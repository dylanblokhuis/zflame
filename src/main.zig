const std = @import("std");
const builtin = @import("builtin");

const GameApi = struct {
    init: *const fn () void,
    update: *const fn () c_int,
    shutdown: *const fn () void,
    get_memory: *const fn () *anyopaque,
    set_memory: *const fn (*anyopaque) void,
    lib: *std.DynLib,

    const Self = @This();

    pub fn init(path: []const u8) !Self {
        std.debug.print("Loading game lib: {s}\n", .{path});
        var library = try std.DynLib.open(path);
        const game_init_symbol = &library.lookup(*const fn () void, "game_init");

        const game_update_symbol = &library.lookup(*const fn () c_int, "game_update");
        const game_shutdown_symbol = &library.lookup(*const fn () void, "game_shutdown");
        const game_memory_symbol = &library.lookup(*const fn () *anyopaque, "get_game_memory");
        const set_memory_symbol = &library.lookup(*const fn (*anyopaque) void, "set_game_memory");

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
            const status = self.api.update();
            if (status == 1) {
                self.api.shutdown();
                break;
            }
            if (status == 2) {
                std.log.debug("Status: {d}", .{status});
                self.check_for_new_lib() catch {
                    std.log.info("Failed to check for new game lib", .{});
                };
            }
        }

        // while (!self.window.shouldClose()) {
        //     const key_callback = struct {
        //         fn callback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
        //             const game = window.getUserPointer(Game) orelse unreachable;
        //             _ = scancode;

        //             if (key == .r and mods.control and action == .press) {
        //                 game.check_for_new_lib() catch {
        //                     printStr("Failed to check for new game lib");
        //                 };
        //             }
        //         }
        //     }.callback;

        //     self.window.setKeyCallback(key_callback);

        //     self.api.update();
        // }
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
                // remove extension
                const bytes_to_remove = if (builtin.os.tag == .macos) 6 else if (builtin.os.tag == .windows) 4 else 3;
                const version_num = std.fmt.parseInt(u32, lib_version[0..(lib_version.len - bytes_to_remove)], 10) catch {
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
            std.log.debug("No need to reload game, version is the same: {s}", .{current_highest_version});
            return;
        }

        std.debug.print("Reloading game with version: {s}\n", .{current_highest_version});
        std.time.sleep(std.time.ns_per_s * 0.3);

        const game_memory = self.api.get_memory();

        // this segfaults on linux, but works on macos..
        // self.api.unload();

        const api = GameApi.init(current_highest_version) catch {
            std.log.warn("Failed to reload game, this frame, will try again next frame.", .{});
            return;
        };
        api.set_memory(game_memory);
        self.api = api;
        self.lib_name = current_highest_version;
    }

    pub fn destroy(self: *Self) void {
        self.allocator.free(self.lib_name);
    }
};

pub fn main() !void {
    var game = try Game.init(std.heap.c_allocator);
    defer game.destroy();

    try game.run();
}
