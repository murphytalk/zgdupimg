const std = @import("std");
const builtin = @import("builtin");

pub const DirWalker = struct {
    ptr: *anyopaque,
    ifDirShouldBeIgnoredFn: *const fn (ptr: *anyopaque, dirName: []const u8) bool,
    addFn: *const fn (ptr: *anyopaque, parent_path: []const u8, name: []const u8) void,
    pub fn joinPath(alloc: std.mem.Allocator, parent_path: []const u8, name: []const u8) anyerror![]u8 {
        const dirs = [_][]const u8{ parent_path, name };
        return try std.fs.path.join(alloc, &dirs);
    }
    pub fn ifDirShouldBeIgnored(self: *const DirWalker, dirName: []const u8) bool {
        return self.ifDirShouldBeIgnoredFn(self.ptr, dirName);
    }
    pub fn add(self: *const DirWalker, parent_path: []const u8, name: []const u8) void {
        self.addFn(self.ptr, parent_path, name);
    }
};

const MockedDirWalker = if (builtin.is_test) struct {
    alloc: std.mem.Allocator,
    files: std.ArrayList([]const u8),
    pub fn deinit(self: MockedDirWalker) void {
        for (self.files.items) |p| {
            self.alloc.free(p);
        }
        self.files.deinit();
    }
    pub fn ifDirShouldBeIgnored(_: *anyopaque, _: []const u8) bool {
        return false;
    }
    pub fn add(ptr: *anyopaque, parent_path: []const u8, name: []const u8) void {
        var self: *MockedDirWalker = @ptrCast(@alignCast(ptr));
        const path = DirWalker.joinPath(self.alloc, parent_path, name) catch |err| {
            std.debug.print("failed to join path:{s}", .{@errorName(err)});
            return;
        };
        self.files.append(path) catch |err| {
            std.debug.print("failed to add path:{s}", .{@errorName(err)});
        };
    }
    pub fn dirWalker(self: *MockedDirWalker) DirWalker {
        return .{ .ptr = self, .ifDirShouldBeIgnoredFn = ifDirShouldBeIgnored, .addFn = add };
    }
} else {};

pub fn walkDir(root: []const u8, walker: DirWalker) void {
    var buffer: [1024]u8 = undefined;
    var vba = std.heap.FixedBufferAllocator.init(&buffer);
    const alloc = vba.allocator();
    walkDir0(alloc, root, walker);
}

fn walkDir0(alloc: std.mem.Allocator, root: []const u8, walker: DirWalker) void {
    var dir: OpenDir = .{};
    dir.openAbs(root) catch |err| {
        std.log.err("Error while iterating dir: {s}", .{@errorName(err)});
        return;
    };
    doWalkDir(alloc, walker, root, dir);
    dir.close();
}

const OpenDir = if (builtin.is_test) struct {
    pub fn openAbs(_: *OpenDir, _: []const u8) anyerror!void {}
    pub fn open(_: *OpenDir, _: std.fs.Dir, _: []const u8) void {}
    pub fn close(_: *OpenDir) void {}
    pub fn iterate(_: *const OpenDir) struct {
        idx: usize = 0,
        mockedPath: [4][]const u8 = [_][]const u8{ "file1", "", "file3", "file2" },
        pub fn next(self: *@This()) anyerror!?std.fs.Dir.Entry {
            if (self.idx < self.mockedPath.len) {
                const p = self.mockedPath[self.idx];
                self.idx += 1;
                return .{ .kind = if (p.len > 0) std.fs.Dir.Entry.Kind.file else std.fs.Dir.Entry.Kind.unknown, .name = p };
            } else return null;
        }
    } {
        return .{};
    }
} else struct {
    dir: std.fs.Dir = undefined,
    pub fn openAbs(self: *OpenDir, path: []const u8) anyerror!void {
        self.dir = try std.fs.openDirAbsolute(path, .{ .iterate = true });
    }
    pub fn open(self: *OpenDir, path: []const u8) anyerror!void {
        self.dir = try self.dir.openDir(path, .{ .iterate = true });
    }
    pub fn close(self: *OpenDir) void {
        self.dir.close();
    }
    pub fn iterate(self: *const OpenDir) std.fs.Dir.Iterator {
        return self.dir.iterate();
    }
};

fn doWalkDir(alloc: std.mem.Allocator, walker: DirWalker, parent_path: []const u8, parentDir: OpenDir) void {
    var it = parentDir.iterate();
    while (it.next()) |entry| {
        if (entry) |e| {
            switch (e.kind) {
                .directory => {
                    //std.log.debug("found dir {s}", .{e.name});
                    const doNotIgnore = if (builtin.is_test) false else !walker.ifDirShouldBeIgnored(e.name);
                    if (doNotIgnore) {
                        const dirs = [_][]const u8{ parent_path, e.name };
                        const path = std.fs.path.join(alloc, &dirs) catch |err| {
                            std.log.err("failed to join dir {s} with {s}:{s}", .{ parent_path, e.name, @errorName(err) });
                            return;
                        };
                        var dir: OpenDir = .{};
                        dir.open(path) catch |err| {
                            std.log.err("failed to open dir {s}: {s}", .{ path, @errorName(err) });
                            alloc.free(path);
                            return;
                        };
                        doWalkDir(alloc, walker, path, dir);
                        alloc.free(path);
                        dir.close();
                    }
                },
                .file => {
                    //std.log.debug("found file {s}", .{e.name});
                    walker.add(parent_path, e.name);
                },
                else => {},
            }
        } else break;
    } else |err| {
        std.log.err("Error while iterating dir: {s}", .{@errorName(err)});
    }
}

test "walkDir" {
    var w: MockedDirWalker = .{ .alloc = std.testing.allocator, .files = std.ArrayList([]const u8).init(std.testing.allocator) };
    defer w.deinit();
    const walker = w.dirWalker();
    walkDir0(std.testing.allocator, "/test", walker);
    try std.testing.expect(w.files.items.len == 3);
}
