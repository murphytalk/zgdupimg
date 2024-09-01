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
};

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
