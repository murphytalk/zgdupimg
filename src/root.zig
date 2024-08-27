const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const testing = std.testing;
const myDir = @import("dir.zig");

pub fn doWork(allocator: std.mem.Allocator, img_dir: []const u8, bin_dir: []const u8) !void {
    _ = bin_dir;
    var realDir = myDir.RealDir{ .alloc = allocator, .root_dir = img_dir };
    const dir = myDir.RealDir.myDir(&realDir);
    var imageFiles = try walkImgDir(allocator, dir);
    defer imageFiles.deinit();

    for (imageFiles.items) |f| {
        std.debug.print("File path: {s}\n", .{f.fullPath});
    }
    std.debug.print("Total {d}\n", .{imageFiles.items.len});
}

pub const ImgFile = struct {
    fullPath: []const u8,
    pub fn init(path: []const u8) ImgFile {
        return ImgFile{ .fullPath = path };
    }
};

pub fn walkImgDir(allocator: std.mem.Allocator, dir: myDir.MyDir) !ArrayList(ImgFile) {
    var files = ArrayList(ImgFile).init(allocator);

    try dir.open();
    while (try dir.next()) |file_path| {
        const imgFile = ImgFile.init(file_path);
        try files.append(imgFile);
    }
    return files;
}

const MockedDir = if (builtin.is_test) struct {
    idx: u8 = 0,
    mockedPath: [3][]const u8,
    pub fn open(_: *anyopaque) !void {}
    pub fn next(ptr: *anyopaque) !?[]const u8 {
        const self: *MockedDir = @ptrCast(@alignCast(ptr));
        if (self.idx < 3) {
            const p = self.mockedPath[self.idx];
            self.idx += 1;
            return p;
        } else return null;
    }
    pub fn dir(self: *MockedDir) myDir.MyDir {
        return .{ .ptr = self, .openFn = open, .nextFn = next };
    }
} else struct {};

test "walkDir" {
    const mockedPath = [_][]const u8{ "/stuff/file1", "/stuff/should-be-ignored/file3", "/stuff/file2" };
    var mockedDir = MockedDir{ .mockedPath = mockedPath };
    const dir = MockedDir.dir(&mockedDir);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const l = try walkImgDir(arena.allocator(), dir);
    try testing.expect(l.items.len == 3);
    for (0..3) |i| {
        try testing.expect(std.mem.eql(u8, mockedPath[i], l.items[i].fullPath));
    }
}
