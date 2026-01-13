pub const c = @cImport({
    @cInclude("wren.h");
});

pub const Version = struct {
    major: u8,
    minor: u8,
    patch: u8,
};

pub fn getVersion() Version {
    var major: c_int = 0;
    var minor: c_int = 0;
    var patch: c_int = 0;
    c.wrenGetVersionNumber(&major, &minor, &patch);
    return .{
        .major = @intCast(major),
        .minor = @intCast(minor),
        .patch = @intCast(patch),
    };
}
