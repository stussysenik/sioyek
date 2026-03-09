const std = @import("std");
const document_mod = @import("document.zig");
const platform = @import("platform.zig");

const c = @cImport({
    @cInclude("SDL.h");
});

const PageTexture = struct {
    texture: ?*c.SDL_Texture = null,
    width: i32 = 0,
    height: i32 = 0,
    page_width: f32 = 0,
    page_height: f32 = 0,
    page_index: usize = 0,
    zoom: f32 = 1.0,

    fn clear(self: *PageTexture) void {
        if (self.texture) |texture| {
            c.SDL_DestroyTexture(texture);
        }
        self.* = .{};
    }
};

pub const App = struct {
    allocator: std.mem.Allocator,
    paths: platform.Paths,
    document: document_mod.Document,
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    texture: PageTexture = .{},
    current_page: usize = 0,
    typed_page: ?usize = null,
    zoom: f32 = 1.0,
    fit_to_window: bool = true,
    needs_render: bool = true,
    quit: bool = false,

    pub fn init(allocator: std.mem.Allocator, cli_document_path: ?[]const u8) !App {
        const paths = try platform.initPaths(allocator);
        errdefer {
            var mutable_paths = paths;
            mutable_paths.deinit(allocator);
        }

        const document_path = try platform.resolveDocumentPath(allocator, cli_document_path, &paths);
        defer allocator.free(document_path);

        const document = try document_mod.Document.open(allocator, document_path);
        errdefer {
            var mutable_document = document;
            mutable_document.deinit(allocator);
        }

        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            return error.SdlInitFailed;
        }
        errdefer c.SDL_Quit();

        const window = c.SDL_CreateWindow(
            "sioyek (zig rewrite)",
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            1280,
            900,
            c.SDL_WINDOW_ALLOW_HIGHDPI | c.SDL_WINDOW_RESIZABLE,
        ) orelse return error.SdlWindowFailed;
        errdefer c.SDL_DestroyWindow(window);

        const renderer = c.SDL_CreateRenderer(
            window,
            -1,
            c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC,
        ) orelse return error.SdlRendererFailed;
        errdefer c.SDL_DestroyRenderer(renderer);

        return .{
            .allocator = allocator,
            .paths = paths,
            .document = document,
            .window = window,
            .renderer = renderer,
        };
    }

    pub fn deinit(self: *App) void {
        self.texture.clear();
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
        self.document.deinit(self.allocator);
        self.paths.deinit(self.allocator);
    }

    pub fn run(self: *App) !void {
        try self.renderIfNeeded();
        while (!self.quit) {
            try self.handleEvents();
            try self.renderIfNeeded();
            self.present();
            c.SDL_Delay(16);
        }
    }

    fn handleEvents(self: *App) !void {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => self.quit = true,
                c.SDL_WINDOWEVENT => {
                    if (event.window.event == c.SDL_WINDOWEVENT_SIZE_CHANGED or event.window.event == c.SDL_WINDOWEVENT_RESIZED) {
                        self.needs_render = true;
                    }
                },
                c.SDL_KEYDOWN => self.handleKeyDown(event.key.keysym.sym),
                else => {},
            }
        }
    }

    fn handleKeyDown(self: *App, key: c.SDL_Keycode) void {
        if (key >= '0' and key <= '9') {
            const digit: usize = @intCast(key - '0');
            self.typed_page = (self.typed_page orelse 0) * 10 + digit;
            self.updateTitle() catch {};
            return;
        }

        switch (key) {
            c.SDLK_ESCAPE, c.SDLK_q => self.quit = true,
            c.SDLK_LEFT, c.SDLK_PAGEUP, c.SDLK_k => self.setPageDelta(-1),
            c.SDLK_RIGHT, c.SDLK_PAGEDOWN, c.SDLK_j, c.SDLK_SPACE => self.setPageDelta(1),
            c.SDLK_HOME => self.setPage(0),
            c.SDLK_END => self.setPage(self.document.page_count - 1),
            c.SDLK_EQUALS, c.SDLK_PLUS => self.adjustZoom(1.1),
            c.SDLK_MINUS, c.SDLK_UNDERSCORE => self.adjustZoom(1.0 / 1.1),
            c.SDLK_0 => {
                self.fit_to_window = true;
                self.needs_render = true;
            },
            c.SDLK_f => {
                self.fit_to_window = !self.fit_to_window;
                self.needs_render = true;
            },
            c.SDLK_RETURN, c.SDLK_KP_ENTER, c.SDLK_g => {
                if (self.typed_page) |typed_page| {
                    if (typed_page > 0) {
                        self.setPage(@min(typed_page - 1, self.document.page_count - 1));
                    }
                    self.typed_page = null;
                }
            },
            else => {
                self.typed_page = null;
                self.updateTitle() catch {};
            },
        }
    }

    fn setPageDelta(self: *App, delta: isize) void {
        const current: isize = @intCast(self.current_page);
        const max_page: isize = @intCast(self.document.page_count - 1);
        const next_page = std.math.clamp(current + delta, 0, max_page);
        self.setPage(@intCast(next_page));
    }

    fn setPage(self: *App, page_index: usize) void {
        self.current_page = page_index;
        self.typed_page = null;
        self.needs_render = true;
    }

    fn adjustZoom(self: *App, factor: f32) void {
        self.fit_to_window = false;
        self.zoom = std.math.clamp(self.zoom * factor, 0.1, 8.0);
        self.needs_render = true;
    }

    fn renderIfNeeded(self: *App) !void {
        if (!self.needs_render) {
            return;
        }

        const page_size = try self.document.pageSize(self.current_page);
        const scale = try self.computeRenderScale(page_size);
        var rendered = try self.document.renderPage(self.current_page, scale);
        defer rendered.deinit();

        const texture = c.SDL_CreateTexture(
            self.renderer,
            c.SDL_PIXELFORMAT_RGBA32,
            c.SDL_TEXTUREACCESS_STATIC,
            rendered.raw.width,
            rendered.raw.height,
        ) orelse return error.SdlTextureFailed;
        errdefer c.SDL_DestroyTexture(texture);

        if (c.SDL_UpdateTexture(texture, null, rendered.raw.pixels, rendered.raw.stride) != 0) {
            return error.SdlTextureUploadFailed;
        }

        _ = c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_NONE);

        self.texture.clear();
        self.texture = .{
            .texture = texture,
            .width = rendered.raw.width,
            .height = rendered.raw.height,
            .page_width = rendered.raw.page_width,
            .page_height = rendered.raw.page_height,
            .page_index = self.current_page,
            .zoom = scale,
        };

        self.needs_render = false;
        try self.updateTitle();
    }

    fn computeRenderScale(self: *App, page_size: document_mod.PageSize) !f32 {
        if (!self.fit_to_window) {
            return self.zoom;
        }

        var output_width: i32 = 0;
        var output_height: i32 = 0;
        if (c.SDL_GetRendererOutputSize(self.renderer, &output_width, &output_height) != 0) {
            return error.SdlOutputSizeFailed;
        }

        const safe_width = @max(output_width - 48, 1);
        const safe_height = @max(output_height - 48, 1);
        const scale_x = @as(f32, @floatFromInt(safe_width)) / page_size.width;
        const scale_y = @as(f32, @floatFromInt(safe_height)) / page_size.height;
        self.zoom = @max(0.1, @min(scale_x, scale_y));
        return self.zoom;
    }

    fn present(self: *App) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, 20, 23, 28, 255);
        _ = c.SDL_RenderClear(self.renderer);

        if (self.texture.texture) |texture| {
            var output_width: i32 = 0;
            var output_height: i32 = 0;
            _ = c.SDL_GetRendererOutputSize(self.renderer, &output_width, &output_height);

            const width_f = @as(f32, @floatFromInt(self.texture.width));
            const height_f = @as(f32, @floatFromInt(self.texture.height));
            const x = (@as(f32, @floatFromInt(output_width)) - width_f) / 2.0;
            const y = (@as(f32, @floatFromInt(output_height)) - height_f) / 2.0;

            const destination = c.SDL_FRect{
                .x = x,
                .y = y,
                .w = width_f,
                .h = height_f,
            };
            _ = c.SDL_RenderCopyF(self.renderer, texture, null, &destination);
        }

        c.SDL_RenderPresent(self.renderer);
    }

    fn updateTitle(self: *App) !void {
        const base_title = try std.fmt.allocPrint(
            self.allocator,
            "sioyek (zig rewrite)  {s}  [{d}/{d}]  zoom {d:.2}x{s}",
            .{
                std.fs.path.basename(self.document.path),
                self.current_page + 1,
                self.document.page_count,
                self.zoom,
                if (self.fit_to_window) " fit" else "",
            },
        );
        defer self.allocator.free(base_title);

        if (self.typed_page) |typed_page| {
            const full_title = try std.fmt.allocPrint(self.allocator, "{s}  goto {d}", .{ base_title, typed_page });
            defer self.allocator.free(full_title);
            _ = c.SDL_SetWindowTitle(self.window, full_title.ptr);
            return;
        }

        _ = c.SDL_SetWindowTitle(self.window, base_title.ptr);
    }
};
