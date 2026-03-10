const std = @import("std");
const document_mod = @import("document.zig");
const index_mod = @import("index.zig");
const platform = @import("platform.zig");
const state_mod = @import("state.zig");

const c = @cImport({
    @cInclude("SDL.h");
});

const InteractionMode = enum {
    normal,
    search_input,
    search_results,
    toc,
};

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
    bookmarks: state_mod.BookmarkStore = .{},
    outline: index_mod.Outline = .{},
    search_results: index_mod.SearchResults = .{},
    search_query: std.ArrayListUnmanaged(u8) = .empty,
    current_page: usize = 0,
    overlay_selection: usize = 0,
    typed_page: ?usize = null,
    zoom: f32 = 1.0,
    fit_to_window: bool = true,
    needs_render: bool = true,
    quit: bool = false,
    outline_loaded: bool = false,
    mode: InteractionMode = .normal,
    status_message: []u8 = &.{},

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

        const bookmarks = try state_mod.loadBookmarks(allocator, &paths, document.path);
        errdefer {
            var mutable_bookmarks = bookmarks;
            mutable_bookmarks.deinit(allocator);
        }

        var current_page: usize = 0;
        var zoom: f32 = 1.0;
        var fit_to_window = true;
        if (try state_mod.loadSession(allocator, &paths, document.path)) |session| {
            if (document.page_count > 0) {
                current_page = @min(session.current_page, document.page_count - 1);
            }
            zoom = session.zoom;
            fit_to_window = session.fit_to_window;
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
            .bookmarks = bookmarks,
            .current_page = current_page,
            .zoom = zoom,
            .fit_to_window = fit_to_window,
        };
    }

    pub fn deinit(self: *App) void {
        self.persistSession();
        self.persistBookmarks();
        self.clearStatus();
        self.search_query.deinit(self.allocator);
        self.search_results.deinit(self.allocator);
        self.outline.deinit(self.allocator);
        self.bookmarks.deinit(self.allocator);
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
                c.SDL_KEYDOWN => try self.handleKeyDown(event.key.keysym.sym),
                else => {},
            }
        }
    }

    fn handleKeyDown(self: *App, key: c.SDL_Keycode) !void {
        switch (self.mode) {
            .search_input => return self.handleSearchInputKeyDown(key),
            .search_results => {
                if (try self.handleSearchResultsKeyDown(key)) return;
            },
            .toc => {
                if (try self.handleTocKeyDown(key)) return;
            },
            .normal => {},
        }

        if (key >= '0' and key <= '9') {
            const digit: usize = @intCast(key - '0');
            self.typed_page = (self.typed_page orelse 0) * 10 + digit;
            try self.updateTitle();
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
                self.persistSession();
            },
            c.SDLK_f => {
                self.fit_to_window = !self.fit_to_window;
                self.needs_render = true;
                self.persistSession();
            },
            c.SDLK_RETURN, c.SDLK_KP_ENTER, c.SDLK_g => {
                if (self.typed_page) |typed_page| {
                    if (typed_page > 0) {
                        self.setPage(@min(typed_page - 1, self.document.page_count - 1));
                    }
                    self.typed_page = null;
                }
            },
            '/' => try self.enterSearchInputMode(),
            'n' => try self.cycleSearchHit(1),
            'p' => try self.cycleSearchHit(-1),
            't' => try self.enterTocMode(),
            'b' => try self.toggleBookmark(),
            '[' => try self.jumpToPrevBookmark(),
            ']' => try self.jumpToNextBookmark(),
            else => {
                self.typed_page = null;
            },
        }

        try self.updateTitle();
    }

    fn handleSearchInputKeyDown(self: *App, key: c.SDL_Keycode) !void {
        switch (key) {
            c.SDLK_ESCAPE => {
                self.mode = .normal;
                self.clearStatus();
            },
            c.SDLK_BACKSPACE => {
                if (self.search_query.items.len > 0) {
                    self.search_query.items.len -= 1;
                }
            },
            c.SDLK_RETURN, c.SDLK_KP_ENTER => try self.finishSearchInput(),
            else => {
                if (key >= 32 and key <= 126) {
                    try self.search_query.append(self.allocator, @intCast(key));
                }
            },
        }
        try self.updateTitle();
    }

    fn handleSearchResultsKeyDown(self: *App, key: c.SDL_Keycode) !bool {
        switch (key) {
            c.SDLK_ESCAPE => {
                self.mode = .normal;
                self.clearStatus();
                try self.updateTitle();
                return true;
            },
            c.SDLK_n, c.SDLK_DOWN, c.SDLK_j => {
                try self.cycleSearchHit(1);
                return true;
            },
            c.SDLK_p, c.SDLK_UP, c.SDLK_k => {
                try self.cycleSearchHit(-1);
                return true;
            },
            c.SDLK_RETURN, c.SDLK_KP_ENTER => {
                try self.activateSearchHit(self.overlay_selection);
                return true;
            },
            '/' => {
                try self.enterSearchInputMode();
                return true;
            },
            else => return false,
        }
    }

    fn handleTocKeyDown(self: *App, key: c.SDL_Keycode) !bool {
        switch (key) {
            c.SDLK_ESCAPE => {
                self.mode = .normal;
                self.clearStatus();
                try self.updateTitle();
                return true;
            },
            c.SDLK_UP, c.SDLK_k => {
                if (self.overlay_selection > 0) self.overlay_selection -= 1;
                try self.printTocPreview();
                try self.updateTitle();
                return true;
            },
            c.SDLK_DOWN, c.SDLK_j => {
                if (self.overlay_selection + 1 < self.outline.entries.len) self.overlay_selection += 1;
                try self.printTocPreview();
                try self.updateTitle();
                return true;
            },
            c.SDLK_PAGEUP => {
                self.overlay_selection = self.overlay_selection -| 10;
                try self.printTocPreview();
                try self.updateTitle();
                return true;
            },
            c.SDLK_PAGEDOWN => {
                if (self.outline.entries.len > 0) {
                    self.overlay_selection = @min(self.overlay_selection + 10, self.outline.entries.len - 1);
                }
                try self.printTocPreview();
                try self.updateTitle();
                return true;
            },
            c.SDLK_RETURN, c.SDLK_KP_ENTER => {
                try self.activateSelectedOutline();
                return true;
            },
            else => return false,
        }
    }

    fn enterSearchInputMode(self: *App) !void {
        self.mode = .search_input;
        self.search_query.clearRetainingCapacity();
        self.clearStatus();
        try self.setStatusFmt("search mode", .{});
        try self.updateTitle();
    }

    fn finishSearchInput(self: *App) !void {
        if (self.search_query.items.len == 0) {
            self.mode = .normal;
            try self.setStatusFmt("empty search query", .{});
            try self.updateTitle();
            return;
        }

        self.search_results.deinit(self.allocator);
        self.search_results = try index_mod.searchDocument(self.allocator, &self.document, self.search_query.items);
        if (self.search_results.hits.len == 0) {
            self.mode = .normal;
            try self.setStatusFmt("no hits for {s}", .{self.search_query.items});
            try self.updateTitle();
            return;
        }

        self.mode = .search_results;
        self.overlay_selection = 0;
        try self.activateSearchHit(0);
        try self.printSearchPreview();
    }

    fn cycleSearchHit(self: *App, delta: isize) !void {
        if (self.search_results.hits.len == 0) {
            try self.setStatusFmt("no search results", .{});
            try self.updateTitle();
            return;
        }

        self.mode = .search_results;
        const current: isize = @intCast(self.overlay_selection);
        const max_index: isize = @intCast(self.search_results.hits.len - 1);
        const next_index = std.math.clamp(current + delta, 0, max_index);
        try self.activateSearchHit(@intCast(next_index));
        try self.printSearchPreview();
    }

    fn activateSearchHit(self: *App, index: usize) !void {
        self.overlay_selection = index;
        const hit = self.search_results.hits[index];
        self.setPage(hit.page_index);
        try self.setStatusFmt(
            "search {d}/{d}: page {d} ({d} hit(s))",
            .{ index + 1, self.search_results.hits.len, hit.page_index + 1, hit.count },
        );
        try self.updateTitle();
    }

    fn enterTocMode(self: *App) !void {
        try self.loadOutlineIfNeeded();
        if (self.outline.entries.len == 0) {
            try self.setStatusFmt("document has no outline", .{});
            try self.updateTitle();
            return;
        }

        self.mode = .toc;
        self.overlay_selection = index_mod.findNearestOutlineEntry(&self.outline, self.current_page) orelse 0;
        try self.printTocPreview();
        try self.updateTitle();
    }

    fn activateSelectedOutline(self: *App) !void {
        if (self.outline.entries.len == 0) return;

        const entry = self.outline.entries[self.overlay_selection];
        if (entry.page_index) |page_index| {
            self.setPage(page_index);
            self.mode = .normal;
            try self.setStatusFmt("outline: {s}", .{entry.title});
        } else {
            try self.setStatusFmt("outline entry has no page target", .{});
        }
        try self.updateTitle();
    }

    fn toggleBookmark(self: *App) !void {
        const added = try self.bookmarks.toggle(self.allocator, self.current_page);
        self.persistBookmarks();
        try self.setStatusFmt(
            "{s} bookmark at page {d}",
            .{ if (added) "added" else "removed", self.current_page + 1 },
        );
        try self.updateTitle();
    }

    fn jumpToNextBookmark(self: *App) !void {
        if (self.bookmarks.next(self.current_page)) |page_index| {
            self.setPage(page_index);
            try self.setStatusFmt("next bookmark: page {d}", .{page_index + 1});
        } else {
            try self.setStatusFmt("no later bookmark", .{});
        }
        try self.updateTitle();
    }

    fn jumpToPrevBookmark(self: *App) !void {
        if (self.bookmarks.prev(self.current_page)) |page_index| {
            self.setPage(page_index);
            try self.setStatusFmt("previous bookmark: page {d}", .{page_index + 1});
        } else {
            try self.setStatusFmt("no earlier bookmark", .{});
        }
        try self.updateTitle();
    }

    fn loadOutlineIfNeeded(self: *App) !void {
        if (self.outline_loaded) return;
        self.outline.deinit(self.allocator);
        self.outline = try index_mod.loadOutline(self.allocator, &self.document);
        self.outline_loaded = true;
    }

    fn persistSession(self: *App) void {
        state_mod.saveSession(
            self.allocator,
            &self.paths,
            self.document.path,
            .{
                .current_page = self.current_page,
                .zoom = self.zoom,
                .fit_to_window = self.fit_to_window,
            },
        ) catch {};
    }

    fn persistBookmarks(self: *App) void {
        state_mod.saveBookmarks(self.allocator, &self.paths, self.document.path, &self.bookmarks) catch {};
    }

    fn clearStatus(self: *App) void {
        if (self.status_message.len > 0) {
            self.allocator.free(self.status_message);
        }
        self.status_message = &.{};
    }

    fn setStatusFmt(self: *App, comptime fmt: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, fmt, args);
        self.clearStatus();
        self.status_message = message;
    }

    fn printTocPreview(self: *App) !void {
        if (self.outline.entries.len == 0) return;

        const start = self.overlay_selection -| 4;
        const end = @min(self.overlay_selection + 5, self.outline.entries.len);
        std.debug.print("TOC preview:\n", .{});
        for (self.outline.entries[start..end], start..) |entry, index| {
            const marker = if (index == self.overlay_selection) ">" else " ";
            const page_text = if (entry.page_index) |page_index|
                try std.fmt.allocPrint(self.allocator, "page {d}", .{page_index + 1})
            else
                try self.allocator.dupe(u8, "no-page");
            defer self.allocator.free(page_text);
            std.debug.print(
                "{s} {s}{s} ({s})\n",
                .{
                    marker,
                    indentPrefix(entry.depth),
                    preview(entry.title),
                    page_text,
                },
            );
        }
    }

    fn printSearchPreview(self: *App) !void {
        if (self.search_results.hits.len == 0) return;

        const start = self.overlay_selection -| 4;
        const end = @min(self.overlay_selection + 5, self.search_results.hits.len);
        std.debug.print("Search results for \"{s}\":\n", .{self.search_results.query});
        for (self.search_results.hits[start..end], start..) |hit, index| {
            const marker = if (index == self.overlay_selection) ">" else " ";
            std.debug.print(
                "{s} page {d}: {d} hit(s)\n",
                .{ marker, hit.page_index + 1, hit.count },
            );
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
        self.persistSession();
    }

    fn adjustZoom(self: *App, factor: f32) void {
        self.fit_to_window = false;
        self.zoom = std.math.clamp(self.zoom * factor, 0.1, 8.0);
        self.needs_render = true;
        self.persistSession();
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
        var detail: []const u8 = "";
        var owned_detail: ?[]u8 = null;
        var owned_suffix: ?[]u8 = null;
        defer if (owned_detail) |value| self.allocator.free(value);
        defer if (owned_suffix) |value| self.allocator.free(value);

        if (self.typed_page) |typed_page| {
            owned_detail = try std.fmt.allocPrint(self.allocator, "goto {d}", .{typed_page});
            detail = owned_detail.?;
        } else switch (self.mode) {
            .search_input => {
                owned_detail = try std.fmt.allocPrint(self.allocator, "search> {s}", .{self.search_query.items});
                detail = owned_detail.?;
            },
            .search_results => {
                if (self.search_results.hits.len > 0) {
                    const hit = self.search_results.hits[self.overlay_selection];
                    owned_detail = try std.fmt.allocPrint(
                        self.allocator,
                        "search {d}/{d} \"{s}\" page {d}",
                        .{ self.overlay_selection + 1, self.search_results.hits.len, self.search_results.query, hit.page_index + 1 },
                    );
                    detail = owned_detail.?;
                }
            },
            .toc => {
                if (self.outline.entries.len > 0) {
                    const entry = self.outline.entries[self.overlay_selection];
                    owned_detail = try std.fmt.allocPrint(
                        self.allocator,
                        "toc {d}/{d} {s}",
                        .{ self.overlay_selection + 1, self.outline.entries.len, preview(entry.title) },
                    );
                    detail = owned_detail.?;
                }
            },
            .normal => {
                if (self.status_message.len > 0) {
                    detail = self.status_message;
                }
            },
        }

        const suffix = if (detail.len > 0) blk: {
            owned_suffix = try std.fmt.allocPrint(self.allocator, "  | {s}", .{detail});
            break :blk owned_suffix.?;
        } else "";

        const title = try std.fmt.allocPrint(
            self.allocator,
            "sioyek (zig rewrite)  {s}  [{d}/{d}]  zoom {d:.2}x{s}{s}{s}",
            .{
                std.fs.path.basename(self.document.path),
                self.current_page + 1,
                self.document.page_count,
                self.zoom,
                if (self.fit_to_window) " fit" else "",
                if (self.bookmarks.contains(self.current_page)) "  [bookmarked]" else "",
                suffix,
            },
        );
        defer self.allocator.free(title);
        const z_title = try self.allocator.alloc(u8, title.len + 1);
        defer self.allocator.free(z_title);
        @memcpy(z_title[0..title.len], title);
        z_title[title.len] = 0;

        _ = c.SDL_SetWindowTitle(self.window, z_title.ptr);
    }
};

fn preview(text: []const u8) []const u8 {
    return text[0..@min(text.len, 48)];
}

fn indentPrefix(depth: usize) []const u8 {
    return switch (@min(depth, 5)) {
        0 => "",
        1 => "  ",
        2 => "    ",
        3 => "      ",
        4 => "        ",
        else => "          ",
    };
}
