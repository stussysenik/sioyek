const std = @import("std");
const commands = @import("commands.zig");
const document_mod = @import("document.zig");
const hud_mod = @import("hud.zig");
const index_mod = @import("index.zig");
const platform = @import("platform.zig");
const state_mod = @import("state.zig");

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

const OverlayTexture = struct {
    texture: ?*c.SDL_Texture = null,
    width: i32 = 0,
    height: i32 = 0,

    fn clear(self: *OverlayTexture) void {
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
    page_texture: PageTexture = .{},
    hud_texture: OverlayTexture = .{},
    bookmarks: state_mod.BookmarkStore = .{},
    outline: index_mod.Outline = .{},
    search_results: index_mod.SearchResults = .{},
    search_query: std.ArrayListUnmanaged(u8) = .empty,
    ui_prefs: state_mod.UiPrefs = .{},
    current_page: usize = 0,
    overlay_selection: usize = 0,
    typed_page: ?usize = null,
    zoom: f32 = 1.0,
    fit_to_window: bool = true,
    needs_render: bool = true,
    needs_hud_render: bool = true,
    quit: bool = false,
    outline_loaded: bool = false,
    mode: commands.InteractionMode = .normal,
    show_help_expanded: bool = false,
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

        var ui_prefs = try state_mod.loadUiPrefs(allocator, &paths);
        const show_help_expanded = !ui_prefs.onboarding_acknowledged or ui_prefs.hud_density == .expanded;
        if (!ui_prefs.onboarding_acknowledged) {
            ui_prefs.hud_visible = true;
        }

        const initial_status = if (ui_prefs.onboarding_acknowledged)
            try allocator.dupe(u8, "Press ? for the full guide.")
        else
            try allocator.dupe(u8, "Space: next page, /: search, t: contents, b: bookmark.");
        errdefer allocator.free(initial_status);

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
            .ui_prefs = ui_prefs,
            .current_page = current_page,
            .zoom = zoom,
            .fit_to_window = fit_to_window,
            .show_help_expanded = show_help_expanded,
            .status_message = initial_status,
        };
    }

    pub fn deinit(self: *App) void {
        self.persistSession();
        self.persistBookmarks();
        self.persistUiPrefs();
        self.clearStatus();
        self.search_query.deinit(self.allocator);
        self.search_results.deinit(self.allocator);
        self.outline.deinit(self.allocator);
        self.bookmarks.deinit(self.allocator);
        self.page_texture.clear();
        self.hud_texture.clear();
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
        self.document.deinit(self.allocator);
        self.paths.deinit(self.allocator);
    }

    pub fn run(self: *App) !void {
        try self.renderIfNeeded();
        try self.renderHudIfNeeded();

        while (!self.quit) {
            try self.handleEvents();
            try self.renderIfNeeded();
            try self.renderHudIfNeeded();
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
                        self.needs_hud_render = true;
                    }
                },
                c.SDL_KEYDOWN => try self.handleKeyDown(event.key),
                else => {},
            }
        }
    }

    fn handleKeyDown(self: *App, event: c.SDL_KeyboardEvent) !void {
        const key_press = keyPressFromSdl(event) orelse return;

        if (isEscape(key_press) and self.show_help_expanded) {
            self.closeExpandedHelp();
            try self.updateTitle();
            return;
        }

        if (self.mode == .search_input) {
            try self.handleSearchInputKeyDown(key_press);
            return;
        }

        const page_digit = if (self.mode == .normal) isPageDigit(key_press) else null;
        if (page_digit) |digit| {
            self.acknowledgeOnboardingAction();
            self.typed_page = (self.typed_page orelse 0) * 10 + digit;
            try self.updateTitle();
            return;
        }

        if (try self.dispatchCommand(key_press)) {
            return;
        }

        if (self.mode == .normal and isEscape(key_press)) {
            self.typed_page = null;
            self.clearStatus();
            try self.setStatusFmt("Press ? for the full guide.", .{});
            try self.updateTitle();
            return;
        }

        if (self.mode == .normal) {
            self.typed_page = null;
            try self.updateTitle();
        }
    }

    fn handleSearchInputKeyDown(self: *App, key_press: commands.KeyPress) !void {
        if (try self.dispatchCommand(key_press)) {
            return;
        }

        switch (key_press.key) {
            .special => |special| switch (special) {
                .backspace => {
                    if (self.search_query.items.len > 0) {
                        self.search_query.items.len -= 1;
                    }
                },
                .enter => {
                    self.acknowledgeOnboardingAction();
                    try self.finishSearchInput();
                    return;
                },
                else => {},
            },
            .char => |char| {
                if (!key_press.ctrl and !key_press.alt and !key_press.meta and std.ascii.isPrint(char)) {
                    self.acknowledgeOnboardingAction();
                    try self.search_query.append(self.allocator, char);
                }
            },
        }

        try self.updateTitle();
    }

    fn dispatchCommand(self: *App, key_press: commands.KeyPress) !bool {
        const command_id = commands.commandForKey(self.mode, key_press) orelse return false;
        try self.executeCommand(command_id);
        return true;
    }

    fn executeCommand(self: *App, command_id: commands.CommandId) !void {
        if (command_id != .toggle_help and command_id != .toggle_hud_density and command_id != .cancel) {
            self.acknowledgeOnboardingAction();
        }

        switch (command_id) {
            .next_page => self.setPageDelta(1),
            .previous_page => self.setPageDelta(-1),
            .goto_first_page => self.setPage(0),
            .goto_last_page => self.setPage(self.document.page_count - 1),
            .zoom_in => self.adjustZoom(1.1),
            .zoom_out => self.adjustZoom(1.0 / 1.1),
            .toggle_fit => {
                self.fit_to_window = !self.fit_to_window;
                self.needs_render = true;
                self.persistSession();
            },
            .fit_reset => {
                self.fit_to_window = true;
                self.needs_render = true;
                self.persistSession();
            },
            .start_search => try self.enterSearchInputMode(),
            .search_next => try self.cycleSearchHit(1),
            .search_prev => try self.cycleSearchHit(-1),
            .open_toc => try self.enterTocMode(),
            .toggle_bookmark => try self.toggleBookmark(),
            .prev_bookmark => try self.jumpToPrevBookmark(),
            .next_bookmark => try self.jumpToNextBookmark(),
            .toggle_help => self.toggleHelp(),
            .toggle_hud_density => self.toggleHudDensity(),
            .selection_up => try self.moveSelection(-1),
            .selection_down => try self.moveSelection(1),
            .selection_activate => try self.activateSelection(),
            .cancel => try self.cancelCurrentMode(),
            .quit => self.quit = true,
        }

        try self.updateTitle();
    }

    fn enterSearchInputMode(self: *App) !void {
        self.mode = .search_input;
        self.search_query.clearRetainingCapacity();
        self.clearStatus();
        try self.setStatusFmt("Type a query and press Enter to search.", .{});
    }

    fn finishSearchInput(self: *App) !void {
        if (self.search_query.items.len == 0) {
            self.mode = .normal;
            try self.setStatusFmt("Empty search query.", .{});
            return;
        }

        self.search_results.deinit(self.allocator);
        self.search_results = try index_mod.searchDocument(self.allocator, &self.document, self.search_query.items);
        if (self.search_results.hits.len == 0) {
            self.mode = .normal;
            try self.setStatusFmt("No hits for {s}.", .{self.search_query.items});
            return;
        }

        self.mode = .search_results;
        self.overlay_selection = 0;
        try self.activateSearchHit(0);
    }

    fn cycleSearchHit(self: *App, delta: isize) !void {
        if (self.search_results.hits.len == 0) {
            try self.setStatusFmt("No search results yet.", .{});
            return;
        }

        self.mode = .search_results;
        const current: isize = @intCast(self.overlay_selection);
        const max_index: isize = @intCast(self.search_results.hits.len - 1);
        const next_index = std.math.clamp(current + delta, 0, max_index);
        try self.activateSearchHit(@intCast(next_index));
    }

    fn activateSearchHit(self: *App, index: usize) !void {
        self.overlay_selection = index;
        const hit = self.search_results.hits[index];
        self.setPage(hit.page_index);
        try self.setStatusFmt(
            "Search {d}/{d}: page {d} with {d} hit(s).",
            .{ index + 1, self.search_results.hits.len, hit.page_index + 1, hit.count },
        );
    }

    fn enterTocMode(self: *App) !void {
        try self.loadOutlineIfNeeded();
        if (self.outline.entries.len == 0) {
            try self.setStatusFmt("This document has no outline.", .{});
            return;
        }

        self.mode = .toc;
        self.overlay_selection = index_mod.findNearestOutlineEntry(&self.outline, self.current_page) orelse 0;
        try self.setStatusFmt("TOC mode: arrows or j/k move, Enter opens.", .{});
    }

    fn moveSelection(self: *App, delta: isize) !void {
        switch (self.mode) {
            .toc => {
                if (self.outline.entries.len == 0) return;
                const current: isize = @intCast(self.overlay_selection);
                const max_index: isize = @intCast(self.outline.entries.len - 1);
                self.overlay_selection = @intCast(std.math.clamp(current + delta, 0, max_index));
                const entry = self.outline.entries[self.overlay_selection];
                if (entry.page_index) |page_index| {
                    try self.setStatusFmt("Outline {d}/{d}: {s} (page {d})", .{
                        self.overlay_selection + 1,
                        self.outline.entries.len,
                        preview(entry.title),
                        page_index + 1,
                    });
                } else {
                    try self.setStatusFmt("Outline {d}/{d}: {s}", .{
                        self.overlay_selection + 1,
                        self.outline.entries.len,
                        preview(entry.title),
                    });
                }
            },
            else => {},
        }
    }

    fn activateSelection(self: *App) !void {
        switch (self.mode) {
            .search_results => try self.activateSearchHit(self.overlay_selection),
            .toc => try self.activateSelectedOutline(),
            else => {},
        }
    }

    fn activateSelectedOutline(self: *App) !void {
        if (self.outline.entries.len == 0) return;

        const entry = self.outline.entries[self.overlay_selection];
        if (entry.page_index) |page_index| {
            self.setPage(page_index);
            self.mode = .normal;
            try self.setStatusFmt("Outline: {s}", .{entry.title});
        } else {
            try self.setStatusFmt("Outline entry has no page target.", .{});
        }
    }

    fn toggleBookmark(self: *App) !void {
        const added = try self.bookmarks.toggle(self.allocator, self.current_page);
        self.persistBookmarks();
        try self.setStatusFmt(
            "{s} bookmark at page {d}.",
            .{ if (added) "Added" else "Removed", self.current_page + 1 },
        );
    }

    fn jumpToNextBookmark(self: *App) !void {
        if (self.bookmarks.next(self.current_page)) |page_index| {
            self.setPage(page_index);
            try self.setStatusFmt("Next bookmark: page {d}.", .{page_index + 1});
        } else {
            try self.setStatusFmt("No later bookmark.", .{});
        }
    }

    fn jumpToPrevBookmark(self: *App) !void {
        if (self.bookmarks.prev(self.current_page)) |page_index| {
            self.setPage(page_index);
            try self.setStatusFmt("Previous bookmark: page {d}.", .{page_index + 1});
        } else {
            try self.setStatusFmt("No earlier bookmark.", .{});
        }
    }

    fn cancelCurrentMode(self: *App) !void {
        switch (self.mode) {
            .search_input => {
                self.mode = .normal;
                try self.setStatusFmt("Search cancelled.", .{});
            },
            .search_results => {
                self.mode = .normal;
                try self.setStatusFmt("Back to document.", .{});
            },
            .toc => {
                self.mode = .normal;
                try self.setStatusFmt("Left table of contents.", .{});
            },
            .normal => {},
        }
    }

    fn toggleHelp(self: *App) void {
        self.ui_prefs.hud_visible = true;
        self.show_help_expanded = !self.show_help_expanded;
        self.ui_prefs.hud_density = if (self.show_help_expanded) .expanded else .compact;
        self.ui_prefs.onboarding_acknowledged = true;
        self.persistUiPrefs();
    }

    fn toggleHudDensity(self: *App) void {
        self.toggleHelp();
    }

    fn closeExpandedHelp(self: *App) void {
        self.show_help_expanded = false;
        self.ui_prefs.hud_density = .compact;
        self.ui_prefs.hud_visible = true;
        self.ui_prefs.onboarding_acknowledged = true;
        self.persistUiPrefs();
    }

    fn acknowledgeOnboardingAction(self: *App) void {
        if (self.ui_prefs.onboarding_acknowledged) return;

        self.ui_prefs.onboarding_acknowledged = true;
        self.ui_prefs.hud_visible = true;
        self.ui_prefs.hud_density = .compact;
        self.show_help_expanded = false;
        self.persistUiPrefs();
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

    fn persistUiPrefs(self: *App) void {
        state_mod.saveUiPrefs(self.allocator, &self.paths, self.ui_prefs) catch {};
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

        self.page_texture.clear();
        self.page_texture = .{
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

    fn renderHudIfNeeded(self: *App) !void {
        if (!self.needs_hud_render) {
            return;
        }

        if (!self.ui_prefs.hud_visible and !self.show_help_expanded) {
            self.hud_texture.clear();
            self.needs_hud_render = false;
            return;
        }

        var output_width: i32 = 0;
        var output_height: i32 = 0;
        if (c.SDL_GetRendererOutputSize(self.renderer, &output_width, &output_height) != 0) {
            return error.SdlOutputSizeFailed;
        }

        const hud_svg = try hud_mod.buildSvg(self.allocator, self.hudModel(output_width, output_height));
        defer self.allocator.free(hud_svg);

        var rendered = try document_mod.renderSvg(hud_svg, 1.0);
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

        _ = c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND);

        self.hud_texture.clear();
        self.hud_texture = .{
            .texture = texture,
            .width = rendered.raw.width,
            .height = rendered.raw.height,
        };
        self.needs_hud_render = false;
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

        if (self.page_texture.texture) |texture| {
            var output_width: i32 = 0;
            var output_height: i32 = 0;
            _ = c.SDL_GetRendererOutputSize(self.renderer, &output_width, &output_height);

            const width_f = @as(f32, @floatFromInt(self.page_texture.width));
            const height_f = @as(f32, @floatFromInt(self.page_texture.height));
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

        if (self.hud_texture.texture) |texture| {
            var output_width: i32 = 0;
            var output_height: i32 = 0;
            _ = c.SDL_GetRendererOutputSize(self.renderer, &output_width, &output_height);

            const destination = c.SDL_FRect{
                .x = 0,
                .y = 0,
                .w = @floatFromInt(output_width),
                .h = @floatFromInt(output_height),
            };
            _ = c.SDL_RenderCopyF(self.renderer, texture, null, &destination);
        }

        c.SDL_RenderPresent(self.renderer);
    }

    fn hudModel(self: *App, output_width: i32, output_height: i32) hud_mod.Model {
        return .{
            .viewport_width = output_width,
            .viewport_height = output_height,
            .file_name = std.fs.path.basename(self.document.path),
            .current_page = self.current_page,
            .page_count = self.document.page_count,
            .zoom = self.zoom,
            .fit_to_window = self.fit_to_window,
            .bookmarked = self.bookmarks.contains(self.current_page),
            .mode = self.mode,
            .status_message = self.status_message,
            .typed_page = self.typed_page,
            .search_query = self.search_query.items,
            .search_selection = self.currentSearchSelection(),
            .toc_selection = self.currentTocSelection(),
            .show_expanded = self.show_help_expanded,
            .onboarding_active = !self.ui_prefs.onboarding_acknowledged,
        };
    }

    fn currentSearchSelection(self: *App) ?hud_mod.SearchSelection {
        if (self.search_results.hits.len == 0 or self.mode != .search_results) {
            return null;
        }

        const hit = self.search_results.hits[self.overlay_selection];
        return .{
            .index = self.overlay_selection,
            .total = self.search_results.hits.len,
            .page_index = hit.page_index,
            .count = hit.count,
        };
    }

    fn currentTocSelection(self: *App) ?hud_mod.TocSelection {
        if (self.outline.entries.len == 0 or self.mode != .toc) {
            return null;
        }

        const entry = self.outline.entries[self.overlay_selection];
        return .{
            .index = self.overlay_selection,
            .total = self.outline.entries.len,
            .title = entry.title,
            .page_index = entry.page_index,
        };
    }

    fn updateTitle(self: *App) !void {
        self.needs_hud_render = true;

        var detail: []const u8 = "";
        var owned_detail: ?[]u8 = null;
        var owned_suffix: ?[]u8 = null;
        defer if (owned_detail) |value| self.allocator.free(value);
        defer if (owned_suffix) |value| self.allocator.free(value);

        if (self.show_help_expanded) {
            detail = "shortcut guide";
        } else if (self.typed_page) |typed_page| {
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

fn isEscape(key_press: commands.KeyPress) bool {
    return switch (key_press.key) {
        .special => |special| special == .escape,
        .char => false,
    };
}

fn isPageDigit(key_press: commands.KeyPress) ?usize {
    if (key_press.ctrl or key_press.alt or key_press.meta) return null;
    return switch (key_press.key) {
        .char => |char| if (char >= '0' and char <= '9') @as(usize, @intCast(char - '0')) else null,
        .special => null,
    };
}

fn keyPressFromSdl(event: c.SDL_KeyboardEvent) ?commands.KeyPress {
    const sym = event.keysym.sym;
    const mods: u32 = @intCast(event.keysym.mod);
    const ctrl = (mods & @as(u32, c.KMOD_CTRL)) != 0;
    const alt = (mods & @as(u32, c.KMOD_ALT)) != 0;
    const meta = (mods & @as(u32, c.KMOD_GUI)) != 0;
    const shift = (mods & @as(u32, c.KMOD_SHIFT)) != 0;

    const special_key = switch (sym) {
        c.SDLK_LEFT => commands.SpecialKey.left,
        c.SDLK_RIGHT => commands.SpecialKey.right,
        c.SDLK_UP => commands.SpecialKey.up,
        c.SDLK_DOWN => commands.SpecialKey.down,
        c.SDLK_PAGEUP => commands.SpecialKey.page_up,
        c.SDLK_PAGEDOWN => commands.SpecialKey.page_down,
        c.SDLK_HOME => commands.SpecialKey.home,
        c.SDLK_END => commands.SpecialKey.end,
        c.SDLK_RETURN, c.SDLK_KP_ENTER => commands.SpecialKey.enter,
        c.SDLK_ESCAPE => commands.SpecialKey.escape,
        c.SDLK_SPACE => commands.SpecialKey.space,
        c.SDLK_BACKSPACE => commands.SpecialKey.backspace,
        c.SDLK_F1 => commands.SpecialKey.f1,
        else => null,
    };

    if (special_key) |special| {
        return .{
            .key = .{ .special = special },
            .ctrl = ctrl,
            .alt = alt,
            .meta = meta,
            .shift = shift,
        };
    }

    if (sym >= c.SDLK_a and sym <= c.SDLK_z) {
        const base: u8 = @intCast(sym);
        const value = if (shift) std.ascii.toUpper(base) else base;
        return .{
            .key = .{ .char = value },
            .ctrl = ctrl,
            .alt = alt,
            .meta = meta,
        };
    }

    if (sym >= c.SDLK_0 and sym <= c.SDLK_9) {
        const index: usize = @intCast(sym - c.SDLK_0);
        const shifted = [_]u8{ ')', '!', '@', '#', '$', '%', '^', '&', '*', '(' };
        return .{
            .key = .{ .char = if (shift) shifted[index] else @as(u8, @intCast(sym)) },
            .ctrl = ctrl,
            .alt = alt,
            .meta = meta,
        };
    }

    const printable: ?u8 = switch (sym) {
        c.SDLK_SLASH => if (shift) @as(u8, '?') else @as(u8, '/'),
        c.SDLK_EQUALS => if (shift) @as(u8, '+') else @as(u8, '='),
        c.SDLK_PLUS => @as(u8, '+'),
        c.SDLK_MINUS => if (shift) @as(u8, '_') else @as(u8, '-'),
        c.SDLK_LEFTBRACKET => if (shift) @as(u8, '{') else @as(u8, '['),
        c.SDLK_RIGHTBRACKET => if (shift) @as(u8, '}') else @as(u8, ']'),
        c.SDLK_SEMICOLON => if (shift) @as(u8, ':') else @as(u8, ';'),
        c.SDLK_QUOTE => if (shift) @as(u8, '"') else @as(u8, '\''),
        c.SDLK_COMMA => if (shift) @as(u8, '<') else @as(u8, ','),
        c.SDLK_PERIOD => if (shift) @as(u8, '>') else @as(u8, '.'),
        c.SDLK_BACKQUOTE => if (shift) @as(u8, '~') else @as(u8, '`'),
        else => null,
    };

    if (printable) |char| {
        return .{
            .key = .{ .char = char },
            .ctrl = ctrl,
            .alt = alt,
            .meta = meta,
        };
    }

    return null;
}
