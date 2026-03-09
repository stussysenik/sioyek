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
