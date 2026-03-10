const std = @import("std");
const commands = @import("commands.zig");

pub const SearchSelection = struct {
    index: usize,
    total: usize,
    page_index: usize,
    count: usize,
};

pub const TocSelection = struct {
    index: usize,
    total: usize,
    title: []const u8,
    page_index: ?usize,
};

pub const Model = struct {
    viewport_width: i32,
    viewport_height: i32,
    file_name: []const u8,
    current_page: usize,
    page_count: usize,
    zoom: f32,
    fit_to_window: bool,
    bookmarked: bool,
    mode: commands.InteractionMode,
    status_message: []const u8,
    typed_page: ?usize = null,
    search_query: []const u8 = "",
    search_selection: ?SearchSelection = null,
    toc_selection: ?TocSelection = null,
    show_expanded: bool,
    onboarding_active: bool,
};

pub fn buildSvg(allocator: std.mem.Allocator, model: Model) ![]u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buffer.deinit(allocator);

    const width: usize = @intCast(@max(model.viewport_width, 1));
    const height: usize = @intCast(@max(model.viewport_height, 1));

    try buffer.writer(allocator).print(
        \\<svg xmlns="http://www.w3.org/2000/svg" width="{d}" height="{d}" viewBox="0 0 {d} {d}">
        \\<style>
        \\.title {{ font-family: Helvetica, Arial, sans-serif; font-size: 22px; font-weight: 700; fill: #f5f9ff; }}
        \\.heading {{ font-family: Helvetica, Arial, sans-serif; font-size: 13px; font-weight: 700; fill: #8fb2d6; text-transform: uppercase; letter-spacing: 0.8px; }}
        \\.body {{ font-family: Helvetica, Arial, sans-serif; font-size: 15px; fill: #e7edf4; }}
        \\.body-muted {{ font-family: Helvetica, Arial, sans-serif; font-size: 14px; fill: #afc2d6; }}
        \\.action {{ font-family: Courier, monospace; font-size: 14px; fill: #f5f9ff; }}
        \\.accent {{ font-family: Courier, monospace; font-size: 14px; fill: #b8ffb0; }}
        \\</style>
        \\
    , .{ width, height, width, height });

    if (model.show_expanded) {
        try appendExpanded(&buffer, allocator, model, width, height);
    } else {
        try appendCompact(&buffer, allocator, model, width, height);
    }

    try buffer.appendSlice(allocator, "</svg>");
    return buffer.toOwnedSlice(allocator);
}

fn appendCompact(
    buffer: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    model: Model,
    viewport_width: usize,
    viewport_height: usize,
) !void {
    _ = viewport_height;
    const action_ids = commands.compactCommands(model.mode);
    const line_count = 6 + action_ids.len;
    const panel_width = @min(viewport_width -| 32, 470);
    const panel_height = @min(@max(214, 48 + line_count * 22), 360);
    const x = 16;
    const y = 16;

    try drawPanel(buffer, allocator, x, y, panel_width, panel_height, false);

    var text_y: usize = y + 34;
    try appendText(buffer, allocator, x + 20, text_y, "title", "Sioyek Zig");
    text_y += 28;

    const file_line = try std.fmt.allocPrint(allocator, "File  {s}", .{truncate(model.file_name, 48)});
    defer allocator.free(file_line);
    try appendText(buffer, allocator, x + 20, text_y, "body", file_line);
    text_y += 22;

    const location_line = try std.fmt.allocPrint(
        allocator,
        "Page  {d}/{d}  Zoom  {d:.2}x{s}{s}",
        .{
            model.current_page + 1,
            model.page_count,
            model.zoom,
            if (model.fit_to_window) " fit" else "",
            if (model.bookmarked) "  Bookmarked" else "",
        },
    );
    defer allocator.free(location_line);
    try appendText(buffer, allocator, x + 20, text_y, "body", location_line);
    text_y += 22;

    const mode_line = try std.fmt.allocPrint(allocator, "Mode  {s}", .{commands.modeLabel(model.mode)});
    defer allocator.free(mode_line);
    try appendText(buffer, allocator, x + 20, text_y, "body", mode_line);
    text_y += 24;

    const status_line = try compactStatusLine(allocator, model);
    defer allocator.free(status_line);
    try appendText(buffer, allocator, x + 20, text_y, "body-muted", status_line);
    text_y += 28;

    try appendText(buffer, allocator, x + 20, text_y, "heading", "Next actions");
    text_y += 22;

    for (action_ids) |command_id| {
        const action_line = try actionLine(allocator, command_id);
        defer allocator.free(action_line);
        try appendText(buffer, allocator, x + 20, text_y, "action", action_line);
        text_y += 20;
    }

    if (model.mode == .normal) {
        const page_jump = "1-9 then Enter  jump to page";
        try appendText(buffer, allocator, x + 20, text_y, "accent", page_jump);
    }
}

fn appendExpanded(
    buffer: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    model: Model,
    viewport_width: usize,
    viewport_height: usize,
) !void {
    try buffer.writer(allocator).print(
        "<rect x=\"0\" y=\"0\" width=\"{d}\" height=\"{d}\" fill=\"#081018\" fill-opacity=\"0.70\"/>",
        .{ viewport_width, viewport_height },
    );

    const help_ids = commands.helpCommands(model.mode);
    const section_count = 5;
    const intro_lines: usize = if (model.onboarding_active) 3 else 1;
    const line_count = 8 + help_ids.len + section_count + intro_lines;
    const panel_width = @min(viewport_width -| 64, 860);
    const panel_height = @min(viewport_height -| 64, @max(420, 84 + line_count * 20));
    const panel_x = (viewport_width - panel_width) / 2;
    const panel_y = (viewport_height - panel_height) / 2;

    try drawPanel(buffer, allocator, panel_x, panel_y, panel_width, panel_height, true);

    var text_y: usize = panel_y + 36;
    try appendText(buffer, allocator, panel_x + 28, text_y, "title", "Sioyek Zig shortcut guide");
    text_y += 30;

    const summary_line = try std.fmt.allocPrint(
        allocator,
        "{s}  |  page {d}/{d}  |  {s}",
        .{
            truncate(model.file_name, 56),
            model.current_page + 1,
            model.page_count,
            commands.modeLabel(model.mode),
        },
    );
    defer allocator.free(summary_line);
    try appendText(buffer, allocator, panel_x + 28, text_y, "body", summary_line);
    text_y += 28;

    const status_line = try compactStatusLine(allocator, model);
    defer allocator.free(status_line);
    try appendText(buffer, allocator, panel_x + 28, text_y, "body-muted", status_line);
    text_y += 28;

    try appendText(buffer, allocator, panel_x + 28, text_y, "heading", "Start here");
    text_y += 22;

    if (model.onboarding_active) {
        try appendText(buffer, allocator, panel_x + 28, text_y, "body", "This HUD stays visible so the app keeps explaining itself while you read.");
        text_y += 20;
        try appendText(buffer, allocator, panel_x + 28, text_y, "body", "Start with Space for next page, / for search, t for contents, and b to bookmark this page.");
        text_y += 20;
        try appendText(buffer, allocator, panel_x + 28, text_y, "body", "Press ? again or Esc to collapse back to the compact guide.");
        text_y += 24;
    } else {
        try appendText(buffer, allocator, panel_x + 28, text_y, "body", "Press ? at any time to reopen this full guide.");
        text_y += 24;
    }

    try appendText(buffer, allocator, panel_x + 28, text_y, "heading", "Current mode");
    text_y += 22;

    for (commands.compactCommands(model.mode)) |command_id| {
        const line = try detailedActionLine(allocator, command_id);
        defer allocator.free(line);
        try appendText(buffer, allocator, panel_x + 28, text_y, "action", line);
        text_y += 20;
    }

    if (model.mode == .normal) {
        try appendText(buffer, allocator, panel_x + 28, text_y, "action", "1-9 then Enter  Jump to a page number");
        text_y += 24;
    } else {
        text_y += 4;
    }

    try appendText(buffer, allocator, panel_x + 28, text_y, "heading", "Reader basics");
    text_y += 22;

    try appendCategory(buffer, allocator, panel_x + 28, &text_y, help_ids, .navigation);
    try appendCategory(buffer, allocator, panel_x + 28, &text_y, help_ids, .search);
    try appendCategory(buffer, allocator, panel_x + 28, &text_y, help_ids, .bookmarks);
    try appendCategory(buffer, allocator, panel_x + 28, &text_y, help_ids, .view);
    try appendCategory(buffer, allocator, panel_x + 28, &text_y, help_ids, .app);
    try appendCategory(buffer, allocator, panel_x + 28, &text_y, help_ids, .help);
}

fn appendCategory(
    buffer: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    x: usize,
    text_y: *usize,
    help_ids: []const commands.CommandId,
    category: commands.Category,
) !void {
    var printed_any = false;
    for (help_ids) |command_id| {
        const spec = commands.find(command_id);
        if (spec.category != category) continue;

        if (!printed_any) {
            const label = switch (category) {
                .navigation => "Navigation",
                .search => "Search",
                .bookmarks => "Bookmarks",
                .view => "View",
                .help => "Help",
                .app => "App",
            };
            try appendText(buffer, allocator, x, text_y.*, "body-muted", label);
            text_y.* += 20;
            printed_any = true;
        }

        const line = try detailedActionLine(allocator, command_id);
        defer allocator.free(line);
        try appendText(buffer, allocator, x + 18, text_y.*, "action", line);
        text_y.* += 20;
    }

    if (printed_any) {
        text_y.* += 8;
    }
}

fn compactStatusLine(allocator: std.mem.Allocator, model: Model) ![]u8 {
    if (model.typed_page) |typed_page| {
        return std.fmt.allocPrint(allocator, "Go to page {d}: press Enter to jump.", .{typed_page});
    }

    switch (model.mode) {
        .search_input => {
            if (model.search_query.len == 0) {
                return allocator.dupe(u8, "Type a query, then press Enter to search.");
            }
            return std.fmt.allocPrint(allocator, "Searching for \"{s}\"", .{truncate(model.search_query, 36)});
        },
        .search_results => {
            if (model.search_selection) |selection| {
                return std.fmt.allocPrint(
                    allocator,
                    "Result {d}/{d} on page {d} with {d} hit(s).",
                    .{ selection.index + 1, selection.total, selection.page_index + 1, selection.count },
                );
            }
        },
        .toc => {
            if (model.toc_selection) |selection| {
                if (selection.page_index) |page_index| {
                    return std.fmt.allocPrint(
                        allocator,
                        "Outline {d}/{d}: {s} (page {d})",
                        .{ selection.index + 1, selection.total, truncate(selection.title, 34), page_index + 1 },
                    );
                }
                return std.fmt.allocPrint(
                    allocator,
                    "Outline {d}/{d}: {s}",
                    .{ selection.index + 1, selection.total, truncate(selection.title, 34) },
                );
            }
        },
        .normal => {},
    }

    if (model.status_message.len > 0) {
        return std.fmt.allocPrint(allocator, "{s}", .{truncate(model.status_message, 58)});
    }

    return allocator.dupe(u8, "Press ? for the full guide.");
}

fn actionLine(allocator: std.mem.Allocator, command_id: commands.CommandId) ![]u8 {
    const spec = commands.find(command_id);
    const bindings = try bindingSummary(allocator, spec.bindings, 2);
    defer allocator.free(bindings);
    return std.fmt.allocPrint(allocator, "{s}  {s}", .{ bindings, spec.label });
}

fn detailedActionLine(allocator: std.mem.Allocator, command_id: commands.CommandId) ![]u8 {
    const spec = commands.find(command_id);
    const bindings = try bindingSummary(allocator, spec.bindings, 3);
    defer allocator.free(bindings);
    return std.fmt.allocPrint(allocator, "{s}  {s}", .{ bindings, spec.description });
}

fn bindingSummary(allocator: std.mem.Allocator, bindings: []const commands.Binding, max_count: usize) ![]u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(allocator);

    const count = @min(bindings.len, max_count);
    for (bindings[0..count], 0..) |binding_entry, index| {
        if (index > 0) {
            try buffer.appendSlice(allocator, " / ");
        }
        try buffer.appendSlice(allocator, binding_entry.label);
    }

    return buffer.toOwnedSlice(allocator);
}

fn drawPanel(buffer: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, x: usize, y: usize, width: usize, height: usize, expanded: bool) !void {
    const fill_opacity = if (expanded) "0.94" else "0.88";
    const stroke_opacity = if (expanded) "0.85" else "0.60";
    try buffer.writer(allocator).print(
        "<rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\" rx=\"18\" fill=\"#0b141d\" fill-opacity=\"{s}\" stroke=\"#35526d\" stroke-opacity=\"{s}\" stroke-width=\"1\"/>",
        .{ x, y, width, height, fill_opacity, stroke_opacity },
    );
}

fn appendText(buffer: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, x: usize, y: usize, class_name: []const u8, text: []const u8) !void {
    try buffer.writer(allocator).print("<text x=\"{d}\" y=\"{d}\" class=\"{s}\">", .{ x, y, class_name });
    try appendEscaped(buffer, allocator, text);
    try buffer.appendSlice(allocator, "</text>");
}

fn appendEscaped(buffer: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, text: []const u8) !void {
    for (text) |char| {
        switch (char) {
            '&' => try buffer.appendSlice(allocator, "&amp;"),
            '<' => try buffer.appendSlice(allocator, "&lt;"),
            '>' => try buffer.appendSlice(allocator, "&gt;"),
            '"' => try buffer.appendSlice(allocator, "&quot;"),
            '\'' => try buffer.appendSlice(allocator, "&apos;"),
            else => try buffer.append(allocator, char),
        }
    }
}

fn truncate(text: []const u8, max_len: usize) []const u8 {
    if (text.len <= max_len) return text;
    if (max_len <= 3) return text[0..max_len];
    return text[0 .. max_len - 3];
}

test "compact status favors current mode state" {
    const allocator = std.testing.allocator;
    const line = try compactStatusLine(allocator, .{
        .viewport_width = 1280,
        .viewport_height = 720,
        .file_name = "paper.pdf",
        .current_page = 4,
        .page_count = 20,
        .zoom = 1.0,
        .fit_to_window = true,
        .bookmarked = false,
        .mode = .search_input,
        .status_message = "",
        .search_query = "portal",
        .show_expanded = false,
        .onboarding_active = false,
    });
    defer allocator.free(line);

    try std.testing.expect(std.mem.containsAtLeast(u8, line, 1, "portal"));
}

test "svg builder emits a root svg element" {
    const allocator = std.testing.allocator;
    const svg = try buildSvg(allocator, .{
        .viewport_width = 800,
        .viewport_height = 600,
        .file_name = "notes.pdf",
        .current_page = 0,
        .page_count = 10,
        .zoom = 1.0,
        .fit_to_window = true,
        .bookmarked = false,
        .mode = .normal,
        .status_message = "ready",
        .show_expanded = false,
        .onboarding_active = false,
    });
    defer allocator.free(svg);

    try std.testing.expect(std.mem.startsWith(u8, svg, "<svg"));
    try std.testing.expect(std.mem.containsAtLeast(u8, svg, 1, "Sioyek Zig"));
}
