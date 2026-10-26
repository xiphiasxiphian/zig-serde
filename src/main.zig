const std = @import("std");
const Io = std.Io;

const zig_serde = @import("zig_serde");
const Token = zig_serde.model.Token;

const TestType = struct {
    boolean: bool,
    number: i32,
    data: struct { x: u32, y: u32 },
    numbers: [5]u8,
};

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const value = TestType{ .boolean = false, .number = 42, .data = .{ .x = 5, .y = 6 }, .numbers = [_]u8{ 1, 2, 3, 4, 5 } };
    const tokens = try zig_serde.tokenize(value, allocator);

    for (tokens.items) |token| {
        std.debug.print("{f}\n", .{token});
    }

    const result = try zig_serde.json.serialize(value, allocator);
    defer allocator.free(result);

    std.debug.print("\n{s}\n", .{result});
}
