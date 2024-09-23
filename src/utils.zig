const std = @import("std");
const builtin = @import("builtin");

pub const log = std.log.scoped(switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseFast, .ReleaseSafe => .info,
    .ReleaseSmall => .err,
});
