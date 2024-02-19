const std = @import("std");
const Gpu = @import("./gpu.zig").Gpu;
const vk = @import("vulkan_zig");
const Allocator = std.mem.Allocator;

pub const GpuAllocation = struct {
    sub_allocation: SubAllocation,
    mapped_ptr: ?[]u8,
};

const MemoryType = struct {
    memory_blocks: std.ArrayList(?MemoryBlock),
    memory_properties: vk.MemoryPropertyFlags,
    memory_type_index: u32,
    heap_index: u32,
    is_mappable: bool,
    active_general_blocks: u32,
    buffer_device_address: bool,

    const Self = @This();

    pub fn allocate(self: *Self, gpu: *Gpu, desc: AllocationCreateDesc, buffer_image_granularity: u64, sizes: AllocationSizes) !GpuAllocation {
        _ = buffer_image_granularity; // autofix
        const memblock_size = if (self.memory_properties.host_visible_bit) blk: {
            break :blk sizes.host_memblock_size;
        } else blk: {
            break :blk sizes.device_memblock_size;
        };

        const size = desc.requirements.size;

        const dedicated_allocation = desc.scheme != .managed;
        const requires_personal_block = size > memblock_size;

        std.log.debug("GpuAllocator - MemoryType: {any} -  allocating {any} bytes - is dedicated? {any}\n", .{ self.memory_type_index, desc.requirements.size, dedicated_allocation or requires_personal_block });

        // Create a dedicated block for large memory allocations or allocations that require dedicated memory allocations.
        if (dedicated_allocation or requires_personal_block) {
            const mem_block = try MemoryBlock.init(gpu, size, self.memory_type_index, self.is_mappable, self.buffer_device_address, desc.scheme, requires_personal_block);

            var maybe_block_index: ?usize = null;
            for (self.memory_blocks.items, 0..) |item, index| {
                if (item == null) {
                    maybe_block_index = index;
                    break;
                }
            }

            const block_index = if (maybe_block_index) |block_index| blk: {
                self.memory_blocks.items[block_index] = mem_block;
                break :blk block_index;
            } else blk: {
                try self.memory_blocks.append(mem_block);
                break :blk self.memory_blocks.items.len - 1;
            };

            const actual_mem_block = &self.memory_blocks.items[block_index].?;

            const allocation = try actual_mem_block.sub_allocator.allocate(@intCast(size));
            return GpuAllocation{
                .mapped_ptr = mem_block.mapped_ptr,
                .sub_allocation = allocation,
            };
        }

        var maybe_empty_block_index: ?usize = null;

        var i = self.memory_blocks.items.len;
        while (i > 0) : (i -= 1) {
            if (self.memory_blocks.items[i - 1]) |*mem_block| {
                const allocation = mem_block.sub_allocator.allocate(@intCast(size)) catch |err| switch (err) {
                    Error.OutOfMemory => continue,
                    else => return err,
                };

                var mapped_ptr: []u8 = undefined;
                if (mem_block.mapped_ptr) |ptr| {
                    mapped_ptr = ptr[allocation.offset .. allocation.offset + size];
                }

                return GpuAllocation{
                    .sub_allocation = allocation,
                    .mapped_ptr = mapped_ptr,
                };
            } else if (maybe_empty_block_index == null) {
                maybe_empty_block_index = i;
            }
        }

        std.log.info("Creating new memory block", .{});

        const new_block_index = blk: {
            const new_memory_block = try MemoryBlock.init(gpu, memblock_size, self.memory_type_index, self.is_mappable, self.buffer_device_address, desc.scheme, false);
            const new_block_index = if (maybe_empty_block_index) |block_index| blkk: {
                self.memory_blocks.items[block_index] = new_memory_block;
                break :blkk block_index;
            } else blkk: {
                try self.memory_blocks.append(new_memory_block);
                // std.debug.print("Something! {d}", .{self.memory_blocks.items.len});
                break :blkk self.memory_blocks.items.len - 1;
            };

            break :blk new_block_index;
        };

        self.active_general_blocks += 1;

        const memory_block = &self.memory_blocks.items[new_block_index].?;

        const allocation = try memory_block.sub_allocator.allocate(@intCast(size));
        var mapped_ptr: ?[]u8 = null;
        if (memory_block.mapped_ptr) |ptr| {
            mapped_ptr = ptr[allocation.offset .. allocation.offset + size];
        }

        return GpuAllocation{
            .sub_allocation = allocation,
            .mapped_ptr = mapped_ptr,
        };
    }
};

pub const AllocationScheme = union(enum) {
    dedicated_image: vk.Image,
    dedicated_buffer: vk.Buffer,
    managed,
};

const MemoryBlock = struct {
    device_memory: vk.DeviceMemory,
    size: u64,
    mapped_ptr: ?[]u8,
    sub_allocator: GpuSubAllocator,

    const Self = @This();

    pub fn init(gpu: *Gpu, size: u64, mem_type_index: u32, mapped: bool, buffer_device_address: bool, alloc_scheme: AllocationScheme, requires_dedicated_block: bool) !Self {
        const device_memory = blk: {
            var alloc_info = vk.MemoryAllocateInfo{
                .allocation_size = size,
                .memory_type_index = mem_type_index,
            };
            const allocation_flags = vk.MemoryAllocateFlags{ .device_address_bit = true };
            var flags_info = vk.MemoryAllocateFlagsInfo{ .flags = allocation_flags, .device_mask = 0 };
            if (buffer_device_address) {
                alloc_info.p_next = &flags_info;
            }

            var dedicated_memory_info = vk.MemoryDedicatedAllocateInfo{};
            switch (alloc_scheme) {
                AllocationScheme.dedicated_image => |image| {
                    dedicated_memory_info.image = image;
                    alloc_info.p_next = &dedicated_memory_info;
                },
                AllocationScheme.dedicated_buffer => |buffer| {
                    dedicated_memory_info.buffer = buffer;
                    alloc_info.p_next = &dedicated_memory_info;
                },
                else => {},
            }

            break :blk try gpu.vkd.allocateMemory(gpu.dev, &alloc_info, null);
        };

        var mapped_ptr: ?[]u8 = null;
        if (mapped) {
            const opaq = try gpu.vkd.mapMemory(gpu.dev, device_memory, 0, vk.WHOLE_SIZE, vk.MemoryMapFlags{});
            if (opaq) |mem| {
                mapped_ptr = @as([*]u8, @ptrCast(@alignCast(mem)))[0..size];
            }
        }

        const sub_allocator = if (alloc_scheme == .dedicated_buffer or alloc_scheme == .dedicated_image or requires_dedicated_block) blk: {
            break :blk try GpuSubAllocator.initDedicatedBlockAllocator(1024 * 1024 * 256);
        } else blk: {
            break :blk try GpuSubAllocator.initOffsetAllocator(gpu.allocator, 1024 * 1024 * 256, null);
        };

        return Self{
            .device_memory = device_memory,
            .size = size,
            .mapped_ptr = mapped_ptr,
            .sub_allocator = sub_allocator,
        };
    }

    pub fn deinit(self: *Self, gpu: *Gpu) void {
        const device_memory = self.device_memory;
        if (self.mapped_ptr) {
            gpu.vkd.unmapMemory(gpu.dev, device_memory);
        }
        gpu.vkd.freeMemory(gpu.dev, device_memory, null);
        self.sub_allocator.deinit();
    }
};

const AllocationSizes = struct {
    /// The size of the memory blocks that will be created for the GPU only memory type.
    ///
    /// Defaults to 256MB.
    device_memblock_size: u64 = 256 * 1024 * 1024,
    /// The size of the memory blocks that will be created for the CPU visible memory types.
    ///
    /// Defaults to 64MB.
    host_memblock_size: u64 = 64 * 1024 * 1024,
};

pub const MemoryLocation = enum {
    unknown,
    gpu_only,
    cpu_to_gpu,
    gpu_to_cpu,
};

pub const AllocationCreateDesc = struct {
    name: []const u8,
    requirements: vk.MemoryRequirements,
    location: MemoryLocation,
    linear: bool,
    scheme: AllocationScheme,
};

pub const GpuAllocator = struct {
    memory_types: std.ArrayList(MemoryType),
    memory_heaps: []vk.MemoryHeap,
    allocation_sizes: AllocationSizes,
    buffer_image_granularity: u64,

    const Self = @This();

    pub fn init(gpu: *Gpu, allocator: Allocator) !Self {
        const memory_heaps = gpu.mem_props.memory_heaps[0..gpu.mem_props.memory_heap_count];

        var memory_types = try std.ArrayList(MemoryType).initCapacity(allocator, gpu.mem_props.memory_type_count);

        for (gpu.mem_props.memory_types[0..gpu.mem_props.memory_type_count], 0..) |memory_type, index| {
            try memory_types.append(MemoryType{
                .memory_blocks = std.ArrayList(?MemoryBlock).init(allocator),
                .memory_properties = memory_type.property_flags,
                .memory_type_index = @intCast(index),
                .heap_index = memory_type.heap_index,
                .is_mappable = memory_type.property_flags.host_visible_bit,
                .active_general_blocks = 0,
                .buffer_device_address = true,
            });
        }

        const physical_props = gpu.vki.getPhysicalDeviceProperties(gpu.physical_device);

        return Self{
            .memory_types = memory_types,
            .memory_heaps = memory_heaps,
            .allocation_sizes = AllocationSizes{},
            .buffer_image_granularity = physical_props.limits.buffer_image_granularity,
        };
    }

    pub fn allocate(self: *Self, gpu: *Gpu, desc: AllocationCreateDesc) !GpuAllocation {
        const preferred_mem_flags = switch (desc.location) {
            .gpu_only => vk.MemoryPropertyFlags{
                .device_local_bit = true,
            },
            .cpu_to_gpu => vk.MemoryPropertyFlags{
                .host_visible_bit = true,
                .host_coherent_bit = true,
                .device_local_bit = true,
            },
            .gpu_to_cpu => vk.MemoryPropertyFlags{
                .host_visible_bit = true,
                .host_coherent_bit = true,
                .host_cached_bit = true,
            },
            else => vk.MemoryPropertyFlags{},
        };

        // we try to find the preferred memory type first
        var memory_type_index_opt = self.findMemoryTypeIndex(desc.requirements, preferred_mem_flags);
        if (memory_type_index_opt == null) {
            const mem_required_flags = switch (desc.location) {
                .gpu_only => vk.MemoryPropertyFlags{
                    .device_local_bit = true,
                },
                .cpu_to_gpu => vk.MemoryPropertyFlags{
                    .host_visible_bit = true,
                    .host_coherent_bit = true,
                },
                .gpu_to_cpu => vk.MemoryPropertyFlags{
                    .host_visible_bit = true,
                    .host_coherent_bit = true,
                },
                else => vk.MemoryPropertyFlags{},
            };

            // we can't find the preferred memory type, so we try to find any memory type that fits the requirements
            memory_type_index_opt = self.findMemoryTypeIndex(desc.requirements, mem_required_flags);
        }

        if (memory_type_index_opt == null) {
            return error.NoCompatibleMemoryFound;
        }

        var memory_type = &self.memory_types.items[memory_type_index_opt.?];

        if (desc.requirements.size > self.memory_heaps[memory_type.heap_index].size) {
            if (desc.location == .cpu_to_gpu) {
                const mem_loc_preferred = vk.MemoryPropertyFlags{
                    .host_visible_bit = true,
                    .host_coherent_bit = true,
                };
                const memory_type_index = self.findMemoryTypeIndex(desc.requirements, mem_loc_preferred);
                if (memory_type_index == null) {
                    return error.NoCompatibleMemoryTypeFound;
                }

                return self.memory_types.items[memory_type_index.?].allocate(gpu, desc, self.buffer_image_granularity, self.allocation_sizes);
            }

            return error.GpuOutOfMemory;
        } else {
            return memory_type.allocate(gpu, desc, self.buffer_image_granularity, self.allocation_sizes);
        }
    }

    fn findMemoryTypeIndex(self: *Self, memory_req: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) ?usize {
        for (self.memory_types.items) |memory_type| {
            if (vk.MemoryPropertyFlags.contains(memory_type.memory_properties, flags)) {
                if ((memory_req.memory_type_bits & std.math.shl(u32, 1, memory_type.memory_type_index)) != 0) {
                    return memory_type.memory_type_index;
                }
            }
        }
        return null;
    }
};

pub const Error = error{
    OutOfMemory,
    FreeingZeroSizeAllocation,
    InvalidAllocation,
    NoCompatibleMemoryFound,
    Other,
};

pub const SubAllocation = struct {
    offset: u64,
    chunk: u64,
};

pub const GpuSubAllocator = union(enum) {
    offset_allocator: OffsetAllocator,
    dedicated_block_allocator: DedicatedBlockAllocator,

    const Self = @This();

    pub fn initOffsetAllocator(
        allocator: std.mem.Allocator,
        size: u32,
        max_allocations: ?u32,
    ) std.mem.Allocator.Error!GpuSubAllocator {
        return Self{
            .offset_allocator = try OffsetAllocator.init(
                allocator,
                size,
                max_allocations,
            ),
        };
    }

    pub fn initDedicatedBlockAllocator(
        size: u64,
    ) std.mem.Allocator.Error!GpuSubAllocator {
        return Self{
            .dedicated_block_allocator = try DedicatedBlockAllocator.init(
                size,
            ),
        };
    }

    pub fn deinit(self: *GpuSubAllocator) void {
        switch (self.*) {
            inline else => |*allocator| allocator.deinit(),
        }
    }

    pub fn reset(self: *GpuSubAllocator) std.mem.Allocator.Error!void {
        switch (self.*) {
            inline else => |allocator| allocator.reset(),
        }
    }

    pub fn allocate(
        self: *GpuSubAllocator,
        size: u32,
    ) Error!SubAllocation {
        return switch (self.*) {
            inline else => |*allocator| allocator.allocate(size),
        };
    }

    pub fn free(self: *GpuSubAllocator, allocation: SubAllocation) Error!void {
        return switch (self.*) {
            inline else => |*allocator| allocator.free(allocation),
        };
    }

    pub fn getSize(self: *const GpuSubAllocator) u64 {
        return switch (self.*) {
            inline else => |allocator| allocator.getSize(),
        };
    }

    pub fn getAllocated(self: *const GpuSubAllocator) u64 {
        return switch (self.*) {
            inline else => |allocator| allocator.getAllocated(),
        };
    }

    pub fn availableMemory(self: *const GpuSubAllocator) u64 {
        return self.getSize() - self.getAllocated();
    }

    pub fn isEmpty(self: *const GpuSubAllocator) bool {
        return self.getAllocated() == 0;
    }
};

pub const DedicatedBlockAllocator = struct {
    size: u64,
    allocated: u64,

    pub fn init(
        size: u64,
    ) std.mem.Allocator.Error!DedicatedBlockAllocator {
        return .{
            .size = size,
            .allocated = 0,
        };
    }

    pub fn deinit(self: *DedicatedBlockAllocator) void {
        _ = self;
    }

    pub fn allocate(
        self: *DedicatedBlockAllocator,
        size: u32,
    ) Error!SubAllocation {
        if (self.allocated != 0) {
            return Error.OutOfMemory;
        }

        if (self.size != size) {
            return Error.OutOfMemory;
        }

        self.allocated = size;

        return .{
            .offset = 0,
            .chunk = 1,
        };
    }

    pub fn free(self: *DedicatedBlockAllocator, allocation: SubAllocation) Error!void {
        _ = allocation;
        self.allocated = 0;
    }

    pub fn getSize(self: *const DedicatedBlockAllocator) u64 {
        return self.size;
    }

    pub fn getAllocated(self: *const DedicatedBlockAllocator) u64 {
        return self.allocated;
    }
};

// OffsetAllocator from https://github.com/sebbbi/OffsetAllocator
// rewritten in zig
pub const OffsetAllocator = struct {
    const NodeIndex = u32;

    const Node = struct {
        data_offset: u32 = 0,
        data_size: u32 = 0,
        bin_list_prev: ?NodeIndex = null,
        bin_list_next: ?NodeIndex = null,
        neighbour_prev: ?NodeIndex = null,
        neighbour_next: ?NodeIndex = null,
        used: bool = false,
    };

    const num_top_bins: u32 = 32;
    const bins_per_leaf: u32 = 8;
    const top_bins_index_shift: u32 = 3;
    const lead_bins_index_mask: u32 = 0x7;
    const num_leaf_bins: u32 = num_top_bins * bins_per_leaf;

    allocator: std.mem.Allocator,
    size: u32,
    max_allocations: u32,
    free_storage: u32 = 0,

    used_bins_top: u32 = 0,
    used_bins: [num_top_bins]u8 = undefined,
    bin_indices: [num_leaf_bins]?NodeIndex = undefined,

    nodes: ?[]Node,
    free_nodes: ?[]NodeIndex,
    free_offset: u32 = 0,

    const SmallFloat = struct {
        const mantissa_bits: u32 = 3;
        const mantissa_value: u32 = 1 << mantissa_bits;
        const mantissa_mask: u32 = mantissa_value - 1;

        pub fn toFloatRoundUp(size: u32) u32 {
            var exp: u32 = 0;
            var mantissa: u32 = 0;

            if (size < mantissa_value) {
                mantissa = size;
            } else {
                const leading_zeros = @clz(size);
                const highestSetBit = 31 - leading_zeros;

                const mantissa_start_bit = highestSetBit - mantissa_bits;
                exp = mantissa_start_bit + 1;
                mantissa = (size >> @as(u5, @truncate(mantissa_start_bit))) & mantissa_mask;

                const low_bits_mask = (@as(u32, 1) << @as(u5, @truncate(mantissa_start_bit))) - 1;
                if ((size & low_bits_mask) != 0) {
                    mantissa += 1;
                }
            }

            return (exp << mantissa_bits) + mantissa;
        }

        pub fn toFloatRoundDown(size: u32) u32 {
            var exp: u32 = 0;
            var mantissa: u32 = 0;

            if (size < mantissa_value) {
                mantissa = size;
            } else {
                const leading_zeros = @clz(size);
                const highestSetBit = 31 - leading_zeros;

                const mantissa_start_bit = highestSetBit - mantissa_bits;
                exp = mantissa_start_bit + 1;
                mantissa = (size >> @as(u5, @truncate(mantissa_start_bit))) & mantissa_mask;
            }

            return (exp << mantissa_bits) | mantissa;
        }
    };

    fn findLowestSetBitAfter(v: u32, start_idx: u32) ?u32 {
        const mask_before_start_index: u32 = (@as(u32, 1) << @as(u5, @truncate(start_idx))) - 1;
        const mask_after_start_index: u32 = ~mask_before_start_index;
        const bits_after: u32 = v & mask_after_start_index;
        if (bits_after == 0) return null;
        return @ctz(bits_after);
    }

    pub fn init(allocator: std.mem.Allocator, size: u32, max_allocations: ?u32) std.mem.Allocator.Error!OffsetAllocator {
        var self = OffsetAllocator{
            .allocator = allocator,
            .size = size,
            .max_allocations = max_allocations orelse 128 * 1024,
            .nodes = null,
            .free_nodes = null,
        };
        try self.reset();
        return self;
    }

    pub fn reset(self: *OffsetAllocator) std.mem.Allocator.Error!void {
        self.free_storage = 0;
        self.used_bins_top = 0;
        self.free_offset = self.max_allocations - 1;

        for (0..num_top_bins) |i| {
            self.used_bins[i] = 0;
        }

        for (0..num_leaf_bins) |i| {
            self.bin_indices[i] = null;
        }

        if (self.nodes) |nodes| {
            self.allocator.free(nodes);
            self.nodes = null;
        }
        if (self.free_nodes) |free_nodes| {
            self.allocator.free(free_nodes);
            self.free_nodes = null;
        }

        self.nodes = try self.allocator.alloc(Node, self.max_allocations);
        self.free_nodes = try self.allocator.alloc(NodeIndex, self.max_allocations);

        for (0..self.max_allocations) |i| {
            self.free_nodes.?[i] = self.max_allocations - @as(u32, @truncate(i)) - 1;
        }

        _ = self.insertNodeIntoBin(self.size, 0);
    }

    pub fn deinit(self: *OffsetAllocator) void {
        if (self.nodes) |nodes| {
            self.allocator.free(nodes);
            self.nodes = null;
        }
        if (self.free_nodes) |free_nodes| {
            self.allocator.free(free_nodes);
            self.free_nodes = null;
        }
    }

    pub fn allocate(
        self: *OffsetAllocator,
        size: u32,
    ) Error!SubAllocation {
        if (self.free_offset == 0) {
            return Error.OutOfMemory;
        }

        const min_bin_index = SmallFloat.toFloatRoundUp(@intCast(size));

        const min_top_bin_index: u32 = min_bin_index >> top_bins_index_shift;
        const min_leaf_bin_index: u32 = min_bin_index & lead_bins_index_mask;

        var top_bin_index = min_top_bin_index;
        var leaf_bin_index: ?u32 = null;

        if ((self.used_bins_top & (@as(u32, 1) << @as(u5, @truncate(top_bin_index)))) != 0) {
            leaf_bin_index = findLowestSetBitAfter(self.used_bins[top_bin_index], min_leaf_bin_index);
        }

        if (leaf_bin_index == null) {
            const found_top_bin_index = findLowestSetBitAfter(self.used_bins_top, min_top_bin_index + 1);
            if (found_top_bin_index == null) {
                return Error.OutOfMemory;
            }
            top_bin_index = found_top_bin_index.?;
            leaf_bin_index = @ctz(self.used_bins[top_bin_index]);
        }

        const bin_index = (top_bin_index << top_bins_index_shift) | leaf_bin_index.?;

        const node_index = self.bin_indices[bin_index].?;
        const node = &self.nodes.?[node_index];
        const node_total_size = node.data_size;
        node.data_size = @intCast(size);
        node.used = true;
        self.bin_indices[bin_index] = node.bin_list_next;
        if (node.bin_list_next) |bln| self.nodes.?[bln].bin_list_prev = null;
        self.free_storage -= node_total_size;

        // debug
        // std.debug.print("free storage: {} ({}) (allocate)\n", .{ self.free_storage, node_total_size });

        if (self.bin_indices[bin_index] == null) {
            self.used_bins[top_bin_index] &= @as(u8, @truncate(~(@as(u32, 1) << @as(u5, @truncate(leaf_bin_index.?)))));
            if (self.used_bins[top_bin_index] == 0) {
                self.used_bins_top &= ~(@as(u32, 1) << @as(u5, @truncate(top_bin_index)));
            }
        }

        const remainder_size = node_total_size - size;
        if (remainder_size > 0) {
            const new_node_index = self.insertNodeIntoBin(@intCast(remainder_size), @intCast(node.data_offset + size));
            if (node.neighbour_next) |nnn| self.nodes.?[nnn].neighbour_prev = new_node_index;
            self.nodes.?[new_node_index].neighbour_prev = node_index;
            self.nodes.?[new_node_index].neighbour_next = node.neighbour_next;
            node.neighbour_next = new_node_index;
        }

        return .{
            .offset = node.data_offset,
            .chunk = node_index,
        };
    }

    pub fn free(self: *OffsetAllocator, allocation: SubAllocation) Error!void {
        if (self.nodes == null) {
            return Error.InvalidAllocation;
        }

        const node_index = allocation.chunk;
        const node = &self.nodes.?[node_index];
        if (!node.used) {
            return Error.InvalidAllocation;
        }

        var offset = node.data_offset;
        var size = node.data_size;

        if (node.neighbour_prev != null and self.nodes.?[node.neighbour_prev.?].used == false) {
            const prev_node = &self.nodes.?[node.neighbour_prev.?];
            offset = prev_node.data_offset;
            size += prev_node.data_size;

            self.removeNodeFromBin(node.neighbour_prev.?);

            std.debug.assert(prev_node.neighbour_next == @as(u32, @truncate(node_index)));
            node.neighbour_prev = prev_node.neighbour_prev;
        }

        if (node.neighbour_next != null and self.nodes.?[node.neighbour_next.?].used == false) {
            const next_node = &self.nodes.?[node.neighbour_next.?];
            size += next_node.data_size;

            self.removeNodeFromBin(node.neighbour_next.?);

            std.debug.assert(next_node.neighbour_prev == @as(u32, @truncate(node_index)));
            node.neighbour_next = next_node.neighbour_next;
        }

        const neighbour_prev = node.neighbour_prev;
        const neighbour_next = node.neighbour_next;

        // debug
        // std.debug.print("putting node {} into freelist[{}] (free)\n", .{ node_index, self.free_offset + 1 });

        self.free_offset += 1;
        self.free_nodes.?[self.free_offset] = @intCast(node_index);

        const combined_node_index = self.insertNodeIntoBin(size, offset);
        if (neighbour_next) |nn| {
            self.nodes.?[combined_node_index].neighbour_next = neighbour_next;
            self.nodes.?[nn].neighbour_prev = combined_node_index;
        }
        if (neighbour_prev) |np| {
            self.nodes.?[combined_node_index].neighbour_prev = neighbour_prev;
            self.nodes.?[np].neighbour_next = combined_node_index;
        }
    }

    pub fn insertNodeIntoBin(self: *OffsetAllocator, size: u32, data_offset: u32) u32 {
        const bin_index = SmallFloat.toFloatRoundDown(size);

        const top_bin_index: u32 = bin_index >> top_bins_index_shift;
        const leaf_bin_index: u32 = bin_index & lead_bins_index_mask;

        if (self.bin_indices[bin_index] == null) {
            self.used_bins[top_bin_index] |= @as(u8, @truncate(@as(u32, 1) << @as(u5, @truncate(leaf_bin_index))));
            self.used_bins_top |= @as(u32, 1) << @as(u5, @truncate(top_bin_index));
        }

        const top_node_index = self.bin_indices[bin_index];
        const node_index = self.free_nodes.?[self.free_offset];
        self.free_offset -= 1;

        // debug
        // std.debug.print("getting node {} from freelist[{}]\n", .{ node_index, self.free_offset + 1 });

        self.nodes.?[node_index] = .{
            .data_offset = data_offset,
            .data_size = size,
            .bin_list_next = top_node_index,
        };
        if (top_node_index) |tni| self.nodes.?[tni].bin_list_prev = node_index;
        self.bin_indices[bin_index] = node_index;

        self.free_storage += size;

        // debug
        // std.debug.print("free storage: {} ({}) (insertNodeIntoBin)\n", .{ self.free_storage, size });

        return node_index;
    }

    pub fn removeNodeFromBin(self: *OffsetAllocator, node_index: NodeIndex) void {
        const node = &self.nodes.?[node_index];

        if (node.bin_list_prev) |blp| {
            self.nodes.?[blp].bin_list_next = node.bin_list_next;
            if (node.bin_list_next) |bln| self.nodes.?[bln].bin_list_prev = node.bin_list_prev;
        } else {
            const bin_index = SmallFloat.toFloatRoundDown(node.data_size);
            const top_bin_index: u32 = bin_index >> top_bins_index_shift;
            const leaf_bin_index: u32 = bin_index & lead_bins_index_mask;

            self.bin_indices[bin_index] = node.bin_list_next;
            if (node.bin_list_next) |bln| self.nodes.?[bln].bin_list_prev = null;

            if (self.bin_indices[bin_index] == null) {
                self.used_bins[top_bin_index] &= @as(u8, @truncate(~(@as(u32, 1) << @as(u5, @truncate(leaf_bin_index)))));

                if (self.used_bins[top_bin_index] == 0) {
                    self.used_bins_top &= ~(@as(u32, 1) << @as(u5, @truncate(top_bin_index)));
                }
            }
        }

        // debug
        // std.debug.print("putting node {} into freelist[{}] (removeNodeFromBin)\n", .{ node_index, self.free_offset + 1 });
        self.free_offset += 1;
        self.free_nodes.?[self.free_offset] = node_index;

        self.free_storage -= node.data_size;

        // debug
        // std.debug.print("free storage: {} ({}) (removeNodeFromBin)\n", .{ self.free_storage, node.data_size });
    }

    pub fn getSize(self: *const OffsetAllocator) u64 {
        return self.size;
    }

    pub fn getAllocated(self: *const OffsetAllocator) u64 {
        return self.size - self.free_storage;
    }
};

test "basic" {
    var allocator = try Allocator.initOffsetAllocator(
        std.testing.allocator,
        1024 * 1024 * 256,
        null,
    );
    defer allocator.deinit();

    const a = try allocator.allocate(1337);
    const offset = a.offset;
    try std.testing.expectEqual(@as(u64, 0), offset);
    try allocator.free(a);
}

test "allocate" {
    var allocator = try Allocator.initOffsetAllocator(
        std.testing.allocator,
        1024 * 1024 * 256,
        null,
    );
    defer allocator.deinit();

    {
        const a = try allocator.allocate(0);
        try std.testing.expectEqual(@as(u64, 0), a.offset);

        const b = try allocator.allocate(1);
        try std.testing.expectEqual(@as(u64, 0), b.offset);

        const c = try allocator.allocate(123);
        try std.testing.expectEqual(@as(u64, 1), c.offset);

        const d = try allocator.allocate(1234);
        try std.testing.expectEqual(@as(u64, 124), d.offset);

        try allocator.free(a);
        try allocator.free(b);
        try allocator.free(c);
        try allocator.free(d);

        const validate = try allocator.allocate(1024 * 1024 * 256);
        try std.testing.expectEqual(@as(u64, 0), validate.offset);
        try allocator.free(validate);
    }

    {
        const a = try allocator.allocate(1024);
        try std.testing.expectEqual(@as(u64, 0), a.offset);

        const b = try allocator.allocate(3456);
        try std.testing.expectEqual(@as(u64, 1024), b.offset);

        try allocator.free(a);

        const c = try allocator.allocate(1024);
        try std.testing.expectEqual(@as(u64, 0), c.offset);

        try allocator.free(b);
        try allocator.free(c);

        const validate = try allocator.allocate(1024 * 1024 * 256);
        try std.testing.expectEqual(@as(u64, 0), validate.offset);
        try allocator.free(validate);
    }

    {
        const a = try allocator.allocate(1024);
        try std.testing.expectEqual(@as(u64, 0), a.offset);

        const b = try allocator.allocate(3456);
        try std.testing.expectEqual(@as(u64, 1024), b.offset);

        try allocator.free(a);

        const c = try allocator.allocate(2345);
        try std.testing.expectEqual(@as(u64, 1024 + 3456), c.offset);

        const d = try allocator.allocate(456);
        try std.testing.expectEqual(@as(u64, 0), d.offset);

        const e = try allocator.allocate(512);
        try std.testing.expectEqual(@as(u64, 456), e.offset);

        try allocator.free(b);
        try allocator.free(c);
        try allocator.free(d);
        try allocator.free(e);

        const validate = try allocator.allocate(1024 * 1024 * 256);
        try std.testing.expectEqual(@as(u64, 0), validate.offset);
        try allocator.free(validate);
    }
}
