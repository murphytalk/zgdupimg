const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const Sha256 = std.crypto.hash.sha2.Sha256;
const media = @import("media.zig");

const Reader = if (builtin.is_test) struct {
    test_data: []const u8,
    idx: usize = 0,
    pub fn read(self: *Reader, buf: []u8) anyerror!usize {
        const left = self.test_data.len - self.idx;
        if (left <= 0) return 0;
        const n = @min(left, buf.len);
        @memcpy(buf[0..n], self.test_data[self.idx .. self.idx + n]);
        self.idx += n;
        return n;
    }
    pub fn deinit(_: Reader) void {}
    // test version: use the part before / as file content
    pub fn init(data: []const u8) !Reader {
        const i = std.mem.indexOfScalar(u8, data, '/') orelse unreachable;
        return .{ .test_data = data[0..i] };
    }
} else struct {
    file: fs.File,
    pub fn init(file_path: []const u8) !Reader {
        return .{ .file = try std.fs.openFileAbsolute(file_path, .{ .mode = .read_only }) };
    }
    pub fn read(self: *Reader, buf: []u8) anyerror!usize {
        const rdr = self.file.reader();
        return try rdr.read(buf);
    }
    pub fn deinit(self: Reader) void {
        self.file.close();
    }
};

fn sha256_digest(comptime BUF_SIZE: u16, reader: *Reader) ![Sha256.digest_length]u8 {
    var sha256 = Sha256.init(.{});

    var buf: [BUF_SIZE]u8 = undefined;
    var n = try reader.read(&buf);
    while (n != 0) {
        sha256.update(buf[0..n]);
        n = try reader.read(&buf);
    }

    return sha256.finalResult();
}

test "test_sha256" {
    const data = "0234567890/";
    var reader1 = try Reader.init(data);
    const r1 = try sha256_digest(100, &reader1);

    var reader1_small_buf = try Reader.init(data);
    const r1_small_buf = try sha256_digest(2, &reader1_small_buf);
    try std.testing.expect(std.mem.eql(u8, &r1, &r1_small_buf));

    var reader2 = try Reader.init("1234567890/");
    const r2 = try sha256_digest(100, &reader2);

    try std.testing.expect(!std.mem.eql(u8, &r1, &r2));
}

fn getExtension(filename: []const u8) ![]const u8 {
    if (std.mem.lastIndexOfScalar(u8, filename, '.')) |last_dot_index| {
        return filename[(last_dot_index + 1)..];
    }
    // No extension found
    return "";
}

const caseAsciiDiff: u8 = 'a' - 'A';
fn charsEqualIgnoreCase(a: u8, b: u8) bool {
    return normalizeChar(a) == normalizeChar(b);
}

// Normalize character to uppercase
fn normalizeChar(c: u8) u8 {
    if (c >= 'a' and c <= 'z') {
        return c - caseAsciiDiff;
    } else {
        return c;
    }
}

pub fn checkFileExtName(fileName: []const u8, expectedExt: []const u8) bool {
    const ext = getExtension(fileName) catch |err| {
        std.log.err("Failed to get file ext name of {s}: {s}", .{ fileName, @errorName(err) });
        return false;
    };
    if (ext.len != expectedExt.len) return false;
    for (ext, expectedExt) |i, k| {
        if (normalizeChar(i) != normalizeChar(k)) return false;
    }
    return true;
}

const jpeg = "jpeg";
const jpg = "jpg";
pub inline fn isPicFile(fileName: []const u8) bool {
    return checkFileExtName(fileName, jpeg) or checkFileExtName(fileName, jpg);
}
const mp4 = "mp4";
const avi = "avi";
const mov = "mov";
const mts = "mts";
pub inline fn isVideoFile(fileName: []const u8) bool {
    return checkFileExtName(fileName, mp4) or checkFileExtName(fileName, avi) or checkFileExtName(fileName, mov) or checkFileExtName(fileName, mts);
}
const json = "json";
pub inline fn isJsonFile(fileName: []const u8) bool {
    return checkFileExtName(fileName, json);
}

test "check file ext name" {
    const expected = "jpeg";
    try std.testing.expect(checkFileExtName("/folder/f1.345.jpeg", expected));
    try std.testing.expect(checkFileExtName("/folder/f1.jpeg", expected));
    try std.testing.expect(checkFileExtName("/folder/f1.JPEG", expected));
    try std.testing.expect(!checkFileExtName("/folder/f1.jpg", expected));
    try std.testing.expect(!checkFileExtName("/folder/f1JPEG", expected));

    try std.testing.expect(isPicFile("/folder/1.jpeg"));
    try std.testing.expect(isPicFile("/folder/1.jpEG"));
    try std.testing.expect(isPicFile("/folder/1.jpg"));
    try std.testing.expect(!isPicFile("/folder/1.jpg1"));

    try std.testing.expect(isJsonFile("IMG_0876.JPG.json"));

    try std.testing.expect(isVideoFile("abcd.efg.mp4"));
}

fn img1HasHigerProrityThanImg2(f1: media.AssetFile, f2: media.AssetFile) bool {
    const f1HasMeta = f1.meta != null;
    const f2HasMeta = f2.meta != null;
    if (!(f1HasMeta and f2HasMeta) and (f1HasMeta or f2HasMeta)) {
        return if (f1HasMeta) true else false;
    }
    const f1nameLessThanf2Name = std.mem.lessThan(u8, f1.fullPath, f2.fullPath);
    return if (f1nameLessThanf2Name) true else false;
}

const FileHash = struct { hash: [Sha256.digest_length]u8, file: *media.AssetFile };

pub fn findDuplicatedImgFiles(allocator: std.mem.Allocator, files: std.ArrayList(media.AssetFile)) void {
    var hashes = std.ArrayList(FileHash).init(allocator);
    defer hashes.deinit();

    var count: usize = 0;
    for (files.items) |*f| {
        if (f.typ != .pic) continue;
        count += 1;
        var reader = Reader.init(f.fullPath) catch |err| {
            std.log.err("Failed to open file {s} to calc hash: {s}", .{ f.fullPath, @errorName(err) });
            continue;
        };
        defer reader.deinit();
        const hash = sha256_digest(4096, &reader) catch |err| {
            std.log.err("Failed to calc bash of file {s}:{s}", .{ f.fullPath, @errorName(err) });
            continue;
        };
        hashes.append(.{ .hash = hash, .file = f }) catch |err| {
            std.log.err("Failed to add bash of file {s}:{s}", .{ f.fullPath, @errorName(err) });
        };
    }
    std.log.info("Calculated hash of {d} image files", .{count});

    std.sort.block(FileHash, hashes.items, @as(u8, 0), struct {
        fn lessThan(_: u8, lhs: FileHash, rhs: FileHash) bool {
            const odr = std.mem.order(u8, &lhs.hash, &rhs.hash);
            return switch (odr) {
                .eq => img1HasHigerProrityThanImg2(lhs.file.*, rhs.file.*),
                .lt => true,
                .gt => false,
            };
        }
    }.lessThan);
    std.log.info("Sorted {d} image files by hash", .{count});

    var last: ?FileHash = null;
    for (hashes.items) |h| {
        if (last) |l| {
            if (std.mem.eql(u8, &l.hash, &h.hash)) {
                // h is duplicated with l and has lower priority
                h.file.duplicated = l.file.fullPath;
            } else {
                last = h;
            }
        } else {
            last = h;
        }
    }
    std.log.info("Duplicated files marked", .{});
}

test "find duplicated files" {
    const allocator = std.testing.allocator;
    var files = std.ArrayList(media.AssetFile).init(allocator);
    defer files.deinit();

    try files.append(media.AssetFile.init("content1/f1.jpg", .pic));
    try files.append(media.AssetFile.init("content2/f2.jpg", .pic));
    try files.append(media.AssetFile.init("content1/f3.jpg", .pic));
    try files.append(media.AssetFile.init("content2/f4.jpg", .pic));
    try files.append(media.AssetFile.init("content0/f5.jpg", .pic));

    var content1WithMeta = media.AssetFile.init("content1/ZZZ.jpg", .pic);
    content1WithMeta.meta = .{};
    try files.append(content1WithMeta);

    findDuplicatedImgFiles(allocator, files);
    for (files.items) |f| {
        if (std.mem.eql(u8, "content1/f1.jpg", f.fullPath)) {
            const dupicated_with = f.duplicated orelse unreachable;
            try std.testing.expect(std.mem.eql(u8, dupicated_with, "content1/ZZZ.jpg"));
        } else if (std.mem.eql(u8, "content2/f2.jpg", f.fullPath)) {
            try std.testing.expect(f.duplicated == null);
        } else if (std.mem.eql(u8, "content1/f3.jpg", f.fullPath)) {
            const dupicated_with = f.duplicated orelse unreachable;
            try std.testing.expect(std.mem.eql(u8, dupicated_with, "content1/ZZZ.jpg"));
        } else if (std.mem.eql(u8, "content2/f4.jpg", f.fullPath)) {
            const dupicated_with = f.duplicated orelse unreachable;
            try std.testing.expect(std.mem.eql(u8, dupicated_with, "content2/f2.jpg"));
        } else if (std.mem.eql(u8, "content1/ZZZ.jpg", f.fullPath)) {
            try std.testing.expect(f.duplicated == null);
        } else if (std.mem.eql(u8, "content0/f5.jpg", f.fullPath)) {
            try std.testing.expect(f.duplicated == null);
        } else unreachable;
    }
}
