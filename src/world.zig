const std = @import("std");
const math = @import("./math.zig");
const gpu = @import("gpu.zig");
const glfw = @import("mach-glfw");

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

const SystemFunc = fn (params: *SystemParams) void;

const on_start_systems = [_]*const SystemFunc{
    @import("./systems/rendering.zig").startup,
};
const on_update_systems = [_]*const SystemFunc{
    @import("./systems/rendering.zig").system,
};

pub const Resources = struct { window: glfw.Window, gpu: gpu.Gpu };

/// per frame resources that are allocated and deallocated every frame
const FrameResources = struct {
    bump: std.mem.Allocator,
};

pub const SystemParams = struct {
    world: *World,
    frame: *FrameResources,
};

pub const World = struct {
    entities: std.ArrayListUnmanaged(Entity),
    allocator: Allocator,
    resources: Resources,

    const Self = @This();

    pub fn init(allocator: Allocator, window: glfw.Window) !Self {
        return Self{
            .entities = try std.ArrayListUnmanaged(Entity).initCapacity(allocator, 0),
            .allocator = allocator,
            .resources = Resources{
                .window = window,
                .gpu = try gpu.Gpu.init(allocator, window),
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit(self.allocator);
    }

    pub fn run_systems(self: *Self, schedule: SystemSchedule) void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var frame_resources = FrameResources{ .bump = arena.allocator() };
        var params = SystemParams{ .world = self, .frame = &frame_resources };

        if (schedule == SystemSchedule.on_start) {
            inline for (on_start_systems) |system| {
                system(&params);
            }
        } else if (schedule == SystemSchedule.on_update) {
            inline for (on_update_systems) |system| {
                system(&params);
            }
        }
    }
};
