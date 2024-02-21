const std = @import("std");
const SystemParams = @import("../world.zig").SystemParams;
const GraphicsPipeline = @import("../gpu/pipeline.zig").GraphicsPipeline;
const VertexBufferBinding = @import("../gpu/pipeline.zig").VertexBufferBinding;
const VertexBufferBindingAttribute = @import("../gpu/pipeline.zig").VertexBufferBindingAttribute;
const vk = @import("vulkan_zig");

var is_something = false;

pub fn startup(params: SystemParams) void {
    const name = @typeName(@This());
    std.log.debug("Starting up system: {s}", .{name});
    std.log.debug("Rendering startup!", .{});

    try GraphicsPipeline.init(params.gpu(), .{
        .debug_name = "Rendering",
        // .vertex = .{
        //     .bytecode = @eme
        // }
        .state = .{
            .depth_test = .always,
            .vertex_buffer_bindings = &[_]VertexBufferBinding{
                VertexBufferBinding{
                    .byte_stride = 0,
                    .attributes = &[_]VertexBufferBindingAttribute{
                        VertexBufferBindingAttribute{
                            .format = .r32g32b32a32_sfloat,
                            .byte_offset = 0,
                        },
                    },
                },
            },
        },
        .color_attachment_formats = &[_]vk.Format{
            .r8g8b8a8_unorm,
        },
        .depth_attachment_format = .d32_sfloat,
    });

    // is_something = true;
}

pub fn system(params: SystemParams) void {
    const gpu = params.gpu();
    _ = gpu; // autofix

    std.log.debug("Rendering system! {any}", .{is_something});

    // gpu.vkd.cmdBeginRendering(command_buffer: CommandBuffer, p_rendering_info: *const RenderingInfo)

}
