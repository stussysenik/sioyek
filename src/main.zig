const std = @import("std");
const App = @import("app.zig").App;
const Document = @import("document.zig").Document;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip();
    const first_arg = args.next();
    if (first_arg) |arg| {
        if (std.mem.eql(u8, arg, "--check")) {
            const document_path = args.next() orelse return error.MissingDocumentPath;
            return runCheck(allocator, document_path);
        }
        if (std.mem.eql(u8, arg, "--search")) {
            const document_path = args.next() orelse return error.MissingDocumentPath;
            const needle = args.next() orelse return error.MissingSearchTerm;
            return runSearch(allocator, document_path, needle);
        }
        if (std.mem.eql(u8, arg, "--toc")) {
            const document_path = args.next() orelse return error.MissingDocumentPath;
            return runToc(allocator, document_path);
        }
    }

    var app = try App.init(allocator, first_arg);
    defer app.deinit();

    try app.run();
}

fn runCheck(allocator: std.mem.Allocator, document_path: []const u8) !void {
    var document = try Document.open(allocator, document_path);
    defer document.deinit(allocator);

    if (document.page_count == 0) {
        return error.EmptyDocument;
    }

    const page_size = try document.pageSize(0);
    var rendered = try document.renderPage(0, 1.0);
    defer rendered.deinit();

    std.debug.print(
        "ok pages={d} first_page={d}x{d} pt={d:.2}x{d:.2}\n",
        .{
            document.page_count,
            rendered.raw.width,
            rendered.raw.height,
            page_size.width,
            page_size.height,
        },
    );
}

fn runSearch(allocator: std.mem.Allocator, document_path: []const u8, needle: []const u8) !void {
    var document = try Document.open(allocator, document_path);
    defer document.deinit(allocator);

    const lowered_needle = try std.ascii.allocLowerString(allocator, needle);
    defer allocator.free(lowered_needle);

    var total_hits: usize = 0;
    for (0..document.page_count) |page_index| {
        var page_text = try document.pageText(page_index);
        defer page_text.deinit();

        const lowered_page = try std.ascii.allocLowerString(allocator, page_text.slice());
        defer allocator.free(lowered_page);

        const hit_count = countSubstrings(lowered_page, lowered_needle);
        if (hit_count > 0) {
            total_hits += hit_count;
            std.debug.print("page {d}: {d} hit(s)\n", .{ page_index + 1, hit_count });
        }
    }

    std.debug.print("total hits: {d}\n", .{total_hits});
}

fn runToc(allocator: std.mem.Allocator, document_path: []const u8) !void {
    var document = try Document.open(allocator, document_path);
    defer document.deinit(allocator);

    var outline = try document.dumpOutline();
    defer outline.deinit();

    std.debug.print("{s}", .{outline.slice()});
}

fn countSubstrings(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0) {
        return 0;
    }

    var count: usize = 0;
    var start: usize = 0;
    while (start < haystack.len) {
        const found = std.mem.indexOfPos(u8, haystack, start, needle) orelse break;
        count += 1;
        start = found + needle.len;
    }
    return count;
}
