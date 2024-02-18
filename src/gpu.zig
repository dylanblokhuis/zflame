const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("mach-glfw");
const vk = @import("vulkan_zig");
const GpuAllocator = @import("./gpu_allocator.zig");
const Allocator = std.mem.Allocator;

const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
    .enumerateInstanceExtensionProperties = true,
    .getInstanceProcAddr = true,
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
    .createDevice = true,
    .destroySurfaceKHR = true,
    .enumeratePhysicalDevices = true,
    .getPhysicalDeviceProperties = true,
    .enumerateDeviceExtensionProperties = true,
    .getPhysicalDeviceSurfaceFormatsKHR = true,
    .getPhysicalDeviceSurfacePresentModesKHR = true,
    .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getPhysicalDeviceSurfaceSupportKHR = true,
    .getPhysicalDeviceMemoryProperties = true,
    .getDeviceProcAddr = true,
    .createDebugUtilsMessengerEXT = true,
});

const DeviceDispatch = vk.DeviceWrapper(.{
    .destroyDevice = true,
    .getDeviceQueue = true,
    .createSemaphore = true,
    .createFence = true,
    .createImageView = true,
    .destroyImageView = true,
    .destroySemaphore = true,
    .destroyFence = true,
    .getSwapchainImagesKHR = true,
    .createSwapchainKHR = true,
    .destroySwapchainKHR = true,
    .acquireNextImageKHR = true,
    .deviceWaitIdle = true,
    .waitForFences = true,
    .resetFences = true,
    .queueSubmit = true,
    .queuePresentKHR = true,
    .createCommandPool = true,
    .destroyCommandPool = true,
    .allocateCommandBuffers = true,
    .freeCommandBuffers = true,
    .queueWaitIdle = true,
    .createShaderModule = true,
    .destroyShaderModule = true,
    .createPipelineLayout = true,
    .destroyPipelineLayout = true,
    .createRenderPass = true,
    .destroyRenderPass = true,
    .createGraphicsPipelines = true,
    .destroyPipeline = true,
    .createFramebuffer = true,
    .destroyFramebuffer = true,
    .beginCommandBuffer = true,
    .endCommandBuffer = true,
    .allocateMemory = true,
    .freeMemory = true,
    .createBuffer = true,
    .destroyBuffer = true,
    .getBufferMemoryRequirements = true,
    .mapMemory = true,
    .unmapMemory = true,
    .bindBufferMemory = true,
    .cmdBeginRenderPass = true,
    .cmdEndRenderPass = true,
    .cmdBindPipeline = true,
    .cmdDraw = true,
    .cmdSetViewport = true,
    .cmdSetScissor = true,
    .cmdBindVertexBuffers = true,
    .cmdCopyBuffer = true,
});

const required_device_extensions = [_][*:0]const u8{
    vk.extension_info.khr_swapchain.name,
    vk.extension_info.khr_dynamic_rendering.name,
    vk.extension_info.ext_descriptor_indexing.name,
    vk.extension_info.ext_buffer_device_address.name,
};

const optional_device_extensions = [_][*:0]const u8{};

const optional_instance_extensions = [_][*:0]const u8{
    vk.extension_info.khr_get_physical_device_properties_2.name,
    vk.extension_info.ext_debug_utils.name,
};

pub const Gpu = struct {
    vkb: BaseDispatch,
    vki: InstanceDispatch,
    vkd: DeviceDispatch,

    instance: vk.Instance,
    surface: vk.SurfaceKHR,
    physical_device: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    dev: vk.Device,
    graphics_queue: Queue,
    present_queue: Queue,

    debug_messenger: vk.DebugUtilsMessengerEXT,
    gpu_allocator: GpuAllocator.GpuAllocator,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator, window: glfw.Window) !Self {
        const app_name = "zflame";
        var self: Self = undefined;
        self.vkb = try BaseDispatch.load(@as(vk.PfnGetInstanceProcAddr, @ptrCast(&glfw.getInstanceProcAddress)));
        const glfw_exts = glfw.getRequiredInstanceExtensions() orelse return blk: {
            const err = glfw.mustGetError();
            std.log.err("failed to get required vulkan instance extensions: error={s}", .{err.description});
            break :blk error.code;
        };

        var instance_extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, glfw_exts.len + 1);
        defer instance_extensions.deinit();
        try instance_extensions.appendSlice(glfw_exts);

        var count: u32 = undefined;
        _ = try self.vkb.enumerateInstanceExtensionProperties(null, &count, null);

        const propsv = try allocator.alloc(vk.ExtensionProperties, count);
        defer allocator.free(propsv);

        _ = try self.vkb.enumerateInstanceExtensionProperties(null, &count, propsv.ptr);

        // set instance extensions
        for (optional_instance_extensions) |extension_name| {
            for (propsv) |prop| {
                const len = std.mem.indexOfScalar(u8, &prop.extension_name, 0).?;
                const prop_ext_name = prop.extension_name[0..len];
                if (std.mem.eql(u8, prop_ext_name, std.mem.span(extension_name))) {
                    try instance_extensions.append(@ptrCast(extension_name));
                    break;
                }
            }
        }

        var layer_names = std.ArrayList([*:0]const u8).init(allocator);
        defer layer_names.deinit();

        // try layer_names.append("VK_LAYER_KHRONOS_validation");

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = app_name,
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_2,
        };

        std.log.info("Creating Vulkan instance with \n extensions: {s}\n layers: {s}", .{
            instance_extensions.items,
            layer_names.items,
        });

        self.instance = try self.vkb.createInstance(&vk.InstanceCreateInfo{
            .flags = if (builtin.os.tag == .macos) .{
                .enumerate_portability_bit_khr = true,
            } else .{},
            .p_application_info = &app_info,
            .enabled_layer_count = @intCast(layer_names.items.len),
            .pp_enabled_layer_names = @ptrCast(layer_names.items),
            .enabled_extension_count = @intCast(instance_extensions.items.len),
            .pp_enabled_extension_names = @ptrCast(instance_extensions.items),
        }, null);

        self.vki = try InstanceDispatch.load(self.instance, self.vkb.dispatch.vkGetInstanceProcAddr);

        if ((glfw.createWindowSurface(self.instance, window, null, &self.surface)) != @intFromEnum(vk.Result.success)) {
            return error.SurfaceInitFailed;
        }

        const candidate = try pickPhysicalDevice(self.vki, self.instance, allocator, self.surface);
        self.physical_device = candidate.physical_device;
        self.props = candidate.props;
        self.dev = try initializeCandidate(allocator, self.vki, candidate);
        self.vkd = try DeviceDispatch.load(self.dev, self.vki.dispatch.vkGetDeviceProcAddr);

        // hmm queues are the same on nvidia
        self.graphics_queue = Queue.init(self.vkd, self.dev, candidate.queues.graphics_family);
        self.present_queue = Queue.init(self.vkd, self.dev, candidate.queues.present_family);

        self.mem_props = self.vki.getPhysicalDeviceMemoryProperties(self.physical_device);

        std.log.info("GPU selected: {s}", .{self.props.device_name});

        try self.setup_debug_utils();
        self.allocator = allocator;

        self.gpu_allocator = try GpuAllocator.GpuAllocator.init(&self, allocator);

        {
            const buffer_info = vk.BufferCreateInfo{
                .size = 268435456,
                .usage = vk.BufferUsageFlags{ .storage_buffer_bit = true },
                .sharing_mode = .exclusive,
            };

            const buffer = try self.vkd.createBuffer(self.dev, &buffer_info, null);

            const buffer_info2 = vk.BufferCreateInfo{
                .size = 268435456,
                .usage = vk.BufferUsageFlags{ .storage_buffer_bit = true },
                .sharing_mode = .exclusive,
            };

            const buffer2 = try self.vkd.createBuffer(self.dev, &buffer_info2, null);

            const mem_reqs = self.vkd.getBufferMemoryRequirements(self.dev, buffer);
            const mem_reqs2 = self.vkd.getBufferMemoryRequirements(self.dev, buffer2);
            // const

            std.debug.print("{any}", .{mem_reqs});

            const allocation = try self.gpu_allocator.allocate(&self, GpuAllocator.AllocationCreateDesc{
                .requirements = mem_reqs,
                .location = .gpu_only,
                .linear = true,
                .scheme = .managed,
                .name = "test",
            });

            const allocation2 = try self.gpu_allocator.allocate(&self, GpuAllocator.AllocationCreateDesc{
                .requirements = mem_reqs2,
                .location = .gpu_only,
                .linear = true,
                .scheme = .managed,
                .name = "test2",
            });

            std.debug.print("{any}", .{allocation});
            std.debug.print("{any}", .{allocation2});
        }

        return self;
    }

    pub fn deinit(self: Self) void {
        self.vki.destroyDebugUtilsMessengerEXT(self.instance, self.debug_messenger, null);
        self.vkd.destroyDevice(self.dev, null);
        self.vki.destroySurfaceKHR(self.instance, self.surface, null);
        self.vki.destroyInstance(self.instance, null);
    }

    pub fn setup_debug_utils(self: *Self) !void {
        const debug_create_info = vk.DebugUtilsMessengerCreateInfoEXT{
            .message_severity = vk.DebugUtilsMessageSeverityFlagsEXT{
                .verbose_bit_ext = true,
                .info_bit_ext = true,
                .error_bit_ext = true,
                .warning_bit_ext = true,
            },
            .message_type = vk.DebugUtilsMessageTypeFlagsEXT{
                .general_bit_ext = true,
                .performance_bit_ext = true,
                .validation_bit_ext = true,
            },
            .pfn_user_callback = debug_callback,
        };
        self.debug_messenger = try self.vki.createDebugUtilsMessengerEXT(self.instance, &debug_create_info, null);
    }

    pub fn findMemoryTypeIndex(self: Self, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.mem_props.memory_types[0..self.mem_props.memory_type_count], 0..) |mem_type, i| {
            if (memory_type_bits & (@as(u32, 1) << @as(u5, @truncate(i))) != 0 and mem_type.property_flags.contains(flags)) {
                return @as(u32, @truncate(i));
            }
        }

        return error.NoSuitableMemoryType;
    }

    pub fn allocate(self: Self, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
        std.debug.print("{any}", .{requirements});
        return try self.vkd.allocateMemory(self.dev, &.{
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
        }, null);
    }
};

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(vkd: DeviceDispatch, dev: vk.Device, family: u32) Queue {
        return .{
            .handle = vkd.getDeviceQueue(dev, family, 0),
            .family = family,
        };
    }
};

fn initializeCandidate(allocator: Allocator, vki: InstanceDispatch, candidate: DeviceCandidate) !vk.Device {
    const priority = [_]f32{1};
    const qci = [_]vk.DeviceQueueCreateInfo{
        .{
            .flags = .{},
            .queue_family_index = candidate.queues.graphics_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
        .{
            .flags = .{},
            .queue_family_index = candidate.queues.present_family,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        },
    };

    const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family)
        1 // nvidia
    else
        2; // amd

    var device_extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, required_device_extensions.len);
    defer device_extensions.deinit();

    try device_extensions.appendSlice(required_device_extensions[0..required_device_extensions.len]);

    var count: u32 = undefined;
    _ = try vki.enumerateDeviceExtensionProperties(candidate.physical_device, null, &count, null);

    const propsv = try allocator.alloc(vk.ExtensionProperties, count);
    defer allocator.free(propsv);

    _ = try vki.enumerateDeviceExtensionProperties(candidate.physical_device, null, &count, propsv.ptr);

    for (optional_device_extensions) |extension_name| {
        for (propsv) |prop| {
            if (std.mem.eql(u8, prop.extension_name[0..prop.extension_name.len], std.mem.span(extension_name))) {
                try device_extensions.append(extension_name);
                break;
            }
        }
    }

    std.log.info("Creating Vulkan device with \n extensions: {s}", .{device_extensions.items});

    return try vki.createDevice(candidate.physical_device, &.{
        .flags = .{},
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = undefined,
        .enabled_extension_count = @as(u32, @intCast(device_extensions.items.len)),
        .pp_enabled_extension_names = @as([*]const [*:0]const u8, @ptrCast(device_extensions.items)),
        .p_enabled_features = null,
    }, null);
}

const DeviceCandidate = struct {
    physical_device: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

fn pickPhysicalDevice(
    vki: InstanceDispatch,
    instance: vk.Instance,
    allocator: Allocator,
    surface: vk.SurfaceKHR,
) !DeviceCandidate {
    var device_count: u32 = undefined;
    _ = try vki.enumeratePhysicalDevices(instance, &device_count, null);

    const physical_devices = try allocator.alloc(vk.PhysicalDevice, device_count);
    defer allocator.free(physical_devices);

    _ = try vki.enumeratePhysicalDevices(instance, &device_count, physical_devices.ptr);

    for (physical_devices) |physical_device| {
        if (try checkSuitable(vki, physical_device, allocator, surface)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

fn checkSuitable(
    vki: InstanceDispatch,
    physical_device: vk.PhysicalDevice,
    allocator: Allocator,
    surface: vk.SurfaceKHR,
) !?DeviceCandidate {
    const props = vki.getPhysicalDeviceProperties(physical_device);

    if (!try checkExtensionSupport(vki, physical_device, allocator)) {
        return null;
    }

    if (!try checkSurfaceSupport(vki, physical_device, surface)) {
        return null;
    }

    if (try allocateQueues(vki, physical_device, allocator, surface)) |allocation| {
        return DeviceCandidate{
            .physical_device = physical_device,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

fn allocateQueues(vki: InstanceDispatch, physical_device: vk.PhysicalDevice, allocator: Allocator, surface: vk.SurfaceKHR) !?QueueAllocation {
    var family_count: u32 = undefined;
    vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &family_count, null);

    const families = try allocator.alloc(vk.QueueFamilyProperties, family_count);
    defer allocator.free(families);
    vki.getPhysicalDeviceQueueFamilyProperties(physical_device, &family_count, families.ptr);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family = @as(u32, @intCast(i));

        if (graphics_family == null and properties.queue_flags.graphics_bit) {
            graphics_family = family;
        }

        if (present_family == null and (try vki.getPhysicalDeviceSurfaceSupportKHR(physical_device, family, surface)) == vk.TRUE) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
            .present_family = present_family.?,
        };
    }

    return null;
}

fn checkSurfaceSupport(vki: InstanceDispatch, physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var format_count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn checkExtensionSupport(
    vki: InstanceDispatch,
    physical_device: vk.PhysicalDevice,
    allocator: Allocator,
) !bool {
    var count: u32 = undefined;
    _ = try vki.enumerateDeviceExtensionProperties(physical_device, null, &count, null);

    const propsv = try allocator.alloc(vk.ExtensionProperties, count);
    defer allocator.free(propsv);

    _ = try vki.enumerateDeviceExtensionProperties(physical_device, null, &count, propsv.ptr);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            const len = std.mem.indexOfScalar(u8, &props.extension_name, 0).?;
            const prop_ext_name = props.extension_name[0..len];
            if (std.mem.eql(u8, std.mem.span(ext), prop_ext_name)) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

fn debug_callback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_types: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    _ = message_severity; // autofix
    // _ = message_severity; // autofix
    _ = message_types; // autofix
    _ = p_user_data; // autofix
    std.debug.print("validation layer: {s}\n", .{p_callback_data.?.p_message});
    // const callback_data = p_callback_data.?;
    // const message = callback_data.p_message.?;
    // std.log.info("validation layer: {s}", .{message});

    // if (message_severity == vk.DebugUtilsMessageSeverityFlagsEXT.verbose_bit_ext) {
    //     std.log.info("validation layer: {s}", .{p_callback_data.?.p_message});
    // } else if (message_severity == .info_bit_ext) {
    //     std.log.info("validation layer: {s}", .{p_callback_data.?.p_message});
    // } else if (message_severity == .warning_bit_ext) {
    //     std.log.warn("validation layer: {s}", .{p_callback_data.?.p_message});
    // } else if (message_severity == .error_bit_ext) {
    //     std.log.err("validation layer: {s}", .{p_callback_data.?.p_message});
    // }

    return vk.FALSE;
}
