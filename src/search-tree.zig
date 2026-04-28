//! Search Tree
//! 4/27/2026 - Nyx

// INCLUDES -----
const std = @import("std");


pub fn SearchTree(comptime Token: type) type {
    return struct {

        keywords: *State,
        fallback_state: *SearchTree(Token).FallbackState,

        pub const State = struct {
            vtable: *const VTable,

            const ReturnStatus = union(enum) {
                Exited,
                Break,
                Changed: *State,
                Stays,
            };

            const VTable = struct {
                construct: *const fn(*anyopaque, []const u8) anyerror!?Token,
                traverse: *const fn(*anyopaque, u8) ReturnStatus,
                deinit: *const fn(*anyopaque, std.mem.Allocator) void,
            };

            pub fn construct(self: *State, buffer: []const u8) anyerror!?Token {
                return self.vtable.construct(self, buffer);
            }

            pub fn traverse(self: *State, ch: u8) ReturnStatus {
                return self.vtable.traverse(self, ch);
            }

            pub fn deinit(self: *State, gpa: std.mem.Allocator) void {
                self.vtable.deinit(self, gpa);
            }
        };

        pub const FallbackState = struct {
            const __vtable: State.VTable = .{
                .construct = FallbackState.__construct,
                .traverse = FallbackState.__traverse,
                .deinit = FallbackState.__deinit,
            };

            vtable: *const State.VTable = &__vtable,
            fallback: Fallback,

            const Fallback = *const fn([]const u8) anyerror!Token;

            fn __construct(ptr: *anyopaque, buffer: []const u8) anyerror!?Token {
                const self: *FallbackState = @ptrCast(@alignCast(ptr));
                return try self.fallback(buffer);
            }

            fn __traverse(_: *anyopaque, _: u8) State.ReturnStatus {
                return .Stays;
            }

            fn __deinit(ptr: *anyopaque, gpa: std.mem.Allocator) void {
                const self: *FallbackState = @ptrCast(@alignCast(ptr));
                gpa.destroy(self);
            }

            pub fn new(gpa: std.mem.Allocator, fallback: Fallback) !*FallbackState {
                const self = try gpa.create(FallbackState);
                self.*.vtable = &__vtable;
                self.*.fallback = fallback;

                return self;
            }

            pub fn interface(self: *FallbackState) *State {
                return @ptrCast(@alignCast(self));
            }
        };

        pub const KeywordState = struct {
            const __vtable: State.VTable = .{
                .construct = KeywordState.__construct,
                .traverse = KeywordState.__traverse,
                .deinit = KeywordState.__deinit,
            };

            vtable: *const State.VTable = &__vtable,
            token: ?Token,
            children: [256]?*KeywordState,
            force_break: bool,

            const Error = error {
                TokenAlreadyBound,
            };

            fn __construct(ptr: *anyopaque, _: []const u8) anyerror!?Token {
                const self: *KeywordState = @ptrCast(@alignCast(ptr));
                if (self.token) |token| {
                    return token;
                } else {
                    return null;
                }
            }

            fn __traverse(ptr: *anyopaque, ch: u8) State.ReturnStatus {
                const self: *KeywordState = @ptrCast(@alignCast(ptr));
                std.debug.print("to: {c}, breaks: {}\n", .{ch, self.force_break});
                if (self.children[ch]) |child| {
                    return .{ .Changed = child.interface() };
                } else if (self.force_break) {
                    return .Break;
                } else {
                    return .Exited;
                }
            }

            fn __deinit(ptr: *anyopaque, gpa: std.mem.Allocator) void {
                const self: *KeywordState = @ptrCast(@alignCast(ptr));
                for (self.children) |child| if (child) |child_ptr| {
                    child_ptr.interface().deinit(gpa);
                };

                gpa.destroy(self);
            }

            pub fn new(gpa: std.mem.Allocator, token: ?Token, breaks: bool) !*KeywordState {
                const state = try gpa.create(KeywordState);
                state.*.vtable = &__vtable;
                state.*.token = token;
                state.*.children = [_]?*KeywordState{null} ** 256;
                state.*.force_break = breaks;

                return state;
            }

            pub fn attach_child(self: *KeywordState, gpa: std.mem.Allocator, character: u8, token: ?Token, breaks: bool) !*KeywordState {
                if (self.children[character]) |child| {
                    if (child.token == null) {
                        child.*.token = token;
                    } else {
                        return Error.TokenAlreadyBound;
                    }
                    child.*.force_break = breaks;
                    return child;
                } else {
                    const child = try KeywordState.new(gpa, token, breaks);
                    self.*.children[character] = child;
                    return child;
                }
            }

            pub fn interface(self: *KeywordState) *State {
                return @ptrCast(@alignCast(self));
            }
        };

        pub const Generator = struct {

            gpa: std.mem.Allocator,

            // keywords: []const []const u8,
            // tokens: []const Token,
            keyword_tokens: []const KeywordToken,

            keyword_head: *KeywordState,
            current: *KeywordState,

            pub const KeywordToken = struct {
                symbol: []const u8,
                token: Token,
                force_break: bool = false,
            };

            const Error = error {
                MismatchingKeywordTokenArrays,
            };

            pub fn init(gpa: std.mem.Allocator, keywords: []const KeywordToken) !Generator {
                const head = try KeywordState.new(gpa, null, false);
                return .{
                    .gpa = gpa,
                    // .keywords = keywords,
                    // .tokens = tokens,
                    .keyword_tokens = keywords,
                    .keyword_head = head,
                    .current = head,
                };
            }

            pub fn generate(self: *Generator) !void {
                for (0..self.keyword_tokens.len) |i| {
                    // const kw: []const u8 = self.keywords[i];
                    // const tk: Token = self.tokens[i];
                    const kw = self.keyword_tokens[i];
                    try self.trace_branch(kw);
                }
            }

            pub fn finish(self: *Generator, fallback: FallbackState.Fallback) !SearchTree(Token) {
                return .{
                    .keywords = self.keyword_head.interface(),
                    .fallback_state = try FallbackState.new(self.gpa, fallback),
                };
            }

            fn trace_branch(self: *Generator, keyword_token: KeywordToken) !void {
                const keyword = keyword_token.symbol;
                const token = keyword_token.token;
                const breaks = keyword_token.force_break;

                for (0..keyword.len - 1) |i| {
                    const ch: u8 = keyword[i];
                    self.*.current = try self.*.current.attach_child(self.gpa, ch, null, false);
                }

                const ch: u8 = keyword[keyword.len - 1];
                _ = try self.*.current.attach_child(self.gpa, ch, token, breaks);
                self.*.current = self.keyword_head;
            }
        };


        pub fn init(gpa: std.mem.Allocator, keyword_tokens: []const Generator.KeywordToken, fallback: FallbackState.Fallback) !SearchTree(Token) {
            var gen: Generator = try .init(gpa, keyword_tokens);
            try gen.generate();
            return try gen.finish(fallback);
        }

        pub fn deinit(self: *SearchTree(Token), gpa: std.mem.Allocator) void {
            self.keywords.deinit(gpa);
        }

    };
}

