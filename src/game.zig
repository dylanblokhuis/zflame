const std = @import("std");
const glfw = @import("mach-glfw");
const vk = @import("vulkan_zig");

const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
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

const Game = struct {
    window: glfw.Window,
    update_status: GameUpdateStatus,

    const Self = @This();

    pub fn init(game: *Self, window: glfw.Window) void {
        game.window = window;
        game.update_status = .nothing;
        game.init_window_callbacks();

        // const vkb = try BaseDispatch.load(null);
        // const instance = try vkb.createInstance(null, null);
        // const vki = try InstanceDispatch.load(instance, null);
        // const vkd = try DeviceDispatch.load(instance, null, null);
        // vkd.createGraphi
        // instance.
    }

    pub fn init_window_callbacks(self: *Self) void {
        const key_callback = struct {
            fn callback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
                const game = window.getUserPointer(Self) orelse unreachable;
                _ = scancode;

                if (key == .r and mods.control and action == .press) {
                    std.log.info("Hot reload requested", .{});
                    game.update_status = .needs_hot_reload;
                }
            }
        }.callback;

        const window = self.window;
        window.setUserPointer(self);
        window.setKeyCallback(key_callback);
    }
};

var game_memory: *Game = undefined;
const allocator = std.heap.c_allocator;

// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}", .{ error_code, description });
}

export fn game_init() void {
    game_memory = allocator.create(Game) catch {
        std.log.err("Failed to allocate initial game memory\n", .{});
        std.process.exit(1);
    };

    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }

    // Create our window
    const window = glfw.Window.create(1280, 720, "zflame", null, null, .{}) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };

    game_memory.init(window);
}

pub const GameUpdateStatus = enum(c_int) {
    nothing,
    close,
    needs_hot_reload,
};

export fn game_update() GameUpdateStatus {
    if (game_memory.window.shouldClose()) {
        return .close;
    }
    glfw.pollEvents();

    defer game_memory.update_status = .nothing;
    return game_memory.update_status;
}

export fn game_shutdown() void {
    game_memory.window.destroy();
    glfw.terminate();

    allocator.destroy(game_memory);
    game_memory = undefined;
}

export fn get_game_memory() *anyopaque {
    return game_memory;
}

export fn set_game_memory(ptr: *anyopaque) void {
    game_memory = @as(*Game, @ptrCast(@alignCast(ptr)));
}
