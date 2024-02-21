const Gpu = @import("../gpu.zig").Gpu;
const vk = @import("vulkan_zig");

pub const VertexBufferBinding = struct {
    byte_stride: u32,
    attributes: []const VertexBufferBindingAttribute,
};

pub const VertexBufferBindingAttribute = struct {
    format: vk.Format,
    byte_offset: u32,
};

pub const GraphicsPipelineDescriptor = struct {
    debug_name: []const u8 = "GraphicsPipelineDescriptor",
    // vertex: struct {
    //     bytecode: []const u8,
    //     entry_point: []const u8,
    // },
    // fragment: struct {
    //     bytecode: []const u8,
    //     entry_point: []const u8,
    // },
    state: struct {
        depth_test: vk.CompareOp,
        vertex_buffer_bindings: []const VertexBufferBinding,
    },

    color_attachment_formats: []const vk.Format,
    depth_attachment_format: vk.Format,

    // bind_groups
};

pub const GraphicsPipeline = struct {
    pipeline: vk.Pipeline,
    layout: vk.PipelineLayout,
    // descriptor_sets

    const Self = @This();

    pub fn init(gpu: *Gpu, desc: GraphicsPipelineDescriptor) !void {
        _ = gpu; // autofix
        _ = desc; // autofix
        // _ = self; // autofix

        // desc.vertex.henk

        // gpu.vkd.createPipelineLayout(gpu.dev, &vk.PipelineLayoutCreateInfo{
        //     .set_layout_count = 0,
        //     .p_set_layouts = null,
        //     .push_constant_range_count = 0,
        //     .p_push_constant_ranges = null,
        // }, null);
    }
};
