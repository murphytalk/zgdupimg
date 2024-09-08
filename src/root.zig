const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const testing = std.testing;
const myDir = @import("dir.zig");
const algo = @import("algo.zig");
const media = @import("media.zig");
const AssetFile = media.AssetFile;

pub fn doWork(allocator: std.mem.Allocator, ignored_dir: []const u8, img_dir: []const u8, bin_dir: []const u8) !void {
    _ = bin_dir;
    var imageFiles = ArrayList(AssetFile).init(allocator);
    try walkImgDir(allocator, img_dir, ignored_dir, &imageFiles);
    std.log.info("Found {} files", .{imageFiles.items.len});
    defer imageFiles.deinit();

    algo.findDuplicatedImgFiles(allocator, imageFiles);

    for (imageFiles.items) |f| {
        if (f.duplicated) |d| {
            std.log.info("Duplicated file path: {s} , meta {any}, duplicated with {s}", .{ f.fullPath, f.meta, d });
        }
    }
    std.log.info("Total {d}", .{imageFiles.items.len});
}

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

    // prerequisite: json files are sorted
    fn findJsonMetaFile(self: DirWalkerImpl, asset: AssetFile) ?[]const u8 {
        if (std.sort.binarySearch([]const u8, asset, self.jsonFiles.items, asset, struct {
            fn byBaseName(_: AssetFile, key: AssetFile, midJsonPath: []const u8) std.math.Order {
                const imgFileBaseNameLen = key.fullPath.len;
                const jsnFileBaseNameLen = std.mem.lastIndexOfScalar(u8, midJsonPath, '.') orelse 0;
                const imgFileBaseName = key.fullPath[0..imgFileBaseNameLen];
                const jsnFileBaseName = midJsonPath[0..jsnFileBaseNameLen];
                if (std.mem.eql(u8, imgFileBaseName, jsnFileBaseName)) return .eq;
                return if (std.mem.lessThan(u8, imgFileBaseName, jsnFileBaseName)) .lt else .gt;
            }
        }.byBaseName)) |idx| {
            return self.jsonFiles.items[idx];
        } else return null;
    }

    fn sortJsonFiles(self: DirWalkerImpl) void {
        std.sort.block([]const u8, self.jsonFiles.items, &self, struct {
            fn lessThanFn(_: *const DirWalkerImpl, lhs: []const u8, rhs: []const u8) bool {
                return std.mem.lessThan(u8, lhs, rhs);
            }
        }.lessThanFn);
    }

    pub fn applyMetaInfo(ptr: *anyopaque) void {
        const self: *DirWalkerImpl = @ptrCast(@alignCast(ptr));
        self.sortJsonFiles();
        for (self.files.items) |*f| {
            if (f.typ != .pic) continue;
            if (self.findJsonMetaFile(f.*)) |jsonFile| {
                if (self.loadImgMetaJson(jsonFile)) |meta| {
                    f.meta = meta;
                } else |err| {
                    std.log.err("Failed to load meta info from {s}: {s}", .{ jsonFile, @errorName(err) });
                }
            }
        }
    }

    pub fn loadImgMetaJson(self: DirWalkerImpl, jsonFile: []const u8) !media.MediaMeta {
        const f = try std.fs.openFileAbsolute(jsonFile, .{ .mode = .read_only });
        defer f.close();
        const size = try f.getEndPos();
        const buf = try self.jsonAlloc.alloc(u8, size);
        defer self.jsonAlloc.free(buf);
        _ = try f.readAll(buf);
        return try media.parseMediaMeta(self.jsonAlloc, buf);
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
        return .{ .ptr = self, .addFn = add, .ifDirShouldBeIgnoredFn = ifDirShouldBeIgnored, .applyMetaInfoFn = applyMetaInfo };
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

test "DirWalker sort and find json file" {
    var files = ArrayList(AssetFile).init(std.testing.allocator);
    defer files.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var dir = DirWalkerImpl.init(arena.allocator(), std.testing.allocator, "", &files);
    defer dir.deinit();

    DirWalkerImpl.add(&dir, "/tmp", "abc.jpeg.json");
    DirWalkerImpl.add(&dir, "/tmp", "z.jpg");
    DirWalkerImpl.add(&dir, "/tmp", "z.jpg.json");
    DirWalkerImpl.add(&dir, "/tmp", "no.jpg");
    DirWalkerImpl.add(&dir, "/tmp", "abd.JPG.json");
    DirWalkerImpl.add(&dir, "/tmp", "abc.jpeg");
    DirWalkerImpl.add(&dir, "/tmp", "abd.JPG");

    try std.testing.expect(dir.jsonFiles.items.len == 3);
    try std.testing.expect(files.items.len == 4);

    dir.sortJsonFiles();
    try std.testing.expect(std.mem.eql(u8, "/tmp/abc.jpeg.json", dir.jsonFiles.items[0]));
    try std.testing.expect(std.mem.eql(u8, "/tmp/abd.JPG.json", dir.jsonFiles.items[1]));
    try std.testing.expect(std.mem.eql(u8, "/tmp/z.jpg.json", dir.jsonFiles.items[2]));

    try std.testing.expect(std.mem.eql(u8, "/tmp/z.jpg", files.items[0].fullPath));
    const jsonPath = dir.findJsonMetaFile(files.items[0]) orelse unreachable;
    try std.testing.expect(std.mem.eql(u8, "/tmp/z.jpg.json", jsonPath));

    const jsonPath2 = dir.findJsonMetaFile(files.items[3]) orelse unreachable;
    try std.testing.expect(std.mem.eql(u8, "/tmp/abd.JPG.json", jsonPath2));

    const notExist: AssetFile = .{ .fullPath = "/tmp/fake.jpg", .typ = .pic, .meta = .{} };
    try std.testing.expect(if (dir.findJsonMetaFile(notExist)) |_| false else true);
}

test {
    _ = @import("dir.zig");
    _ = @import("algo.zig");
    _ = @import("media.zig");
}
