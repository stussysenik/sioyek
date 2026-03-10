const std = @import("std");
const App = @import("app.zig").App;
const bench = @import("bench.zig");
const Document = @import("document.zig").Document;
const index_mod = @import("index.zig");

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
        if (std.mem.eql(u8, arg, "--bench")) {
            const document_path = args.next() orelse return error.MissingDocumentPath;
            const search_term = args.next() orelse return error.MissingSearchTerm;
            const iterations_arg = args.next();
            const iterations = if (iterations_arg) |value|
                try std.fmt.parseInt(usize, value, 10)
            else
                5;
            return runBench(allocator, document_path, search_term, iterations);
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

    try writeStdout(
        allocator,
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

    var results = try index_mod.searchDocument(allocator, &document, needle);
    defer results.deinit(allocator);

    var total_hits: usize = 0;
    for (results.hits) |hit| {
        total_hits += hit.count;
        try writeStdout(allocator, "page {d}: {d} hit(s)\n", .{ hit.page_index + 1, hit.count });
    }

    try writeStdout(allocator, "total hits: {d}\n", .{total_hits});
}

fn runToc(allocator: std.mem.Allocator, document_path: []const u8) !void {
    var document = try Document.open(allocator, document_path);
    defer document.deinit(allocator);

    var outline = try document.dumpOutline();
    defer outline.deinit();

    try std.fs.File.stdout().writeAll(outline.slice());
}

fn runBench(allocator: std.mem.Allocator, document_path: []const u8, search_term: []const u8, iterations: usize) !void {
    const report = try bench.run(allocator, document_path, search_term, iterations);
    try bench.writeJson(allocator, report);
}

fn writeStdout(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try std.fs.File.stdout().writeAll(text);
}
