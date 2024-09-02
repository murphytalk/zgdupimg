const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const Sha256 = std.crypto.hash.sha2.Sha256;

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
} else struct {
    file: fs.File,
    pub fn read(self: *Reader, buf: []u8) anyerror!usize {
        const rdr = self.file.reader();
        return try rdr.read(&buf);
    }
    pub fn deinit(self: Reader) !void {
        self.file.close();
    }
};

pub fn calcFileHash(filePath: []const u8) ![Sha256.digest_length]u8 {
    const reader: Reader = .{ .file = std.fs.openFileAbsolute(filePath, .{ .mode = .read_only }) };
    defer reader.deinit();
    return sha256_digest(4096, &reader);
}

fn sha256_digest(comptime BUF_SIZE: u8, reader: *Reader) ![Sha256.digest_length]u8 {
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
    const data = "0234567890";
    var reader1: Reader = .{ .test_data = data };
    const r1 = try sha256_digest(100, &reader1);

    var reader1_small_buf: Reader = .{ .test_data = data };
    const r1_small_buf = try sha256_digest(2, &reader1_small_buf);
    try std.testing.expect(std.mem.eql(u8, &r1, &r1_small_buf));

    var reader2: Reader = .{ .test_data = "1234567890" };
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
pub inline fn isVideoFile(fileName: []const u8) bool {
    return checkFileExtName(fileName, mp4) or checkFileExtName(fileName, avi);
}
const json = "json";
pub inline fn isJsonFile(fileName: []const u8) bool {
    return checkFileExtName(fileName, json);
}

test "check_file_ext_name" {
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
