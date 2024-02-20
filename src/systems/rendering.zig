const std = @import("std");
const SystemParams = @import("../world.zig").SystemParams;

pub fn startup(params: *SystemParams) void {
    _ = params; // autofix
    std.log.debug("Rendering startup!", .{});
}

pub fn system(params: *SystemParams) void {
    _ = params; // autofix
    // std.log.debug("How it jsut works!", .{});
}
