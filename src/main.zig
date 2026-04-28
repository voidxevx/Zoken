
const std = @import("std");
const zoken = @import("Zoken");

const Token = enum {
    Test,
    Tesselate,
};

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    var st: zoken.SearchTree(Token) = try .init(gpa, &.{
        "test",
        "tes",
    }, &.{
        .Test,
        .Tesselate,
    });
    defer st.deinit(gpa);

    const tk = try st.keywords.traverse('t').Changed.traverse('e').Changed.traverse('s').Changed.construct("test");
    std.debug.assert(tk == .Tesselate);
}