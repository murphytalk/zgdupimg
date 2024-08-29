const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const testing = std.testing;
const myDir = @import("dir.zig");

pub fn doWork(allocator: std.mem.Allocator, ignored_dir: []const u8, img_dir: []const u8, bin_dir: []const u8) !void {
    _ = bin_dir;
    var imageFiles = try walkImgDir(allocator, img_dir, ignored_dir);
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

pub const RealDir = struct {
    alloc: std.mem.Allocator,
    ignoredDir: []const u8,
    files: ArrayList(ImgFile),

    pub fn ifDirShouldBeIgnored(ptr: *anyopaque, dirName: []const u8) bool {
        const self: *RealDir = @ptrCast(@alignCast(ptr));
        return std.mem.eql(u8, self.ignoredDir, dirName);
    }
    pub fn add(ptr: *anyopaque, parent_path: []const u8, name: []const u8) void {
        const self: *RealDir = @ptrCast(@alignCast(ptr));
        const dirs = [_][]const u8{ parent_path, name };
        const path = std.fs.path.join(self.alloc, &dirs);
        const imgFile = ImgFile.init(path);
        self.files.append(imgFile);
    }
    pub fn init(self: *RealDir) myDir.MyDir {
        return .{ .ptr = self, .addFn = add, .ifDirShouldBeIgnoredFn = ifDirShouldBeIgnored };
    }
};

fn walkImgDir(allocator: std.mem.Allocator, img_dir: []const u8, ignored_dir: []const u8) !ArrayList(ImgFile) {
    const files = ArrayList(ImgFile).init(allocator);
    const dir: RealDir = .{ .alloc = allocator, .ignoredDir = ignored_dir, .files = files };
    myDir.walkDir(img_dir, dir);
    return files;
}

//const MockedDir = if (builtin.is_test) struct {
//    idx: u8 = 0,
//    mockedPath: [3][]const u8,
//    pub fn open(_: *anyopaque) !void {}
//    pub fn next(ptr: *anyopaque) !?[]const u8 {
//        const self: *MockedDir = @ptrCast(@alignCast(ptr));
//        if (self.idx < 3) {
//            const p = self.mockedPath[self.idx];
//            self.idx += 1;
//            return p;
//        } else return null;
//    }
//    pub fn dir(self: *MockedDir) myDir.MyDir {
//        return .{ .ptr = self, .openFn = open, .nextFn = next };
//    }
//} else struct {};
//
//test "walkDir" {
//    const ignoredPath = "should-be-ignored";
//    const mockedPath = [_][]const u8{ "/stuff/file1", "/stuff/should-be-ignored/file3", "/stuff/file2" };
//    var mockedDir = MockedDir{ .mockedPath = mockedPath };
//    const dir = MockedDir.dir(&mockedDir);
//
//    var arena = std.heap.ArenaAllocator.init(testing.allocator);
//    defer arena.deinit();
//
//    const l = try walkImgDir(arena.allocator(), dir, ignoredPath);
//    try testing.expect(l.items.len == 3);
//    for (0..3) |i| {
//        try testing.expect(std.mem.eql(u8, mockedPath[i], l.items[i].fullPath));
//    }
//}
