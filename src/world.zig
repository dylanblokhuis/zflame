const std = @import("std");
const math = @import("./math.zig");
const Allocator = std.mem.Allocator;

// const EntityID
const Entity = struct {
    transform: Transform,
    flags: EntityFlags,
};

pub const Transform = struct {
    position: math.Vec,
    rotation: math.Quat,
    scale: math.Vec,
};

const EntityFlags = packed struct(u2) {
    is_active: bool = true,
    renderable: bool,
};

const SystemSchedule = enum { on_start, on_update };

const SystemFunc = fn (world: *World) void;
const System = struct {
    func: *const SystemFunc,
    schedule: SystemSchedule,
};

pub const World = struct {
    entities: std.ArrayListUnmanaged(Entity),
    systems: std.ArrayListUnmanaged(System),
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        // std.debug.print("init world {any}\n", .{@sizeOf(System)});

        return Self{
            .entities = try std.ArrayListUnmanaged(Entity).initCapacity(allocator, 0),
            .systems = try std.ArrayListUnmanaged(System).initCapacity(allocator, 0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit(self.allocator);
    }

    pub fn add_system(self: *Self, schedule: SystemSchedule, func: SystemFunc) !void {
        const func_ptr: *const SystemFunc = try self.allocator.create(SystemFunc);
        func_ptr.* = func;
        try self.systems.append(self.allocator, System{ .func = func_ptr, .schedule = schedule });
    }

    pub fn run_systems(self: *Self, schedule: SystemSchedule) void {
        for (self.systems.items) |system| {
            if (system.schedule == schedule) system.func(self);
        }
    }
};
