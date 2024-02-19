const std = @import("std");
const glfw = @import("mach-glfw");
const gpu = @import("./gpu.zig");
const World = @import("./world.zig").World;
const Allocator = std.mem.Allocator;

const Game = struct {
    window: glfw.Window,
    update_status: GameUpdateStatus,
    gpu: gpu.Gpu,
    world: World,

    const Self = @This();

    pub fn init(game: *Self, allocator: Allocator, window: glfw.Window) void {
        game.window = window;
        game.update_status = .nothing;
        game.init_window_callbacks();
        game.gpu = gpu.Gpu.init(allocator, window) catch {
            std.log.err("Failed to initialize GPU\n", .{});
            std.process.exit(1);
        };
        game.world = World.init(allocator) catch {
            std.log.err("Failed to initialize world\n", .{});
            std.process.exit(1);
        };
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

    pub fn update(self: *Self) void {
        _ = self; // autofix

    }
};

var game_memory: *Game = undefined;
// const allocator = std.heap.c_allocator;

// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}", .{ error_code, description });
}

export fn game_init() void {
    std.debug.print("\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
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
    const window = glfw.Window.create(1280, 720, "zflame", null, null, .{ .client_api = .no_api }) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };

    game_memory.init(allocator, window);
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

    game_memory.update();

    defer game_memory.update_status = .nothing;
    return game_memory.update_status;
}

export fn game_shutdown() void {
    game_memory.window.destroy();
    glfw.terminate();

    // allocator.destroy(game_memory);
    // game_memory = undefined;
}

export fn get_game_memory() *anyopaque {
    return game_memory;
}

export fn set_game_memory(ptr: *anyopaque) void {
    game_memory = @as(*Game, @ptrCast(@alignCast(ptr)));
}
