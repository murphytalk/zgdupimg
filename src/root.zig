const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;
const myDir = @import("dir.zig");

pub fn doWork(img_dir: []const u8, bin_dir: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();

    _ = bin_dir;
    var imageFiles = try walkImgDir(arena_allocator, img_dir);
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

pub fn walkImgDir(allocator: std.mem.Allocator, img_dir: []const u8) !ArrayList(ImgFile) {
    var files = ArrayList(ImgFile).init(allocator);
    var realDir = myDir.RealDir{ .alloc = allocator, .root_dir = img_dir };
    var dir = myDir.RealDir.myDir(&realDir);

    const walker = try dir.open();
    while (try dir.next(walker)) |file_path| {
        const imgFile = ImgFile.init(file_path);
        try files.append(imgFile);
    }
    return files;
}
