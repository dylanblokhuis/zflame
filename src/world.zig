const std = @import("std");
const math = @import("./math.zig");
const Gpu = @import("gpu.zig").Gpu;
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

const SystemFunc = fn (params: SystemParams) void;

const on_start_systems = [_]*const SystemFunc{
    @import("./systems/rendering.zig").startup,
};
const on_update_systems = [_]*const SystemFunc{
    @import("./systems/rendering.zig").system,
};

pub const Resources = struct { window: glfw.Window, gpu: Gpu };

pub const SystemParams = struct {
    world: *World,
    /// A bump allocator for temporary allocations. All allocations are freed at the end of the frame.
    bump: *Allocator,

    const Self = @This();

    pub inline fn resources(self: Self) *Resources {
        return &self.world.resources;
    }

    pub inline fn gpu(self: Self) *Gpu {
        return &self.world.resources.gpu;
    }
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
                .gpu = try Gpu.init(allocator, window),
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit(self.allocator);
    }

    pub fn run_systems(self: *Self, schedule: SystemSchedule) void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var allocator = arena.allocator();
        const params = SystemParams{ .world = self, .bump = &allocator };

        if (schedule == SystemSchedule.on_start) {
            inline for (on_start_systems) |system| {
                system(params);
            }
        } else if (schedule == SystemSchedule.on_update) {
            inline for (on_update_systems) |system| {
                system(params);
            }
        }
    }
};
