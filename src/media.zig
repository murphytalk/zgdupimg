const std = @import("std");

const GoogleMetaTime = struct {
    timestamp: u64,
    formatted: ?[]const u8 = "",
};
const GeoData = struct {
    latitude: f64,
    longitude: f64,
    altitude: f64,
    latitudeSpan: f64,
    longitudeSpan: f64,
};
const GoogleMeta = struct {
    title: []const u8 = "",
    description: []const u8 = "",
    imageViews: u32 = 0,
    creationTime: ?GoogleMetaTime = null,
    photoTakenTime: ?GoogleMetaTime = null,
    geoData: ?GeoData = null,
    geoDataExif: ?GeoData = null,
    people: ?[]struct {
        name: []const u8,
    } = null,
    url: []const u8 = "",
};

pub const MediaMeta = struct {
    timestamp: u64 = 0,
    geoData: ?GeoData = null,
    pub fn init(googleMeta: GoogleMeta) MediaMeta {
        const tm = googleMeta.photoTakenTime orelse googleMeta.creationTime;
        const tmstmp = if (tm) |t| t.timestamp else 0;
        return .{ .timestamp = tmstmp, .geoData = googleMeta.geoData orelse googleMeta.geoDataExif };
    }
};

fn parseGoogleMeta(allocator: std.mem.Allocator, jsonStr: []const u8) !std.json.Parsed(GoogleMeta) {
    return try std.json.parseFromSlice(GoogleMeta, allocator, jsonStr, .{ .ignore_unknown_fields = true });
}

pub fn parseMediaMeta(allocator: std.mem.Allocator, json: []const u8) !MediaMeta {
    const meta = try parseGoogleMeta(allocator, json);
    defer meta.deinit();
    return MediaMeta.init(meta.value);
}

test "parse json meta" {
    const json =
        \\{
        \\  "unexpectedField" : 10,
        \\  "description": "",
        \\  "imageViews": "7",
        \\  "creationTime": {
        \\    "timestamp": "1503902470",
        \\    "formatted": "2017年8月28日 UTC 06:41:10"
        \\  },
        \\  "photoTakenTime": {
        \\    "timestamp": "1503897131",
        \\    "formatted": "2017年8月28日 UTC 05:12:11"
        \\  },
        \\  "geoData": {
        \\    "latitude": 35.7099304,
        \\    "longitude": 139.8115387,
        \\    "altitude": 55.3,
        \\    "latitudeSpan": 0.0,
        \\    "longitudeSpan": 0.0
        \\  },
        \\  "geoDataExif": {
        \\    "latitude": 35.7099304,
        \\    "longitude": 139.8115387,
        \\    "altitude": 55.3,
        \\    "latitudeSpan": 0.0,
        \\    "longitudeSpan": 0.0
        \\  },
        \\  "people": [{
        \\    "name": "tester"
        \\  }],
        \\  "url": "https://photos.google.com/photo/AF1QipP18DJYl9sWpmGZ58kOKKXynw7N1oDLB8-Gtmiq"
        \\}
    ;
    const meta = try parseGoogleMeta(std.testing.allocator, json);
    defer meta.deinit();
    if (meta.value.geoData) |geo| {
        try std.testing.expect(geo.latitude == 35.7099304);
    } else try std.testing.expect(false);
    if (meta.value.creationTime) |time| {
        try std.testing.expect(time.timestamp == 1503902470);
    } else try std.testing.expect(false);
}

test "parse json meta : pick preferred field" {
    const json =
        \\{
        \\  "creationTime": {
        \\    "timestamp": "1503902470"
        \\  },
        \\  "photoTakenTime": {
        \\    "timestamp": "1503897131"
        \\  },
        \\  "geoData": {
        \\    "latitude": 35,
        \\    "longitude": 139,
        \\    "altitude": 55.3,
        \\    "latitudeSpan": 0.0,
        \\    "longitudeSpan": 0.0
        \\  },
        \\  "geoDataExif": {
        \\    "latitude": 35.7099304,
        \\    "longitude": 139.8115387,
        \\    "altitude": 55.3,
        \\    "latitudeSpan": 0.0,
        \\    "longitudeSpan": 0.0
        \\  },
        \\  "people": [{
        \\    "name": "tester"
        \\  }],
        \\  "url": "https://photos.google.com/photo/AF1QipP18DJYl9sWpmGZ58kOKKXynw7N1oDLB8-Gtmiq"
        \\}
    ;
    const meta = try parseMediaMeta(std.testing.allocator, json);
    try std.testing.expect(meta.timestamp == 1503897131);
    const g = meta.geoData orelse unreachable;
    try std.testing.expect(g.latitude == 35);
}
