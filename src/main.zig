const std = @import("std");
const game = @import("./game.zig");

const Game = struct {
    init: fn () void,
    // update: fn () void,
    // render: fn () void,
};

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    var library = try std.DynLib.open("./zig-out/lib/libgame.dylib");
    defer library.close();

    const func: *const fn () void = undefined;
    const game_init_symbol = &library.lookup(@TypeOf(func), "game_init");
    const game_update_symbol = &library.lookup(@TypeOf(func), "game_update");
    const game_shutdown_symbol = &library.lookup(@TypeOf(func), "game_shutdown");

    if (game_init_symbol.*) |ptr| {
        ptr();
    }

    if (game_update_symbol.*) |ptr| {
        ptr();
    }

    if (game_shutdown_symbol.*) |ptr| {
        ptr();
    }
}
