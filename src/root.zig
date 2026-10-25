const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const model = @import("model.zig");
const Token = model.Token;

pub fn serialize(value: anytype, allocator: Allocator) !std.ArrayList(Token) {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);

    try model.serializeValue(value, allocator, &tokens);

    return tokens;
}
