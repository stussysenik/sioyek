const std = @import("std");

pub const c = @cImport({
    @cInclude("mupdf_wrapper.h");
});

pub const PageSize = struct {
    width: f32,
    height: f32,
};

pub const RenderedPage = struct {
    raw: c.SioyekRenderedPage,

    pub fn deinit(self: *RenderedPage) void {
        c.sioyek_mupdf_free_rendered_page(&self.raw);
        self.* = undefined;
    }
};

pub const OwnedString = struct {
    raw: [*c]u8,

    pub fn slice(self: OwnedString) []const u8 {
        return std.mem.span(self.raw);
    }

    pub fn deinit(self: *OwnedString) void {
        c.sioyek_mupdf_free_string(self.raw);
        self.* = undefined;
    }
};

pub const Document = struct {
    raw: *c.SioyekMupdfDocument,
    path: []u8,
    page_count: usize,

    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Document {
        var error_buffer: [512]u8 = [_]u8{0} ** 512;
        const raw = c.sioyek_mupdf_open_document(path.ptr, &error_buffer, error_buffer.len) orelse {
            return error.OpenDocumentFailed;
        };
        errdefer c.sioyek_mupdf_close_document(raw);

        const owned_path = try allocator.dupe(u8, path);
        errdefer allocator.free(owned_path);

        return .{
            .raw = raw,
            .path = owned_path,
            .page_count = @intCast(c.sioyek_mupdf_page_count(raw)),
        };
    }

    pub fn deinit(self: *Document, allocator: std.mem.Allocator) void {
        c.sioyek_mupdf_close_document(self.raw);
        allocator.free(self.path);
        self.* = undefined;
    }

    pub fn pageSize(self: *Document, page_index: usize) !PageSize {
        var width: f32 = 0;
        var height: f32 = 0;
        var error_buffer: [512]u8 = [_]u8{0} ** 512;
        const ok = c.sioyek_mupdf_get_page_size(
            self.raw,
            @intCast(page_index),
            &width,
            &height,
            &error_buffer,
            error_buffer.len,
        );
        if (ok == 0) {
            return error.GetPageSizeFailed;
        }

        return .{ .width = width, .height = height };
    }

    pub fn renderPage(self: *Document, page_index: usize, scale: f32) !RenderedPage {
        var error_buffer: [512]u8 = [_]u8{0} ** 512;
        const raw = c.sioyek_mupdf_render_page(
            self.raw,
            @intCast(page_index),
            scale,
            &error_buffer,
            error_buffer.len,
        );
        if (raw.pixels == null or raw.width <= 0 or raw.height <= 0 or raw.stride <= 0) {
            return error.RenderPageFailed;
        }

        return .{ .raw = raw };
    }

    pub fn pageText(self: *Document, page_index: usize) !OwnedString {
        var error_buffer: [512]u8 = [_]u8{0} ** 512;
        const raw = c.sioyek_mupdf_page_text(
            self.raw,
            @intCast(page_index),
            &error_buffer,
            error_buffer.len,
        ) orelse return error.PageTextFailed;

        return .{ .raw = raw };
    }

    pub fn dumpOutline(self: *Document) !OwnedString {
        var error_buffer: [512]u8 = [_]u8{0} ** 512;
        const raw = c.sioyek_mupdf_dump_outline(
            self.raw,
            &error_buffer,
            error_buffer.len,
        ) orelse return error.OutlineFailed;

        return .{ .raw = raw };
    }
};
