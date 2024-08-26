const std = @import("std");

pub const MyDir = struct {
    ptr: *anyopaque,
    openFn: *const fn (ptr: *anyopaque) anyerror!void,
    nextFn: *const fn (ptr: *anyopaque) anyerror!?[]const u8,

    pub fn open(self: *const MyDir) anyerror!void {
        return try self.openFn(self.ptr);
    }

    pub fn next(self: *const MyDir) anyerror!?[]const u8 {
        return try self.nextFn(self.ptr);
    }
};

pub const RealDir = struct {
    alloc: std.mem.Allocator,
    walker: ?std.fs.Dir.Walker = null,
    root_dir: []const u8,
    pub fn open(ptr: *anyopaque) !void {
        const self: *RealDir = @ptrCast(@alignCast(ptr));
        var dir = try std.fs.openDirAbsolute(self.root_dir, .{ .iterate = true });
        self.walker = try dir.walk(self.alloc);
    }
    pub fn next(ptr: *anyopaque) !?[]const u8 {
        const self: *RealDir = @ptrCast(@alignCast(ptr));
        if (self.walker) |wk| {
            var w = @constCast(&wk);
            if (try w.next()) |entry| {
                const dirs = [_][]const u8{ self.root_dir, entry.path, entry.basename };
                return try std.fs.path.join(self.alloc, &dirs);
            } else {
                w.deinit();
                return null;
            }
        } else return null;
    }
    pub fn myDir(self: *RealDir) MyDir {
        return .{ .ptr = self, .openFn = open, .nextFn = next };
    }
};
