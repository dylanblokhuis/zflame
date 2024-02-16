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
        var library = try std.DynLib.open(path);
        const func: *const fn () void = undefined;
        const game_init_symbol = &library.lookup(@TypeOf(func), "game_init");
        const game_update_symbol = &library.lookup(@TypeOf(func), "game_update");
        const game_shutdown_symbol = &library.lookup(@TypeOf(func), "game_shutdown");
        const game_memory_cb: *const fn () *anyopaque = undefined;
        const game_memory_symbol = &library.lookup(@TypeOf(game_memory_cb), "get_game_memory");
        const set_memory_cb: *const fn (*anyopaque) void = undefined;
        const set_memory_symbol = &library.lookup(@TypeOf(set_memory_cb), "set_game_memory");

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
        self.init = undefined;
        self.update = undefined;
        self.shutdown = undefined;
        self.get_memory = undefined;
        self.set_memory = undefined;
        self.lib.close();
        self.lib = undefined;
    }
};

const Game = struct {
    api: GameApi,
    lib_name: []const u8,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const lib_name = try Game.get_lib_path(allocator);
        return Self{
            .api = try GameApi.init(lib_name),
            .lib_name = lib_name,
            .allocator = allocator,
        };
    }

    pub fn run(self: *Self) !void {
        self.api.init();
        while (true) {
            try self.check_for_new_lib();
            self.api.update();
        }
    }

    /// scans the zig-out directory for the game library and its version
    ///
    /// example file name: ``libgame-4.so``, with 4 being the version
    fn get_lib_path(alloc: std.mem.Allocator) ![]const u8 {
        const path = "./zig-out/lib";

        const lib_files = try std.fs.cwd().openDir(path, .{
            .iterate = true,
        });

        var iterator = lib_files.iterate();

        var current_highest_version: u32 = 0;
        while (try iterator.next()) |entry| {
            var iter = std.mem.splitSequence(u8, entry.name, "-");

            // skip first part, which is the libname
            _ = iter.next();

            if (iter.next()) |lib_version| {
                // remove last 3 bytes
                const version_num = std.fmt.parseInt(u32, lib_version[0..(lib_version.len - 3)], 10) catch {
                    continue;
                };
                if (version_num > current_highest_version) {
                    current_highest_version = version_num;
                }
            }
        }
        const lib_name = "libgame";
        const extension = switch (builtin.os.tag) {
            .linux => ".so",
            .windows => ".dll",
            .macos, .tvos, .watchos, .ios => ".dylib",
            else => return std.debug.panic("Unsupported OS.\n"),
        };

        return try std.fmt.allocPrint(alloc, "{s}/{s}-{d}{s}", .{ path, lib_name, current_highest_version, extension });
    }

    pub fn check_for_new_lib(self: *Self) !void {
        const current_highest_version = try Game.get_lib_path(self.allocator);
        defer self.allocator.free(current_highest_version);

        if (std.mem.eql(u8, self.lib_name, current_highest_version)) {
            return;
        }

        std.debug.print("Reloading game with version: {s}\n", .{current_highest_version});
        std.time.sleep(std.time.ns_per_s * 0.3);

        const game_memory = self.api.get_memory();

        // this segfaults on linux, but works on macos..
        // self.api.unload();

        const api = GameApi.init(current_highest_version) catch {
            printStr("Failed to reload game, this frame, will try again next frame.");
            return;
        };
        api.set_memory(game_memory);
        self.api = api;
        self.lib_name = current_highest_version;
    }

    pub fn destroy(self: *Self) void {
        _ = self; // autofix
        // self.api.destroy();
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var game = try Game.init(allocator);
    defer game.destroy();

    try game.run();
}

fn printAny(args: anytype) void {
    std.debug.print("{any}\n", .{args});
}

fn printStr(args: []const u8) void {
    std.debug.print("{s}\n", .{args});
}
