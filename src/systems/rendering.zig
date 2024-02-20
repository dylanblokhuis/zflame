const World = @import("../world.zig").World;
const SystemParams = @import("../world.zig").SystemParams;
const std = @import("std");

pub fn startup(world: *SystemParams) void {
    _ = world; // autofix
    std.log.debug("Rendering startup!", .{});
}

pub fn system(params: *SystemParams) void {
    _ = params; // autofix
    // std.log.debug("How it jsut works!", .{});
}
