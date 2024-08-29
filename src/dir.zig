const std = @import("std");

pub const MyDir = struct {
    ptr: *anyopaque,
    ifDirShouldBeIgnoredFn: *const fn (ptr: *anyopaque, dirName: []const u8) bool,
    addFn: *const fn (ptr: *anyopaque, parent_path: []const u8, name: []const u8) void,

    pub fn ifDirShouldBeIgnored(self: *const MyDir, dirName: []const u8) bool {
        return self.ifDirShouldBeIgnoredFn(dirName);
    }
    pub fn add(self: *const MyDir, parent_path: []const u8, name: []const u8) void {
        self.addFn(parent_path, name);
    }
    pub fn chDir(self: *const MyDir, subDirName: []const u8) void {
        self.chDirFn(subDirName);
    }
};

pub fn walkDir(root: []const u8, myDir: MyDir) void {
    var buffer: [1024]u8 = undefined;
    const alloc = std.heap.FixedBufferAllocator.init(&buffer).allocator();
    const dir = std.fs.openDirAbsolute(root, .{ .iterate = true }) catch |err| {
        std.log.err("Error while iterating dir: {s}", .{@errorName(err)});
        return;
    };
    myDir.chDir(root);
    doWalkDir(alloc, myDir, root, dir);
    dir.close();
}

fn doWalkDir(alloc: std.mem.Allocator, dir: MyDir, parent_path: []const u8, parentDir: std.fs.Dir) void {
    var it = parentDir.iterate();
    while (it.next()) |entry| {
        if (entry) |e| {
            switch (e.kind) {
                .directory => {
                    if (dir.ifDirShouldBeIgnored(e.name)) {
                        const dirs = [_][]const u8{ parent_path, e.name };
                        const path = std.fs.path.join(alloc, &dirs);
                        const p = parentDir.openDir(e.name, .{ .iterate = true });
                        doWalkDir(alloc, path, dir, p);
                        alloc.free(path);
                        p.close();
                    }
                },
                .file => {
                    dir.add(parent_path, e.name);
                },
                else => {},
            }
        }
    } else |err| {
        std.log.err("Error while iterating dir: {s}", .{@errorName(err)});
    }
}
