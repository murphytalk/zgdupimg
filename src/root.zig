const std = @import("std");
const testing = std.testing;

pub fn doWork(img_dir: []const u8, bin_dir: []const u8) !void {
    _ = bin_dir;
    try walkImgDir(img_dir);
}

pub fn walkImgDir(img_dir: []const u8) !void {
    var dir = try std.fs.openDirAbsolute(img_dir, .{ .iterate = true });

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();

    var walker = try dir.walk(arena_allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        const dirs = [_][]const u8{ img_dir, entry.path, entry.basename };
        const path_buffer = try std.fs.path.join(arena_allocator, &dirs);
        std.debug.print("File path: {s}\n", .{path_buffer});
    }
}
