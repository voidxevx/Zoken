
const std = @import("std");
const zoken = @import("Zoken");

const Token = enum {
    Test,
    Tesselate,
    Other,

    pub fn format(self: *const Token, writer: *std.io.Writer) std.io.Writer.Error!void {
        switch (self.*) {
            .Test => try writer.print("Test", .{}),
            .Tesselate => try writer.print("Tesselate", .{}),
            .Other => try writer.print("other", .{}),
        }
    }
};

fn identifier_fallback(_: []const u8) anyerror!Token {
    return .Other;
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;

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

    const str = "tesl";

    const ts = try zoken.TokenStream(Token).init(gpa, st, str);
    std.debug.print("{f}", .{ts});
}