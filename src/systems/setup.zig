const World = @import("../world.zig").World;
const std = @import("std");

pub fn setup(world: *World) void {
    _ = world; // autofix
    std.debug.print("Setup!", .{});
}
