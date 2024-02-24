const std = @import("std");
const c = @cImport({
    @cInclude("cgltf.h");
});

pub fn parseGltf(path: [*]const u8) !void {
    var data: c.cgltf_data = undefined;
    const options = c.cgltf_options{};
    const result = c.cgltf_parse_file(&options, path, @ptrCast(&data));
    if (result != c.cgltf_result_success) {
        return error.FailedToParseGltf;
    }

    // const not_undef = data orelse return error.FailedToParseGltf;
    // _ = not_undef; // autofix

    // if (data == null) {
    //     return error.FailedToParseGltf;
    // }

    // const meshes = &data.*.*.meshes;

    // std.log.debug("{any}", .{data.*.*.meshes});

    // defer c.cgltf_free(data);
}
