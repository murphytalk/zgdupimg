const std = @import("std");
const builtin = @import("builtin");

pub const MyDir = struct {
    ptr: *anyopaque,
    openFn: *const fn (ptr: *anyopaque) anyerror!std.fs.Dir.Walker,
    nextFn: *const fn (ptr: *anyopaque, walker: std.fs.Dir.Walker) anyerror!?[]const u8,

    pub fn open(self: *const MyDir) anyerror!std.fs.Dir.Walker {
        return try self.openFn(self.ptr);
    }

    pub fn next(self: *const MyDir, walker: std.fs.Dir.Walker) anyerror!?[]const u8 {
        return try self.nextFn(self.ptr, walker);
    }
};

pub const RealDir = struct {
    alloc: std.mem.Allocator,
    root_dir: []const u8,
    pub fn open(ptr: *anyopaque) !std.fs.Dir.Walker {
        const self: *RealDir = @ptrCast(@alignCast(ptr));
        var dir = try std.fs.openDirAbsolute(self.root_dir, .{ .iterate = true });
        return try dir.walk(self.alloc);
    }
    pub fn next(ptr: *anyopaque, walker: std.fs.Dir.Walker) !?[]const u8 {
        const self: *RealDir = @ptrCast(@alignCast(ptr));
        var w = @constCast(&walker);
        if (try w.next()) |entry| {
            const dirs = [_][]const u8{ self.root_dir, entry.path, entry.basename };
            return try std.fs.path.join(self.alloc, &dirs);
        } else {
            w.deinit();
            return null;
        }
    }
    pub fn myDir(self: *RealDir) MyDir {
        return .{ .ptr = self, .openFn = open, .nextFn = next };
    }
};
