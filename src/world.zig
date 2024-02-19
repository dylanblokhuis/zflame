const std = @import("std");
const math = @import("./math.zig");
const Allocator = std.mem.Allocator;

pub const World = struct {
    entities: std.ArrayListUnmanaged(u32),
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .entities = try std.ArrayListUnmanaged(u32).initCapacity(allocator, 0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit(self.allocator);
    }

    pub fn spawn(self: *Self, comptime component: anytype) void {
        const info = @typeInfo(component);
        // _ = info.Struct.fields;
        // std.debug.print("type: {any}\n", .{});
        inline for (info.Struct.fields) |field| {
            // _ = field; // autofix
            std.debug.print("field: {s} {s}\n", .{ @typeName(field.type), field.name });
            // field.type
            // ;
        }

        // info.
        // _ = component; // autofix
        _ = self; // autofix
        // self.entities.append(entity);
    }
};

pub const Transform = struct {
    position: math.Vec,
    rotation: math.Quat,
    scale: math.Vec,
};

pub const Health = f32;
pub const Damage = f32;

pub const Player = struct {
    transform: Transform,
    health: Health,
};

pub const Weapon = struct {
    transform: Transform,
    damage: Damage,
};
