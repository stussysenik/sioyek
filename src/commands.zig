const std = @import("std");

pub const InteractionMode = enum {
    normal,
    search_input,
    search_results,
    toc,
};

pub const Category = enum {
    navigation,
    search,
    bookmarks,
    view,
    help,
    app,
};

pub const CommandId = enum {
    next_page,
    previous_page,
    goto_first_page,
    goto_last_page,
    zoom_in,
    zoom_out,
    toggle_fit,
    fit_reset,
    start_search,
    search_next,
    search_prev,
    open_toc,
    toggle_bookmark,
    prev_bookmark,
    next_bookmark,
    toggle_help,
    toggle_hud_density,
    selection_up,
    selection_down,
    selection_activate,
    cancel,
    quit,
};

pub const SpecialKey = enum {
    left,
    right,
    up,
    down,
    page_up,
    page_down,
    home,
    end,
    enter,
    escape,
    space,
    backspace,
    f1,
};

pub const Key = union(enum) {
    char: u8,
    special: SpecialKey,
};

pub const KeyPress = struct {
    key: Key,
    ctrl: bool = false,
    alt: bool = false,
    meta: bool = false,
    shift: bool = false,
};

pub const Shortcut = struct {
    first: KeyPress,
    second: ?KeyPress = null,
};

pub const Binding = struct {
    label: []const u8,
    shortcut: Shortcut,
};

pub const CommandSpec = struct {
    id: CommandId,
    category: Category,
    label: []const u8,
    description: []const u8,
    mode_mask: u8,
    bindings: []const Binding,
};

const all_modes_mask = modeBits(&.{ .normal, .search_input, .search_results, .toc });
const normal_mode_mask = modeBits(&.{.normal});
const search_results_mask = modeBits(&.{.search_results});
const toc_mask = modeBits(&.{.toc});

const next_page_bindings = [_]Binding{
    binding("Space", shortcutSpecial(.space)),
    binding("Down", shortcutSpecial(.down)),
    binding("Right", shortcutSpecial(.right)),
    binding("PgDn", shortcutSpecial(.page_down)),
    binding("j", shortcutChar('j')),
};

const previous_page_bindings = [_]Binding{
    binding("Up", shortcutSpecial(.up)),
    binding("Left", shortcutSpecial(.left)),
    binding("PgUp", shortcutSpecial(.page_up)),
    binding("k", shortcutChar('k')),
};

const first_page_bindings = [_]Binding{
    binding("Home", shortcutSpecial(.home)),
};

const last_page_bindings = [_]Binding{
    binding("End", shortcutSpecial(.end)),
};

const zoom_in_bindings = [_]Binding{
    binding("+", shortcutChar('+')),
};

const zoom_out_bindings = [_]Binding{
    binding("-", shortcutChar('-')),
};

const toggle_fit_bindings = [_]Binding{
    binding("f", shortcutChar('f')),
};

const fit_reset_bindings = [_]Binding{
    binding("0", shortcutChar('0')),
};

const search_bindings = [_]Binding{
    binding("/", shortcutChar('/')),
    binding("Ctrl+F", shortcutCtrlChar('f')),
};

const search_next_bindings = [_]Binding{
    binding("n", shortcutChar('n')),
    binding("Down", shortcutSpecial(.down)),
    binding("j", shortcutChar('j')),
};

const search_prev_bindings = [_]Binding{
    binding("p", shortcutChar('p')),
    binding("Up", shortcutSpecial(.up)),
    binding("k", shortcutChar('k')),
};

const toc_bindings = [_]Binding{
    binding("t", shortcutChar('t')),
};

const bookmark_toggle_bindings = [_]Binding{
    binding("b", shortcutChar('b')),
};

const bookmark_prev_bindings = [_]Binding{
    binding("[", shortcutChar('[')),
};

const bookmark_next_bindings = [_]Binding{
    binding("]", shortcutChar(']')),
};

const toggle_help_bindings = [_]Binding{
    binding("?", shortcutChar('?')),
    binding("F1", shortcutSpecial(.f1)),
};

const hud_density_bindings = [_]Binding{
    binding("H", shortcutChar('H')),
};

const selection_up_bindings = [_]Binding{
    binding("Up", shortcutSpecial(.up)),
    binding("k", shortcutChar('k')),
};

const selection_down_bindings = [_]Binding{
    binding("Down", shortcutSpecial(.down)),
    binding("j", shortcutChar('j')),
};

const selection_activate_bindings = [_]Binding{
    binding("Enter", shortcutSpecial(.enter)),
};

const cancel_bindings = [_]Binding{
    binding("Esc", shortcutSpecial(.escape)),
};

const quit_bindings = [_]Binding{
    binding("q", shortcutChar('q')),
};

const all_commands = [_]CommandSpec{
    .{
        .id = .next_page,
        .category = .navigation,
        .label = "Next page",
        .description = "Move forward through the document.",
        .mode_mask = normal_mode_mask,
        .bindings = &next_page_bindings,
    },
    .{
        .id = .previous_page,
        .category = .navigation,
        .label = "Previous page",
        .description = "Move backward through the document.",
        .mode_mask = normal_mode_mask,
        .bindings = &previous_page_bindings,
    },
    .{
        .id = .goto_first_page,
        .category = .navigation,
        .label = "First page",
        .description = "Jump to the beginning of the document.",
        .mode_mask = normal_mode_mask,
        .bindings = &first_page_bindings,
    },
    .{
        .id = .goto_last_page,
        .category = .navigation,
        .label = "Last page",
        .description = "Jump to the end of the document.",
        .mode_mask = normal_mode_mask,
        .bindings = &last_page_bindings,
    },
    .{
        .id = .zoom_in,
        .category = .view,
        .label = "Zoom in",
        .description = "Increase the page scale.",
        .mode_mask = normal_mode_mask,
        .bindings = &zoom_in_bindings,
    },
    .{
        .id = .zoom_out,
        .category = .view,
        .label = "Zoom out",
        .description = "Decrease the page scale.",
        .mode_mask = normal_mode_mask,
        .bindings = &zoom_out_bindings,
    },
    .{
        .id = .toggle_fit,
        .category = .view,
        .label = "Toggle fit",
        .description = "Switch between fit-to-window and manual zoom.",
        .mode_mask = normal_mode_mask,
        .bindings = &toggle_fit_bindings,
    },
    .{
        .id = .fit_reset,
        .category = .view,
        .label = "Reset fit",
        .description = "Snap back to fit-to-window.",
        .mode_mask = normal_mode_mask,
        .bindings = &fit_reset_bindings,
    },
    .{
        .id = .start_search,
        .category = .search,
        .label = "Search",
        .description = "Open search and type a query.",
        .mode_mask = normal_mode_mask | search_results_mask,
        .bindings = &search_bindings,
    },
    .{
        .id = .search_next,
        .category = .search,
        .label = "Next result",
        .description = "Move to the next search hit.",
        .mode_mask = search_results_mask,
        .bindings = &search_next_bindings,
    },
    .{
        .id = .search_prev,
        .category = .search,
        .label = "Previous result",
        .description = "Move to the previous search hit.",
        .mode_mask = search_results_mask,
        .bindings = &search_prev_bindings,
    },
    .{
        .id = .open_toc,
        .category = .navigation,
        .label = "Table of contents",
        .description = "Open the document outline.",
        .mode_mask = normal_mode_mask,
        .bindings = &toc_bindings,
    },
    .{
        .id = .toggle_bookmark,
        .category = .bookmarks,
        .label = "Toggle bookmark",
        .description = "Add or remove a bookmark on the current page.",
        .mode_mask = normal_mode_mask,
        .bindings = &bookmark_toggle_bindings,
    },
    .{
        .id = .prev_bookmark,
        .category = .bookmarks,
        .label = "Previous bookmark",
        .description = "Jump to the previous bookmark.",
        .mode_mask = normal_mode_mask,
        .bindings = &bookmark_prev_bindings,
    },
    .{
        .id = .next_bookmark,
        .category = .bookmarks,
        .label = "Next bookmark",
        .description = "Jump to the next bookmark.",
        .mode_mask = normal_mode_mask,
        .bindings = &bookmark_next_bindings,
    },
    .{
        .id = .toggle_help,
        .category = .help,
        .label = "Help",
        .description = "Toggle the full shortcut guide.",
        .mode_mask = all_modes_mask,
        .bindings = &toggle_help_bindings,
    },
    .{
        .id = .toggle_hud_density,
        .category = .help,
        .label = "HUD density",
        .description = "Switch between compact and expanded HUD layouts.",
        .mode_mask = all_modes_mask,
        .bindings = &hud_density_bindings,
    },
    .{
        .id = .selection_up,
        .category = .navigation,
        .label = "Move up",
        .description = "Move the active selection upward.",
        .mode_mask = toc_mask,
        .bindings = &selection_up_bindings,
    },
    .{
        .id = .selection_down,
        .category = .navigation,
        .label = "Move down",
        .description = "Move the active selection downward.",
        .mode_mask = toc_mask,
        .bindings = &selection_down_bindings,
    },
    .{
        .id = .selection_activate,
        .category = .navigation,
        .label = "Open selection",
        .description = "Open the highlighted item.",
        .mode_mask = search_results_mask | toc_mask,
        .bindings = &selection_activate_bindings,
    },
    .{
        .id = .cancel,
        .category = .help,
        .label = "Cancel",
        .description = "Leave the current mode or close expanded help.",
        .mode_mask = all_modes_mask,
        .bindings = &cancel_bindings,
    },
    .{
        .id = .quit,
        .category = .app,
        .label = "Quit",
        .description = "Close the viewer.",
        .mode_mask = normal_mode_mask,
        .bindings = &quit_bindings,
    },
};

const compact_normal = [_]CommandId{
    .next_page,
    .previous_page,
    .start_search,
    .open_toc,
    .toggle_bookmark,
    .next_bookmark,
    .toggle_help,
};

const compact_search_input = [_]CommandId{
    .cancel,
    .toggle_help,
};

const compact_search_results = [_]CommandId{
    .search_next,
    .search_prev,
    .selection_activate,
    .start_search,
    .cancel,
    .toggle_help,
};

const compact_toc = [_]CommandId{
    .selection_down,
    .selection_up,
    .selection_activate,
    .cancel,
    .toggle_help,
};

const help_normal = [_]CommandId{
    .next_page,
    .previous_page,
    .goto_first_page,
    .goto_last_page,
    .start_search,
    .open_toc,
    .toggle_bookmark,
    .prev_bookmark,
    .next_bookmark,
    .zoom_in,
    .zoom_out,
    .toggle_fit,
    .fit_reset,
    .toggle_help,
    .toggle_hud_density,
    .quit,
};

const help_search_input = [_]CommandId{
    .cancel,
    .toggle_help,
    .toggle_hud_density,
};

const help_search_results = [_]CommandId{
    .search_next,
    .search_prev,
    .selection_activate,
    .start_search,
    .cancel,
    .toggle_help,
    .toggle_hud_density,
};

const help_toc = [_]CommandId{
    .selection_down,
    .selection_up,
    .selection_activate,
    .cancel,
    .toggle_help,
    .toggle_hud_density,
};

pub fn commandForKey(mode: InteractionMode, key_press: KeyPress) ?CommandId {
    for (&all_commands) |*command| {
        if (!isModeAvailable(command.mode_mask, mode)) continue;
        for (command.bindings) |binding_entry| {
            if (matches(binding_entry.shortcut, key_press)) {
                return command.id;
            }
        }
    }
    return null;
}

pub fn find(id: CommandId) *const CommandSpec {
    for (&all_commands) |*command| {
        if (command.id == id) return command;
    }
    unreachable;
}

pub fn compactCommands(mode: InteractionMode) []const CommandId {
    return switch (mode) {
        .normal => &compact_normal,
        .search_input => &compact_search_input,
        .search_results => &compact_search_results,
        .toc => &compact_toc,
    };
}

pub fn helpCommands(mode: InteractionMode) []const CommandId {
    return switch (mode) {
        .normal => &help_normal,
        .search_input => &help_search_input,
        .search_results => &help_search_results,
        .toc => &help_toc,
    };
}

pub fn modeLabel(mode: InteractionMode) []const u8 {
    return switch (mode) {
        .normal => "Normal",
        .search_input => "Search input",
        .search_results => "Search results",
        .toc => "Table of contents",
    };
}

fn matches(shortcut: Shortcut, key_press: KeyPress) bool {
    if (shortcut.second != null) {
        return false;
    }
    return keyPressEql(shortcut.first, key_press);
}

fn keyPressEql(a: KeyPress, b: KeyPress) bool {
    if (a.ctrl != b.ctrl or a.alt != b.alt or a.meta != b.meta or a.shift != b.shift) {
        return false;
    }

    return switch (a.key) {
        .char => |lhs| switch (b.key) {
            .char => |rhs| lhs == rhs,
            .special => false,
        },
        .special => |lhs| switch (b.key) {
            .char => false,
            .special => |rhs| lhs == rhs,
        },
    };
}

fn isModeAvailable(mask: u8, mode: InteractionMode) bool {
    return (mask & modeBit(mode)) != 0;
}

fn modeBits(comptime modes: []const InteractionMode) u8 {
    var mask: u8 = 0;
    inline for (modes) |mode| {
        mask |= modeBit(mode);
    }
    return mask;
}

fn modeBit(mode: InteractionMode) u8 {
    return switch (mode) {
        .normal => 1 << 0,
        .search_input => 1 << 1,
        .search_results => 1 << 2,
        .toc => 1 << 3,
    };
}

fn binding(label: []const u8, shortcut_value: Shortcut) Binding {
    return .{
        .label = label,
        .shortcut = shortcut_value,
    };
}

fn shortcutChar(value: u8) Shortcut {
    return .{
        .first = .{
            .key = .{ .char = value },
        },
    };
}

fn shortcutCtrlChar(value: u8) Shortcut {
    return .{
        .first = .{
            .key = .{ .char = value },
            .ctrl = true,
        },
    };
}

fn shortcutSpecial(value: SpecialKey) Shortcut {
    return .{
        .first = .{
            .key = .{ .special = value },
        },
    };
}

test "command lookup matches beginner and compatible bindings" {
    try std.testing.expectEqual(
        CommandId.next_page,
        commandForKey(.normal, .{ .key = .{ .special = .space } }).?,
    );
    try std.testing.expectEqual(
        CommandId.start_search,
        commandForKey(.normal, .{ .key = .{ .char = '/' } }).?,
    );
    try std.testing.expectEqual(
        CommandId.toggle_help,
        commandForKey(.normal, .{ .key = .{ .char = '?' } }).?,
    );
}

test "mode-specific commands stay scoped" {
    try std.testing.expect(commandForKey(.normal, .{ .key = .{ .special = .enter } }) == null);
    try std.testing.expectEqual(
        CommandId.selection_activate,
        commandForKey(.toc, .{ .key = .{ .special = .enter } }).?,
    );
}
