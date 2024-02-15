const std = @import("std");
const GameMemory = struct { some_state: u32 };

var game_memory: *GameMemory = undefined;
const allocator = std.heap.page_allocator;

export const yo: u32 = 4;

export fn game_init() void {
    game_memory = allocator.create(GameMemory) catch {
        std.debug.print("Failed to allocate memory\n", .{});
        return;
    };
}

export fn game_update() void {
    game_memory.some_state += 1;
    std.debug.print("some_state: {any}\n", .{game_memory.some_state});
}

export fn game_shutdown() void {
    allocator.destroy(game_memory);
    game_memory = undefined;
}
