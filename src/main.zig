
const std = @import("std");
const zoken = @import("Zoken");

const Token = union(enum) {
    Test,
    Tesselate,
    Other: []const u8,

    pub fn format(self: *const Token, writer: *std.io.Writer) std.io.Writer.Error!void {
        switch (self.*) {
            .Test => try writer.print("Test", .{}),
            .Tesselate => try writer.print("Tesselate", .{}),
            .Other => |c| try writer.print("{s}", .{c}),
        }
    }
};

const allocator = std.heap.page_allocator;
fn identifier_fallback(buf: []const u8) anyerror!Token {
    const ident = try allocator.alloc(u8, buf.len);
    @memcpy(ident, buf);
    return .{ .Other = ident };
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    std.debug.print("Generating:\n", .{});
    var st: zoken.SearchTree(Token) = try .init(
        gpa,
        &.{
            .{
                .symbol = "test",
                .token = .Test,
            },
            .{
                .symbol = "tes",
                .token = .Tesselate,
                .force_break = true,
            }
        }, 
        identifier_fallback,
        null,
        &.{},
    );
    defer st.deinit(gpa);

    std.debug.print("\nTokenizing:\n", .{});
    const str = "tesl";

    const ts = try zoken.TokenStream(Token).init(gpa, st, str);
    std.debug.print("{f}", .{ts});
}