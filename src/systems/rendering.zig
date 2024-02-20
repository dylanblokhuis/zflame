const World = @import("../world.zig").World;
const std = @import("std");

pub fn startup(world: *World) void {
    _ = world; // autofix
    std.log.debug("Rendering startup!", .{});
}

pub fn system(world: *World) void {
    _ = world; // autofix
    // std.log.debug("Rendering!", .{});
}
