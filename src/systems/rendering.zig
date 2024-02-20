const std = @import("std");
const SystemParams = @import("../world.zig").SystemParams;

pub fn startup(params: SystemParams) void {
    _ = params; // autofix
    std.log.debug("Rendering startup!", .{});
}

pub fn system(params: SystemParams) void {
    const gpu = params.gpu();
    _ = gpu; // autofix

    // gpu.vkd.cmdBeginRendering(command_buffer: CommandBuffer, p_rendering_info: *const RenderingInfo)

}
