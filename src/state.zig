const std = @import("std");
const Paths = @import("platform.zig").Paths;

pub const SessionState = struct {
    current_page: usize = 0,
    zoom: f32 = 1.0,
    fit_to_window: bool = true,
};

pub const HudDensity = enum {
    compact,
    expanded,
};

pub const UiPrefs = struct {
    hud_visible: bool = true,
    hud_density: HudDensity = .compact,
    onboarding_acknowledged: bool = false,
};

pub const BookmarkStore = struct {
    pages: std.ArrayListUnmanaged(usize) = .empty,

    pub fn deinit(self: *BookmarkStore, allocator: std.mem.Allocator) void {
        self.pages.deinit(allocator);
        self.* = .{};
    }

    pub fn count(self: *const BookmarkStore) usize {
        return self.pages.items.len;
    }

    pub fn contains(self: *const BookmarkStore, page_index: usize) bool {
        return self.indexOf(page_index) != null;
    }

    pub fn toggle(self: *BookmarkStore, allocator: std.mem.Allocator, page_index: usize) !bool {
        if (self.indexOf(page_index)) |index| {
            _ = self.pages.orderedRemove(index);
            return false;
        }

        try self.insertSorted(allocator, page_index);
        return true;
    }

    pub fn next(self: *const BookmarkStore, current_page: usize) ?usize {
        var best: ?usize = null;
        for (self.pages.items) |page_index| {
            if (page_index > current_page and (best == null or page_index < best.?)) {
                best = page_index;
            }
        }
        return best;
    }

    pub fn prev(self: *const BookmarkStore, current_page: usize) ?usize {
        var best: ?usize = null;
        for (self.pages.items) |page_index| {
            if (page_index < current_page and (best == null or page_index > best.?)) {
                best = page_index;
            }
        }
        return best;
    }

    fn indexOf(self: *const BookmarkStore, page_index: usize) ?usize {
        for (self.pages.items, 0..) |value, index| {
            if (value == page_index) return index;
        }
        return null;
    }

    fn insertSorted(self: *BookmarkStore, allocator: std.mem.Allocator, page_index: usize) !void {
        var insert_at: usize = 0;
        while (insert_at < self.pages.items.len and self.pages.items[insert_at] < page_index) : (insert_at += 1) {}
        try self.pages.insert(allocator, insert_at, page_index);
    }
};

pub fn loadSession(allocator: std.mem.Allocator, paths: *const Paths, document_path: []const u8) !?SessionState {
    const file_path = try stateFilePath(allocator, paths, document_path, "session");
    defer allocator.free(file_path);

    const file = std.fs.openFileAbsolute(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 8 * 1024);
    defer allocator.free(contents);

    var state = SessionState{};
    var lines = std.mem.tokenizeScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \r\t");
        if (std.mem.startsWith(u8, line, "page=")) {
            state.current_page = try std.fmt.parseInt(usize, line["page=".len..], 10);
        } else if (std.mem.startsWith(u8, line, "zoom=")) {
            state.zoom = try std.fmt.parseFloat(f32, line["zoom=".len..]);
        } else if (std.mem.startsWith(u8, line, "fit=")) {
            state.fit_to_window = std.mem.eql(u8, line["fit=".len..], "1");
        }
    }

    return state;
}

pub fn saveSession(allocator: std.mem.Allocator, paths: *const Paths, document_path: []const u8, state: SessionState) !void {
    const file_path = try stateFilePath(allocator, paths, document_path, "session");
    defer allocator.free(file_path);

    const file = try std.fs.createFileAbsolute(file_path, .{ .truncate = true });
    defer file.close();

    const contents = try std.fmt.allocPrint(
        allocator,
        "page={d}\nzoom={d:.4}\nfit={d}\n",
        .{ state.current_page, state.zoom, if (state.fit_to_window) @as(u8, 1) else @as(u8, 0) },
    );
    defer allocator.free(contents);
    try file.writeAll(contents);
}

pub fn loadBookmarks(allocator: std.mem.Allocator, paths: *const Paths, document_path: []const u8) !BookmarkStore {
    const file_path = try stateFilePath(allocator, paths, document_path, "bookmarks");
    defer allocator.free(file_path);

    const file = std.fs.openFileAbsolute(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 32 * 1024);
    defer allocator.free(contents);

    var store = BookmarkStore{};
    errdefer store.deinit(allocator);

    var lines = std.mem.tokenizeScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \r\t");
        if (line.len == 0) continue;
        const page_index = try std.fmt.parseInt(usize, line, 10);
        if (!store.contains(page_index)) {
            try store.insertSorted(allocator, page_index);
        }
    }

    return store;
}

pub fn loadUiPrefs(allocator: std.mem.Allocator, paths: *const Paths) !UiPrefs {
    const file_path = try uiPrefsFilePath(allocator, paths);
    defer allocator.free(file_path);

    const file = std.fs.openFileAbsolute(file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 8 * 1024);
    defer allocator.free(contents);

    return parseUiPrefs(contents);
}

pub fn saveUiPrefs(allocator: std.mem.Allocator, paths: *const Paths, prefs: UiPrefs) !void {
    const file_path = try uiPrefsFilePath(allocator, paths);
    defer allocator.free(file_path);

    const file = try std.fs.createFileAbsolute(file_path, .{ .truncate = true });
    defer file.close();

    const contents = try formatUiPrefs(allocator, prefs);
    defer allocator.free(contents);

    try file.writeAll(contents);
}

pub fn saveBookmarks(allocator: std.mem.Allocator, paths: *const Paths, document_path: []const u8, store: *const BookmarkStore) !void {
    const file_path = try stateFilePath(allocator, paths, document_path, "bookmarks");
    defer allocator.free(file_path);

    const file = try std.fs.createFileAbsolute(file_path, .{ .truncate = true });
    defer file.close();

    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(allocator);

    for (store.pages.items) |page_index| {
        try buffer.writer(allocator).print("{d}\n", .{page_index});
    }
    try file.writeAll(buffer.items);
}

fn stateFilePath(allocator: std.mem.Allocator, paths: *const Paths, document_path: []const u8, extension: []const u8) ![]u8 {
    const key = try documentKey(allocator, document_path);
    defer allocator.free(key);
    const file_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ key, extension });
    defer allocator.free(file_name);
    return try std.fs.path.join(allocator, &.{ paths.rewrite_state_dir, file_name });
}

fn uiPrefsFilePath(allocator: std.mem.Allocator, paths: *const Paths) ![]u8 {
    return try std.fs.path.join(allocator, &.{ paths.rewrite_state_dir, "ui_prefs.state" });
}

fn parseUiPrefs(contents: []const u8) UiPrefs {
    var prefs = UiPrefs{};
    var lines = std.mem.tokenizeScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \r\t");
        if (std.mem.startsWith(u8, line, "hud_visible=")) {
            prefs.hud_visible = std.mem.eql(u8, line["hud_visible=".len..], "1");
        } else if (std.mem.startsWith(u8, line, "hud_density=")) {
            prefs.hud_density = if (std.mem.eql(u8, line["hud_density=".len..], "expanded")) .expanded else .compact;
        } else if (std.mem.startsWith(u8, line, "onboarding_acknowledged=")) {
            prefs.onboarding_acknowledged = std.mem.eql(u8, line["onboarding_acknowledged=".len..], "1");
        }
    }
    return prefs;
}

fn formatUiPrefs(allocator: std.mem.Allocator, prefs: UiPrefs) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "hud_visible={d}\nhud_density={s}\nonboarding_acknowledged={d}\n",
        .{
            if (prefs.hud_visible) @as(u8, 1) else @as(u8, 0),
            @tagName(prefs.hud_density),
            if (prefs.onboarding_acknowledged) @as(u8, 1) else @as(u8, 0),
        },
    );
}

fn documentKey(allocator: std.mem.Allocator, document_path: []const u8) ![]u8 {
    const hash = std.hash.Wyhash.hash(0, document_path);
    return std.fmt.allocPrint(allocator, "{x}", .{hash});
}

test "ui prefs parse and format round trip" {
    const allocator = std.testing.allocator;
    const encoded = try formatUiPrefs(allocator, .{
        .hud_visible = true,
        .hud_density = .expanded,
        .onboarding_acknowledged = true,
    });
    defer allocator.free(encoded);

    const decoded = parseUiPrefs(encoded);
    try std.testing.expect(decoded.hud_visible);
    try std.testing.expectEqual(HudDensity.expanded, decoded.hud_density);
    try std.testing.expect(decoded.onboarding_acknowledged);
}
