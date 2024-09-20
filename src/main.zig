const std = @import("std");
const builtin = @import("builtin");
const clap = @import("clap");
const io = std.io;
const root = @import("root.zig");
const utils = @import("utils.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-d, --dir <str>         Directory to scan images
        \\-b, --bin <str>         Directory to save duplicated images
        \\-i, --ignorePath <str>  Directory to ignore when searching images
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

    const ignoreDir: []const u8 = res.args.ignorePath orelse "@eaDir";

    if (res.args.dir) |img_dir| {
        utils.log.debug("program started", .{});
        utils.log.info("Scan images in {s}, ignoring dir: {s}", .{ img_dir, ignoreDir });
        if (res.args.bin) |bin_dir| {
            utils.log.info("Will save duplicated images in {s}", .{bin_dir});
            try root.doWork(allocator, ignoreDir, img_dir, bin_dir);
        } else {
            utils.log.info("-b not specified", .{});
        }
    } else {
        utils.log.info("-d not specified", .{});
    }
}
