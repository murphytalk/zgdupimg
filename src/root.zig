const std = @import("std");
const ArrayList = std.ArrayList;
const testing = std.testing;

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
}

pub const ImgFile = struct {
    fullPath: []const u8,
    pub fn init(path: []const u8) ImgFile {
        return ImgFile{ .fullPath = path };
    }
};

pub fn walkImgDir(allocator: std.mem.Allocator, img_dir: []const u8) !ArrayList(ImgFile) {
    var files = ArrayList(ImgFile).init(allocator);
    var dir = try std.fs.openDirAbsolute(img_dir, .{ .iterate = true });

    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        const dirs = [_][]const u8{ img_dir, entry.path, entry.basename };
        const imgFile = ImgFile.init(try std.fs.path.join(allocator, &dirs));
        try files.append(imgFile);
    }
    return files;
}
