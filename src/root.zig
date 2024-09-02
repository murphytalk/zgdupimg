const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const testing = std.testing;
const myDir = @import("dir.zig");
const algo = @import("algo.zig");

pub fn doWork(allocator: std.mem.Allocator, ignored_dir: []const u8, img_dir: []const u8, bin_dir: []const u8) !void {
    _ = bin_dir;
    var imageFiles = ArrayList(AssetFile).init(allocator);
    try walkImgDir(allocator, img_dir, ignored_dir, &imageFiles);
    defer imageFiles.deinit();

    for (imageFiles.items) |f| {
        std.log.info("File path: {s}", .{f.fullPath});
    }
    std.log.info("Total {d}", .{imageFiles.items.len});
}

const AssetFile = struct {
    typ: FileType,
    fullPath: []const u8,
    pub fn init(path: []const u8, t: FileType) AssetFile {
        return AssetFile{ .fullPath = path, .typ = t };
    }
};

const FileType = enum { pic, video };

const DirWalkerImpl = struct {
    //allocator for stuff will live longer than walker
    alloc: std.mem.Allocator,
    ignoredDir: []const u8,
    files: *ArrayList(AssetFile),
    //json files will be freed together with walker
    jsonFiles: ArrayList([]const u8),
    jsonAlloc: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, json_alloc: std.mem.Allocator, ignored_dir: []const u8, files: *ArrayList(AssetFile)) DirWalkerImpl {
        return .{ .alloc = allocator, .jsonAlloc = json_alloc, .ignoredDir = ignored_dir, .files = files, .jsonFiles = ArrayList([]const u8).init(json_alloc) };
    }
    pub fn deinit(self: DirWalkerImpl) void {
        for (self.jsonFiles.items) |f| {
            self.jsonAlloc.free(f);
        }
        self.jsonFiles.deinit();
    }
    pub fn applyMetaInfo(self: DirWalkerImpl) void {
        std.sort.block([]const u8, self.jsonFiles.items, &self, struct {
            pub fn lessThanFn(_: *const DirWalkerImpl, lhs: []const u8, rhs: []const u8) bool {
                return std.mem.lessThan(u8, lhs, rhs);
            }
        }.lessThanFn);
        //for (self.jsonFiles) |_| {}
    }
    pub fn ifDirShouldBeIgnored(ptr: *anyopaque, dirName: []const u8) bool {
        const self: *DirWalkerImpl = @ptrCast(@alignCast(ptr));
        return std.mem.eql(u8, self.ignoredDir, dirName);
    }
    pub fn add(ptr: *anyopaque, parent_path: []const u8, name: []const u8) void {
        const isJson = algo.isJsonFile(name);
        const isPic = algo.isPicFile(name);
        const isVideo = algo.isVideoFile(name);

        if (!isJson and !isPic and !isVideo) {
            std.log.debug("ignored {s}", .{name});
            return;
        }

        const self: *DirWalkerImpl = @ptrCast(@alignCast(ptr));
        const path = myDir.DirWalker.joinPath(if (isJson) self.jsonAlloc else self.alloc, parent_path, name) catch |err| {
            std.log.err("failed to join path {s} with {s}: {s}", .{ parent_path, name, @errorName(err) });
            return;
        };

        if (isJson) {
            std.log.debug("adding json file {s}", .{path});
            self.jsonFiles.append(path) catch |err| {
                std.log.err("failed to add json path {s}: {s}", .{ path, @errorName(err) });
            };
            return;
        }

        std.log.debug("adding file {s}", .{path});
        const imgFile = AssetFile.init(path, if (isPic) .pic else .video);
        self.files.append(imgFile) catch |err| {
            std.log.err("failed to append image file path:{s}", .{@errorName(err)});
        };
    }
    pub fn dirWalker(self: *DirWalkerImpl) myDir.DirWalker {
        return .{ .ptr = self, .addFn = add, .ifDirShouldBeIgnoredFn = ifDirShouldBeIgnored };
    }
};

fn walkImgDir(allocator: std.mem.Allocator, img_dir: []const u8, ignored_dir: []const u8, files: *ArrayList(AssetFile)) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var dir = DirWalkerImpl.init(allocator, gpa.allocator(), ignored_dir, files);
    defer dir.deinit();

    const walker = DirWalkerImpl.dirWalker(&dir);
    myDir.walkDir(img_dir, walker);
}

test "DirWalker sort json files" {
    var files = ArrayList(AssetFile).init(std.testing.allocator);
    defer files.deinit();
    var dir = DirWalkerImpl.init(std.testing.allocator, std.testing.allocator, "", &files);
    defer dir.deinit();
    DirWalkerImpl.add(&dir, "/tmp", "abc.json");
    DirWalkerImpl.add(&dir, "/tmp", "z.json");
    DirWalkerImpl.add(&dir, "/tmp", "abd.json");
    dir.applyMetaInfo();
    try std.testing.expect(std.mem.eql(u8, "/tmp/abc.json", dir.jsonFiles.items[0]));
    try std.testing.expect(std.mem.eql(u8, "/tmp/abd.json", dir.jsonFiles.items[1]));
    try std.testing.expect(std.mem.eql(u8, "/tmp/z.json", dir.jsonFiles.items[2]));
}

test {
    _ = @import("dir.zig");
    _ = @import("algo.zig");
}
