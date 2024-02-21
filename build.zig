const std = @import("std");
const builtin = @import("builtin");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zflame",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        // .use_llvm = false,
        // .use_lld = false,
    });

    exe.linkLibC();

    {
        const glfw_dep = b.dependency("mach-glfw", .{
            .target = target,
            .optimize = optimize,
        });

        const lib_name = blk: {
            const lib_files = std.fs.cwd().openDir("./zig-out/lib", .{
                .iterate = true,
            }) catch {
                break :blk "game-0";
            };

            var count: u32 = 0;
            var iterator = lib_files.iterate();

            while (try iterator.next()) |entry| {
                _ = entry;
                count += 1;
            }

            const lib_name = try std.fmt.allocPrint(b.allocator, "game-{d}", .{count});

            break :blk lib_name;
        };

        const lib = b.addSharedLibrary(.{
            .name = lib_name,
            .root_source_file = .{ .path = "src/game.zig" },
            .target = target,
            .optimize = optimize,
            // .use_llvm = false,
            // .use_lld = false,
        });

        lib.linkLibC();

        var maybe_xml_path: ?[]const u8 = null;
        if (std.process.hasEnvVarConstant("VULKAN_SDK")) {
            const vulkan_sdk_path = std.process.getEnvVarOwned(b.allocator, "VULKAN_SDK") catch {
                return error.@"VULKAN_SDK environment variable not set";
            };
            defer b.allocator.free(vulkan_sdk_path);

            const vulkan_lib = try std.fmt.allocPrint(b.allocator, "{s}/lib", .{vulkan_sdk_path});
            defer b.allocator.free(vulkan_lib);

            exe.addLibraryPath(.{ .path = vulkan_lib });
            lib.addLibraryPath(.{ .path = vulkan_lib });

            maybe_xml_path = try std.fmt.allocPrint(b.allocator, "{s}/share/vulkan/registry/vk.xml", .{vulkan_sdk_path});
        }

        if (maybe_xml_path) |xml_path| {
            const vkzig_dep = b.dependency("vulkan_zig", .{
                .registry = xml_path,
            });

            lib.root_module.addImport("vulkan_zig", vkzig_dep.module("vulkan-zig"));
            b.allocator.free(xml_path);
        } else {
            return error.@"VULKAN_SDK environment variable not set";
        }

        lib.root_module.addImport("mach-glfw", glfw_dep.module("mach-glfw"));

        {
            const check = b.step("check", "Check if the game compiles");
            check.dependOn(&lib.step);
        }
        b.installArtifact(lib);
    }

    compile_shaders: {
        const build_shaders = b.step("shaders", "Compile shaders");

        const shaders = std.fs.cwd().openDir("shaders", .{ .iterate = true }) catch {
            std.log.warn("No shaders dir found, not compiling..", .{});
            break :compile_shaders;
        };

        var shader_files = try std.ArrayList([]const u8).initCapacity(b.allocator, 5);
        defer shader_files.deinit();

        var iterator = shaders.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) {
                continue;
            }
            try shader_files.append(entry.name);
        }

        for (shader_files.items) |file| {
            var split_file = std.mem.splitSequence(u8, file, ".");
            const filename = split_file.next().?;
            const ext = split_file.next().?;

            const output_path = try std.fmt.allocPrint(b.allocator, "./zig-out/shaders/{s}.{s}{s}", .{ filename, ext, ".spv" });
            defer b.allocator.free(output_path);

            const input_path = try std.fmt.allocPrint(b.allocator, "./shaders/{s}", .{file});
            defer b.allocator.free(input_path);

            const shader_stage = try std.fmt.allocPrint(b.allocator, "-fshader-stage={s}", .{ext});
            defer b.allocator.free(shader_stage);

            // create folder if not exists
            try std.fs.cwd().makePath("./zig-out/shaders/");

            const argv = [_][]const u8{ "glslc", input_path, "-I", "./shaders/includes", "-std=450", "--target-env=vulkan1.2", shader_stage, "-o", output_path };
            build_shaders.evalChildProcess(&argv) catch |err| {
                std.log.err("Failed to compile shaders {any}", .{err});
            };
        }
    }

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
