const std = @import("std");
const clap = @import("clap");
const io = std.io;
const root = @import("root.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-d, --dir <str>        Directory to scan images
        \\-b, --bin <str>        Directory to save duplicated images
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    if (res.args.dir) |img_dir| {
        try stdout.print("Scan images in {s}", .{img_dir});
        if (res.args.bin) |bin_dir| {
            try stdout.print("Will save duplicated images in {s}", .{bin_dir});
            try root.doWork(allocator, img_dir, bin_dir);
        } else {
            try stdout.print("-b not specified", .{});
        }
    } else {
        try stdout.print("-d not specified", .{});
    }
    try bw.flush(); // don't forget to flush!
}
