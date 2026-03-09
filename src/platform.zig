const builtin = @import("builtin");
const std = @import("std");

pub const Paths = struct {
    data_dir: []u8,
    last_document_path: []u8,

    pub fn deinit(self: *Paths, allocator: std.mem.Allocator) void {
        allocator.free(self.data_dir);
        allocator.free(self.last_document_path);
    }
};

pub fn initPaths(allocator: std.mem.Allocator) !Paths {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.MissingHomeDirectory,
        else => return err,
    };
    defer allocator.free(home);

    const data_dir = if (builtin.os.tag == .macos)
        try std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "sioyek" })
    else blk: {
        if (std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME")) |xdg_data_home| {
            defer allocator.free(xdg_data_home);
            break :blk try std.fs.path.join(allocator, &.{ xdg_data_home, "sioyek" });
        } else |_| {
            break :blk try std.fs.path.join(allocator, &.{ home, ".local", "share", "sioyek" });
        }
    };
    errdefer allocator.free(data_dir);

    try std.fs.makeDirAbsolute(data_dir);

    const last_document_path = try std.fs.path.join(allocator, &.{ data_dir, "last_document_path.txt" });
    return .{
        .data_dir = data_dir,
        .last_document_path = last_document_path,
    };
}

pub fn resolveDocumentPath(allocator: std.mem.Allocator, cli_path: ?[]const u8, paths: *const Paths) ![]u8 {
    if (cli_path) |path| {
        const absolute = try std.fs.cwd().realpathAlloc(allocator, path);
        try writeLastDocumentPath(paths.last_document_path, absolute);
        return absolute;
    }

    const stored = readLastDocumentPath(allocator, paths.last_document_path) catch |err| switch (err) {
        error.FileNotFound => return error.MissingDocumentPath,
        else => return err,
    };
    defer allocator.free(stored);

    return try std.fs.cwd().realpathAlloc(allocator, stored);
}

pub fn writeLastDocumentPath(path_file: []const u8, document_path: []const u8) !void {
    const file = try std.fs.createFileAbsolute(path_file, .{ .truncate = true });
    defer file.close();
    try file.writeAll(document_path);
}

fn readLastDocumentPath(allocator: std.mem.Allocator, path_file: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path_file, .{});
    defer file.close();

    const max_size = 16 * 1024;
    const contents = try file.readToEndAlloc(allocator, max_size);
    defer allocator.free(contents);

    const trimmed = std.mem.trim(u8, contents, " \r\n\t");
    return try allocator.dupe(u8, trimmed);
}
