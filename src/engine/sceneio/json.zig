const std = @import("std");
const rl = @import("raylib");

const types = @import("types.zig");

pub const JsonError = error{
    InvalidJson,
    MissingField,
    InvalidType,
    InvalidValue,
};

pub fn loadSceneIR(allocator: std.mem.Allocator, path: []const u8) !types.SceneIR {
    const io = std.Io.Threaded.global_single_threaded.io();
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var reader = file.reader(io, &.{});
    const text = try reader.interface.allocRemaining(allocator, .limited(1 << 20));
    defer allocator.free(text);

    return parseSceneIR(allocator, text);
}

pub fn parseSceneIR(allocator: std.mem.Allocator, text: []const u8) !types.SceneIR {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, text, .{}) catch return JsonError.InvalidJson;
    defer parsed.deinit();

    return try parseRoot(allocator, parsed.value);
}

fn parseRoot(allocator: std.mem.Allocator, root: std.json.Value) !types.SceneIR {
    if (root != .object) return JsonError.InvalidType;

    const obj = root.object;

    const name_val = obj.get("name") orelse return JsonError.MissingField;
    const name = try dupString(allocator, try asString(name_val));

    var scene_type: types.SceneType = .exploration;
    if (obj.get("type")) |tval| {
        const t = try asString(tval);
        if (std.mem.eql(u8, t, "exploration")) scene_type = .exploration else if (std.mem.eql(u8, t, "visual_novel")) scene_type = .visual_novel else return JsonError.InvalidValue;
    }

    var width: i32 = 800;
    var height: i32 = 450;

    if (obj.get("size")) |sval| {
        if (sval != .object) return JsonError.InvalidType;
        if (sval.object.get("width")) |w| width = @intCast(try asInt(w));
        if (sval.object.get("height")) |h| height = @intCast(try asInt(h));
    }

    const entities_val = obj.get("entities") orelse return JsonError.MissingField;
    const entities = try parseEntities(allocator, entities_val);

    return .{
        .name = name,
        .scene_type = scene_type,
        .width = width,
        .height = height,
        .entities = entities,
    };
}

fn parseEntities(allocator: std.mem.Allocator, v: std.json.Value) ![]types.EntityIR {
    if (v != .array) return JsonError.InvalidType;

    const arr = v.array.items;
    var entities = try allocator.alloc(types.EntityIR, arr.len);

    for (arr, 0..) |item, i| {
        entities[i] = try parseEntity(allocator, item);
    }

    return entities;
}

fn parseEntity(allocator: std.mem.Allocator, v: std.json.Value) !types.EntityIR {
    if (v != .object) return JsonError.InvalidType;

    const obj = v.object;

    var tag: ?[]const u8 = null;
    if (obj.get("tag")) |t| {
        tag = try dupString(allocator, try asString(t));
    }

    const comps_val = obj.get("components") orelse return JsonError.MissingField;
    const components = try parseComponents(allocator, comps_val);

    return .{ .tag = tag, .components = components };
}

fn parseComponents(allocator: std.mem.Allocator, v: std.json.Value) ![]types.ComponentIR {
    if (v != .object) return JsonError.InvalidType;

    var count: usize = 0;
    var it = v.object.iterator();
    while (it.next()) |_| count += 1;

    var out = try allocator.alloc(types.ComponentIR, count);

    var idx: usize = 0;
    var it2 = v.object.iterator();
    while (it2.next()) |entry| {
        out[idx] = try parseComponent(allocator, entry.key_ptr.*, entry.value_ptr.*);
        idx += 1;
    }

    return out;
}

fn parseComponent(allocator: std.mem.Allocator, key: []const u8, v: std.json.Value) !types.ComponentIR {
    if (std.mem.eql(u8, key, "Transform")) {
        return .{ .Transform = try parseTransform(v) };
    }

    if (std.mem.eql(u8, key, "Sprite")) {
        return .{ .Sprite = try parseSprite(allocator, v) };
    }

    if (std.mem.eql(u8, key, "Circle")) {
        return .{ .Circle = try parseCircle(v) };
    }

    if (std.mem.eql(u8, key, "Rect")) {
        return .{ .Rect = try parseRect(v) };
    }

    if (std.mem.eql(u8, key, "Camera")) {
        return .{ .Camera = try parseCamera(allocator, v) };
    }

    if (std.mem.eql(u8, key, "PlayerController")) {
        return .{ .PlayerController = try parsePlayerController(v) };
    }

    if (std.mem.eql(u8, key, "Trigger")) {
        return .{ .Trigger = try parseTrigger(allocator, v) };
    }

    return JsonError.InvalidValue;
}

fn parseTransform(v: std.json.Value) !types.TransformIR {
    if (v != .object) return JsonError.InvalidType;

    var out: types.TransformIR = .{};

    if (v.object.get("position")) |p| out.position = try parseVec2(p);
    if (v.object.get("rotation")) |r| out.rotation = @floatCast(try asFloat(r));
    if (v.object.get("scale")) |s| out.scale = try parseVec2(s);

    return out;
}

fn parseSprite(allocator: std.mem.Allocator, v: std.json.Value) !types.SpriteIR {
    if (v != .object) return JsonError.InvalidType;

    const tex = v.object.get("texture") orelse return JsonError.MissingField;
    const texture = try dupString(allocator, try asString(tex));

    var flip_x: bool = false;
    if (v.object.get("flipX")) |f| flip_x = try asBool(f);

    var tint: ?rl.Color = null;
    if (v.object.get("tint")) |t| tint = try parseColor(t);

    return .{ .texture = texture, .flip_x = flip_x, .tint = tint };
}

fn parseCircle(v: std.json.Value) !types.CircleIR {
    if (v != .object) return JsonError.InvalidType;

    const radius_val = v.object.get("radius") orelse return JsonError.MissingField;
    const color_val = v.object.get("color") orelse return JsonError.MissingField;

    return .{
        .radius = @floatCast(try asFloat(radius_val)),
        .color = try parseColor(color_val) orelse return JsonError.InvalidValue,
    };
}

fn parseRect(v: std.json.Value) !types.RectIR {
    if (v != .object) return JsonError.InvalidType;

    const wv = v.object.get("width") orelse return JsonError.MissingField;
    const hv = v.object.get("height") orelse return JsonError.MissingField;
    const cv = v.object.get("color") orelse return JsonError.MissingField;

    return .{
        .width = @floatCast(try asFloat(wv)),
        .height = @floatCast(try asFloat(hv)),
        .color = try parseColor(cv) orelse return JsonError.InvalidValue,
    };
}

fn parseCamera(allocator: std.mem.Allocator, v: std.json.Value) !types.CameraIR {
    if (v != .object) return JsonError.InvalidType;

    const offset_val = v.object.get("offset") orelse return JsonError.MissingField;
    var out: types.CameraIR = .{ .offset = try parseVec2(offset_val) };

    if (v.object.get("rotation")) |r| out.rotation = @floatCast(try asFloat(r));
    if (v.object.get("zoom")) |z| out.zoom = @floatCast(try asFloat(z));
    if (v.object.get("followTag")) |ft| out.follow_tag = try dupString(allocator, try asString(ft));

    return out;
}

fn parsePlayerController(v: std.json.Value) !types.PlayerControllerIR {
    if (v != .object) return JsonError.InvalidType;

    var out: types.PlayerControllerIR = .{};
    if (v.object.get("speed")) |s| out.speed = @floatCast(try asFloat(s));
    return out;
}

fn parseTrigger(allocator: std.mem.Allocator, v: std.json.Value) !types.TriggerIR {
    if (v != .object) return JsonError.InvalidType;

    const bounds_val = v.object.get("bounds") orelse return JsonError.MissingField;
    const action_val = v.object.get("action") orelse return JsonError.MissingField;

    var one_shot = false;
    if (v.object.get("oneShot")) |o| one_shot = try asBool(o);

    return .{
        .bounds = try parseRect4(bounds_val),
        .one_shot = one_shot,
        .action = try parseTriggerAction(allocator, action_val),
    };
}

fn parseTriggerAction(allocator: std.mem.Allocator, v: std.json.Value) !types.TriggerActionIR {
    if (v != .object) return JsonError.InvalidType;

    if (v.object.get("startDialogue")) |sd| {
        if (sd != .object) return JsonError.InvalidType;
        var label: ?[]const u8 = null;
        if (sd.object.get("label")) |l| label = try dupString(allocator, try asString(l));
        return .{ .StartDialogue = .{ .label = label } };
    }

    if (v.object.get("showMessage")) |sm| {
        if (sm != .object) return JsonError.InvalidType;
        const text_val = sm.object.get("text") orelse return JsonError.MissingField;
        var duration: f32 = 2.0;
        if (sm.object.get("duration")) |d| duration = @floatCast(try asFloat(d));
        return .{ .ShowMessage = .{ .text = try dupString(allocator, try asString(text_val)), .duration = duration } };
    }

    if (v.object.get("changeScene")) |cs| {
        if (cs != .object) return JsonError.InvalidType;
        var idx: ?usize = null;
        var name: ?[]const u8 = null;
        if (cs.object.get("index")) |i| idx = @intCast(try asInt(i));
        if (cs.object.get("name")) |n| name = try dupString(allocator, try asString(n));
        return .{ .ChangeScene = .{ .index = idx, .name = name } };
    }

    if (v.object.get("setFlag")) |sf| {
        if (sf != .object) return JsonError.InvalidType;
        const name_val = sf.object.get("name") orelse return JsonError.MissingField;
        var value: bool = true;
        if (sf.object.get("value")) |vv| value = try asBool(vv);
        return .{ .SetFlag = .{ .name = try dupString(allocator, try asString(name_val)), .value = value } };
    }

    return JsonError.InvalidValue;
}

fn parseVec2(v: std.json.Value) !rl.Vector2 {
    if (v != .array) return JsonError.InvalidType;
    if (v.array.items.len != 2) return JsonError.InvalidValue;

    const x = try asFloat(v.array.items[0]);
    const y = try asFloat(v.array.items[1]);
    return .{ .x = @floatCast(x), .y = @floatCast(y) };
}

fn parseRect4(v: std.json.Value) !rl.Rectangle {
    if (v != .array) return JsonError.InvalidType;
    if (v.array.items.len != 4) return JsonError.InvalidValue;

    const x = try asFloat(v.array.items[0]);
    const y = try asFloat(v.array.items[1]);
    const w = try asFloat(v.array.items[2]);
    const h = try asFloat(v.array.items[3]);

    return .{ .x = @floatCast(x), .y = @floatCast(y), .width = @floatCast(w), .height = @floatCast(h) };
}

fn parseColor(v: std.json.Value) !?rl.Color {
    const s = try asString(v);
    if (types.parseColor(s)) |c| return c;
    if (types.parseColorHex(s)) |c2| return c2;
    return null;
}

fn asString(v: std.json.Value) ![]const u8 {
    return switch (v) {
        .string => v.string,
        else => JsonError.InvalidType,
    };
}

fn asBool(v: std.json.Value) !bool {
    return switch (v) {
        .bool => v.bool,
        else => JsonError.InvalidType,
    };
}

fn asInt(v: std.json.Value) !i64 {
    return switch (v) {
        .integer => v.integer,
        .float => @intFromFloat(v.float),
        else => JsonError.InvalidType,
    };
}

fn asFloat(v: std.json.Value) !f64 {
    return switch (v) {
        .float => v.float,
        .integer => @floatFromInt(v.integer),
        else => JsonError.InvalidType,
    };
}

fn dupString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, s.len);
    @memcpy(buf, s);
    return buf;
}

test "scene parser accepts reference crossroads scene" {
    const text = @embedFile("../../../assets/reference-game/crossroads.json");
    const ir = try parseSceneIR(std.testing.allocator, text);
    try std.testing.expectEqualStrings("crossroads", ir.name);
    try std.testing.expectEqual(@as(usize, 6), ir.entities.len);

    var found_sprite = false;
    var found_trigger = false;
    for (ir.entities) |entity| {
        for (entity.components) |component| {
            switch (component) {
                .Sprite => |sprite| {
                    found_sprite = true;
                    try std.testing.expectEqualStrings("reference-game/player.png", sprite.texture);
                },
                .Trigger => |trigger| {
                    found_trigger = true;
                    try std.testing.expect(std.meta.activeTag(trigger.action) == .SetFlag);
                    try std.testing.expectEqualStrings("stone_touched", trigger.action.SetFlag.name);
                },
                else => {},
            }
        }
    }

    try std.testing.expect(found_sprite);
    try std.testing.expect(found_trigger);
}

test "scene parser accepts reference clearing scene" {
    const text = @embedFile("../../../assets/reference-game/clearing.json");
    const ir = try parseSceneIR(std.testing.allocator, text);
    try std.testing.expectEqualStrings("clearing", ir.name);
    try std.testing.expectEqual(@as(i32, 800), ir.width);
    try std.testing.expectEqual(@as(i32, 450), ir.height);
}

test "scene parser rejects unknown component" {
    const text =
        \\{
        \\  "name": "bad",
        \\  "entities": [
        \\    { "tag": "thing", "components": { "Missing": {} } }
        \\  ]
        \\}
    ;

    try std.testing.expectError(JsonError.InvalidValue, parseSceneIR(std.testing.allocator, text));
}
