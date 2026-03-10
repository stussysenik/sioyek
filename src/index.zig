const std = @import("std");
const Document = @import("document.zig").Document;

pub const OutlineEntry = struct {
    depth: usize,
    page_index: ?usize,
    title: []u8,
};

pub const Outline = struct {
    entries: []OutlineEntry = &.{},

    pub fn deinit(self: *Outline, allocator: std.mem.Allocator) void {
        for (self.entries) |entry| {
            allocator.free(entry.title);
        }
        if (self.entries.len > 0) allocator.free(self.entries);
        self.* = .{};
    }
};

pub const SearchHit = struct {
    page_index: usize,
    count: usize,
};

pub const SearchResults = struct {
    query: []u8 = &.{},
    hits: []SearchHit = &.{},

    pub fn deinit(self: *SearchResults, allocator: std.mem.Allocator) void {
        if (self.query.len > 0) allocator.free(self.query);
        if (self.hits.len > 0) allocator.free(self.hits);
        self.* = .{};
    }
};

pub fn loadOutline(allocator: std.mem.Allocator, document: *Document) !Outline {
    var outline_text = try document.dumpOutline();
    defer outline_text.deinit();

    var list: std.ArrayListUnmanaged(OutlineEntry) = .empty;
    errdefer {
        for (list.items) |entry| allocator.free(entry.title);
        list.deinit(allocator);
    }

    var lines = std.mem.tokenizeScalar(u8, outline_text.slice(), '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "(no outline)")) continue;

        var indent_bytes: usize = 0;
        while (indent_bytes + 1 < line.len and line[indent_bytes] == ' ' and line[indent_bytes + 1] == ' ') : (indent_bytes += 2) {}
        const depth = indent_bytes / 2;

        const marker_index = std.mem.indexOf(u8, trimmed, "- ") orelse continue;
        const content = trimmed[marker_index + 2 ..];
        const page_marker = std.mem.lastIndexOf(u8, content, " @ page ");

        var page_index: ?usize = null;
        var title_slice = content;
        if (page_marker) |index| {
            title_slice = std.mem.trimRight(u8, content[0..index], " ");
            const page_text = std.mem.trim(u8, content[index + " @ page ".len ..], " ");
            const page_number = std.fmt.parseInt(usize, page_text, 10) catch 0;
            if (page_number > 0) page_index = page_number - 1;
        }

        try list.append(allocator, .{
            .depth = depth,
            .page_index = page_index,
            .title = try allocator.dupe(u8, title_slice),
        });
    }

    return .{ .entries = try list.toOwnedSlice(allocator) };
}

pub fn searchDocument(allocator: std.mem.Allocator, document: *Document, needle: []const u8) !SearchResults {
    var hits: std.ArrayListUnmanaged(SearchHit) = .empty;
    errdefer hits.deinit(allocator);

    const lowered_needle = try std.ascii.allocLowerString(allocator, needle);
    defer allocator.free(lowered_needle);

    for (0..document.page_count) |page_index| {
        var page_text = try document.pageText(page_index);
        defer page_text.deinit();

        const lowered_page = try std.ascii.allocLowerString(allocator, page_text.slice());
        defer allocator.free(lowered_page);

        const hit_count = countSubstrings(lowered_page, lowered_needle);
        if (hit_count > 0) {
            try hits.append(allocator, .{
                .page_index = page_index,
                .count = hit_count,
            });
        }
    }

    return .{
        .query = try allocator.dupe(u8, needle),
        .hits = try hits.toOwnedSlice(allocator),
    };
}

pub fn findNearestOutlineEntry(outline: *const Outline, current_page: usize) ?usize {
    var best_index: ?usize = null;
    for (outline.entries, 0..) |entry, index| {
        if (entry.page_index) |page_index| {
            if (page_index <= current_page) {
                best_index = index;
            } else if (best_index == null) {
                return index;
            } else {
                return best_index;
            }
        }
    }
    return best_index;
}

fn countSubstrings(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0) return 0;

    var count: usize = 0;
    var start: usize = 0;
    while (start < haystack.len) {
        const found = std.mem.indexOfPos(u8, haystack, start, needle) orelse break;
        count += 1;
        start = found + needle.len;
    }
    return count;
}
