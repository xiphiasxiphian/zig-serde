const std = @import("std");
const Allocator = std.mem.Allocator;

const root = @import("root.zig");

pub fn serialize(value: anytype, allocator: Allocator) ![] const u8
{
    const ir = root.serialize(value, allocator);

}
