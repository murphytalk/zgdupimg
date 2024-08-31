const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const testing = std.testing;
const myDir = @import("dir.zig");

pub fn doWork(allocator: std.mem.Allocator, ignored_dir: []const u8, img_dir: []const u8, bin_dir: []const u8) !void {
    _ = bin_dir;
    var imageFiles = ArrayList(ImgFile).init(allocator);
    try walkImgDir(allocator, img_dir, ignored_dir, &imageFiles);
    defer imageFiles.deinit();

    for (imageFiles.items) |f| {
        std.log.info("File path: {s}", .{f.fullPath});
    }
    std.log.info("Total {d}", .{imageFiles.items.len});
}

const ImgFile = struct {
    fullPath: []const u8,
    pub fn init(path: []const u8) ImgFile {
        return ImgFile{ .fullPath = path };
    }
};

const DirWalkerImpl = struct {
    alloc: std.mem.Allocator,
    ignoredDir: []const u8,
    files: *ArrayList(ImgFile),

    pub fn ifDirShouldBeIgnored(ptr: *anyopaque, dirName: []const u8) bool {
        const self: *DirWalkerImpl = @ptrCast(@alignCast(ptr));
        return std.mem.eql(u8, self.ignoredDir, dirName);
    }
    pub fn add(ptr: *anyopaque, parent_path: []const u8, name: []const u8) void {
        const self: *DirWalkerImpl = @ptrCast(@alignCast(ptr));
        const path = myDir.DirWalker.joinPath(self.alloc, parent_path, name) catch |err| {
            std.log.err("failed to join path {s} with {s}: {s}", .{ parent_path, name, @errorName(err) });
            return;
        };
        std.log.debug("adding file {s}", .{path});
        const imgFile = ImgFile.init(path);
        self.files.append(imgFile) catch |err| {
            std.log.err("failed to append image file path:{s}", .{@errorName(err)});
        };
    }
    pub fn dirWalker(self: *DirWalkerImpl) myDir.DirWalker {
        return .{ .ptr = self, .addFn = add, .ifDirShouldBeIgnoredFn = ifDirShouldBeIgnored };
    }
};

fn walkImgDir(allocator: std.mem.Allocator, img_dir: []const u8, ignored_dir: []const u8, files: *ArrayList(ImgFile)) !void {
    var dir: DirWalkerImpl = .{ .alloc = allocator, .ignoredDir = ignored_dir, .files = files };
    const walker = DirWalkerImpl.dirWalker(&dir);
    myDir.walkDir(img_dir, walker);
}

test {
    _ = @import("dir.zig");
}
