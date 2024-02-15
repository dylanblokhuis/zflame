const std = @import("std");
const game = @import("./game.zig");

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    var library = try std.DynLib.open("./zig-out/lib/libgame.dylib");
    const func: *const u32 = undefined;
    const symbol = &library.lookup(@TypeOf(func), "yo");

    if (symbol.*) |ptr| {
        std.debug.print("symbol value: {any}\n", .{ptr.*});
    }
}
