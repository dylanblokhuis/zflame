const std = @import("std");
const builtin = @import("builtin");

const GameApi = struct {
    init: *const fn () void,
    update: *const fn () void,
    shutdown: *const fn () void,
    get_memory: *const fn () *anyopaque,
    set_memory: *const fn (*anyopaque) void,
    lib: *std.DynLib,

    const Self = @This();

    pub fn init(path: []const u8) !Self {
        printStr("here!");
        var library = try std.DynLib.open(path);
        printStr("here2!");
        const func: *const fn () void = undefined;
        const game_init_symbol = &library.lookup(@TypeOf(func), "game_init");
        const game_update_symbol = &library.lookup(@TypeOf(func), "game_update");
        const game_shutdown_symbol = &library.lookup(@TypeOf(func), "game_shutdown");
        const game_memory_cb: *const fn () *anyopaque = undefined;
        const game_memory_symbol = &library.lookup(@TypeOf(game_memory_cb), "get_game_memory");
        const set_memory_cb: *const fn (*anyopaque) void = undefined;
        const set_memory_symbol = &library.lookup(@TypeOf(set_memory_cb), "set_game_memory");
        printStr("here3!");
        // check if all symbols exist

        return Self{
            .init = game_init_symbol.*.?,
            .update = game_update_symbol.*.?,
            .shutdown = game_shutdown_symbol.*.?,
            .get_memory = game_memory_symbol.*.?,
            .set_memory = set_memory_symbol.*.?,
            .lib = &library,
        };
    }

    pub fn unload(self: *Self) void {
        // self.shutdown();
        self.lib.close();
        // self.init = undefined;
        // self.update = undefined;
        // self.shutdown = undefined;
        // self.get_memory = undefined;
        // self.set_memory = undefined;
    }
};

const Game = struct {
    api: GameApi,
    last_mod_time: i128,

    const Self = @This();

    pub fn init() !Self {
        return Self{
            .api = try GameApi.init(Game.get_lib_path()),
            .last_mod_time = 0,
        };
    }

    pub fn run(self: *Self) !void {
        self.api.init();
        while (true) {
            try self.check_for_new_lib();
            self.api.update();

            std.time.sleep(std.time.ns_per_s * 0.5);
        }
    }

    fn get_lib_path() []const u8 {
        const path = "./zig-out/lib/libgame";
        return switch (builtin.os.tag) {
            .linux => path ++ ".so",
            .windows => path ++ ".dll",
            .macos, .tvos, .watchos, .ios => path ++ ".dylib",
            else => return std.debug.panic("Unsupported OS.\n"),
        };
    }

    pub fn check_for_new_lib(self: *Self) !void {
        const file = try std.fs.cwd().openFile(Game.get_lib_path(), .{});
        defer file.close();
        const stat = try file.stat();

        if (self.last_mod_time == 0) {
            self.last_mod_time = stat.mtime;
        }

        if (stat.mtime > self.last_mod_time) {
            printStr("Prob should just reload the game here");
            std.time.sleep(std.time.ns_per_s * 2.0);

            const game_memory = self.api.get_memory();
            self.api.unload();

            const api = GameApi.init(Game.get_lib_path()) catch {
                printStr("Failed to reload game, this frame, will try again next frame.");
                return;
            };
            api.set_memory(game_memory);

            self.api = api;
            self.last_mod_time = stat.mtime;
        }

        // printAny(stat.mtime);
    }

    pub fn destroy(self: *Self) void {
        _ = self; // autofix
        // self.api.destroy();
    }
};

pub fn main() !void {
    var game = try Game.init();
    defer game.destroy();

    try game.run();
}

fn printAny(args: anytype) void {
    std.debug.print("{any}\n", .{args});
}

fn printStr(args: []const u8) void {
    std.debug.print("{s}\n", .{args});
}
