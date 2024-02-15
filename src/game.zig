const std = @import("std");
const GameMemory = struct { some_state: u32 };

var game_memory: *GameMemory = undefined;
const allocator = std.heap.page_allocator;

export fn game_init() void {
    game_memory = allocator.create(GameMemory) catch {
        std.debug.print("Failed to allocate memory\n", .{});
        return;
    };
    game_memory.some_state = 0;
}

export fn game_update() void {
    game_memory.some_state += 1;
    std.debug.print("some_state!!!: {any}\n", .{game_memory.some_state});
}

export fn game_shutdown() void {
    allocator.destroy(game_memory);
    game_memory = undefined;
}

export fn get_game_memory() *anyopaque {
    return game_memory;
}

export fn set_game_memory(ptr: *anyopaque) void {
    game_memory = @as(*GameMemory, @ptrCast(@alignCast(ptr)));
}
