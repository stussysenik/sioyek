const std = @import("std");
const Document = @import("document.zig").Document;
const index_mod = @import("index.zig");

pub const Report = struct {
    iterations: usize,
    page_count: usize,
    outline_entries: usize,
    search_hit_pages: usize,
    search_total_hits: usize,
    open_document: Metric = .{},
    first_page_size: Metric = .{},
    render_first_page: Metric = .{},
    load_outline: Metric = .{},
    search_document: Metric = .{},
};

pub const Metric = struct {
    min_ns: u64 = std.math.maxInt(u64),
    max_ns: u64 = 0,
    total_ns: u128 = 0,
    samples: usize = 0,

    pub fn record(self: *Metric, elapsed_ns: u64) void {
        self.min_ns = @min(self.min_ns, elapsed_ns);
        self.max_ns = @max(self.max_ns, elapsed_ns);
        self.total_ns += elapsed_ns;
        self.samples += 1;
    }

    pub fn avg_ns(self: *const Metric) u64 {
        if (self.samples == 0) return 0;
        return @intCast(self.total_ns / self.samples);
    }
};

pub fn run(allocator: std.mem.Allocator, document_path: []const u8, search_term: []const u8, iterations: usize) !Report {
    var report = Report{
        .iterations = iterations,
        .page_count = 0,
        .outline_entries = 0,
        .search_hit_pages = 0,
        .search_total_hits = 0,
    };

    var iteration: usize = 0;
    while (iteration < iterations) : (iteration += 1) {
        var timer = try std.time.Timer.start();
        var document = try Document.open(allocator, document_path);
        defer document.deinit(allocator);
        report.open_document.record(timer.read());

        report.page_count = document.page_count;

        timer = try std.time.Timer.start();
        _ = try document.pageSize(0);
        report.first_page_size.record(timer.read());

        timer = try std.time.Timer.start();
        var rendered = try document.renderPage(0, 1.0);
        defer rendered.deinit();
        report.render_first_page.record(timer.read());

        timer = try std.time.Timer.start();
        var outline = try index_mod.loadOutline(allocator, &document);
        defer outline.deinit(allocator);
        report.load_outline.record(timer.read());
        report.outline_entries = outline.entries.len;

        timer = try std.time.Timer.start();
        var search_results = try index_mod.searchDocument(allocator, &document, search_term);
        defer search_results.deinit(allocator);
        report.search_document.record(timer.read());
        report.search_hit_pages = search_results.hits.len;

        var total_hits: usize = 0;
        for (search_results.hits) |hit| total_hits += hit.count;
        report.search_total_hits = total_hits;
    }

    return report;
}

pub fn writeJson(allocator: std.mem.Allocator, report: Report) !void {
    const json = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"iterations\": {d},\n  \"page_count\": {d},\n  \"outline_entries\": {d},\n  \"search_hit_pages\": {d},\n  \"search_total_hits\": {d},\n  \"open_document_ns\": {{\"min\": {d}, \"avg\": {d}, \"max\": {d}}},\n  \"first_page_size_ns\": {{\"min\": {d}, \"avg\": {d}, \"max\": {d}}},\n  \"render_first_page_ns\": {{\"min\": {d}, \"avg\": {d}, \"max\": {d}}},\n  \"load_outline_ns\": {{\"min\": {d}, \"avg\": {d}, \"max\": {d}}},\n  \"search_document_ns\": {{\"min\": {d}, \"avg\": {d}, \"max\": {d}}}\n}}\n",
        .{
            report.iterations,
            report.page_count,
            report.outline_entries,
            report.search_hit_pages,
            report.search_total_hits,
            report.open_document.min_ns,
            report.open_document.avg_ns(),
            report.open_document.max_ns,
            report.first_page_size.min_ns,
            report.first_page_size.avg_ns(),
            report.first_page_size.max_ns,
            report.render_first_page.min_ns,
            report.render_first_page.avg_ns(),
            report.render_first_page.max_ns,
            report.load_outline.min_ns,
            report.load_outline.avg_ns(),
            report.load_outline.max_ns,
            report.search_document.min_ns,
            report.search_document.avg_ns(),
            report.search_document.max_ns,
        },
    );
    defer allocator.free(json);

    try std.fs.File.stdout().writeAll(json);
}
