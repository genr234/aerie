const std = @import("std");
const rl = @import("raylib");

const types = @import("types.zig");

pub const JsonError = error{
    InvalidJson,
    MissingField,
    InvalidType,
    InvalidValue,
};

const ParseError = JsonError || std.mem.Allocator.Error;

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

    var background_color: ?rl.Color = null;
    if (obj.get("background")) |bg| {
        if (bg != .object) return JsonError.InvalidType;
        if (bg.object.get("color")) |color| background_color = try parseColor(color);
    }

    const entities_val = obj.get("entities") orelse return JsonError.MissingField;
    const entities = try parseEntities(allocator, entities_val);

    return .{
        .name = name,
        .scene_type = scene_type,
        .width = width,
        .height = height,
        .background_color = background_color,
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

    if (std.mem.eql(u8, key, "Solid")) {
        return .{ .Solid = try parseSolid(v) };
    }

    if (std.mem.eql(u8, key, "Animation")) {
        return .{ .Animation = try parseAnimation(allocator, v) };
    }

    if (std.mem.eql(u8, key, "Tilemap")) {
        return .{ .Tilemap = try parseTilemap(allocator, v) };
    }

    if (std.mem.eql(u8, key, "ParticleEmitter")) {
        return .{ .ParticleEmitter = try parseParticleEmitter(v) };
    }

    if (std.mem.eql(u8, key, "Tween")) {
        return .{ .Tween = try parseTween(v) };
    }

    if (std.mem.eql(u8, key, "Trigger")) {
        return .{ .Trigger = try parseTrigger(allocator, v) };
    }

    if (std.mem.eql(u8, key, "BoxCollider")) {
        return .{ .BoxCollider = try parseBoxCollider(v) };
    }

    if (std.mem.eql(u8, key, "Interactable")) {
        return .{ .Interactable = try parseInteractable(allocator, v) };
    }

    if (std.mem.eql(u8, key, "Portal")) {
        return .{ .Portal = try parsePortal(allocator, v) };
    }

    if (std.mem.eql(u8, key, "SpawnPoint")) {
        return .{ .SpawnPoint = try parseSpawnPoint(allocator, v) };
    }

    if (std.mem.eql(u8, key, "Layer")) {
        return .{ .Layer = try parseLayer(v) };
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

fn parseLayer(v: std.json.Value) !types.LayerIR {
    if (v != .object) return JsonError.InvalidType;

    var out: types.LayerIR = .{};
    if (v.object.get("order")) |order| out.order = @intCast(try asInt(order));
    if (v.object.get("ySort")) |y_sort| out.y_sort = try asBool(y_sort);
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

    var out = types.SpriteIR{ .texture = texture, .flip_x = flip_x, .tint = tint };
    if (v.object.get("frameWidth")) |fw| out.frame_width = @floatCast(try asFloat(fw));
    if (v.object.get("frameHeight")) |fh| out.frame_height = @floatCast(try asFloat(fh));
    if (v.object.get("frames")) |frames| out.frames = @intCast(try asInt(frames));
    if (v.object.get("fps")) |fps| out.fps = @floatCast(try asFloat(fps));
    if (v.object.get("loop")) |loop| out.loop = try asBool(loop);

    return out;
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
    if (v.object.get("smoothing")) |s| out.smoothing = @floatCast(try asFloat(s));
    if (v.object.get("clampToScene")) |c| out.clamp_to_scene = try asBool(c);
    if (v.object.get("followTag")) |ft| out.follow_tag = try dupString(allocator, try asString(ft));

    return out;
}

fn parsePlayerController(v: std.json.Value) !types.PlayerControllerIR {
    if (v != .object) return JsonError.InvalidType;

    var out: types.PlayerControllerIR = .{};
    if (v.object.get("speed")) |s| out.speed = @floatCast(try asFloat(s));
    if (v.object.get("mode")) |m| out.mode = try parseMovementMode(try asString(m));
    if (v.object.get("stepSize")) |s| out.step_size = @floatCast(try asFloat(s));
    if (v.object.get("stepTime")) |s| out.step_time = @floatCast(try asFloat(s));
    return out;
}

fn parseSolid(v: std.json.Value) !types.SolidIR {
    if (v != .object) return JsonError.InvalidType;
    var out: types.SolidIR = .{};
    if (v.object.get("enabled")) |enabled| out.enabled = try asBool(enabled);
    return out;
}

fn parseAnimation(allocator: std.mem.Allocator, v: std.json.Value) !types.AnimationIR {
    if (v != .object) return JsonError.InvalidType;
    var out: types.AnimationIR = .{};
    if (v.object.get("current")) |current| out.current = try dupString(allocator, try asString(current));

    if (v.object.get("clips")) |clips_val| {
        if (clips_val != .array) return JsonError.InvalidType;
        const items = clips_val.array.items;
        const clips = try allocator.alloc(types.AnimationClipIR, items.len);
        for (items, 0..) |item, i| {
            if (item != .object) return JsonError.InvalidType;
            const name_val = item.object.get("name") orelse return JsonError.MissingField;
            var clip = types.AnimationClipIR{ .name = try dupString(allocator, try asString(name_val)) };
            if (item.object.get("start")) |start| clip.start = @intCast(try asInt(start));
            if (item.object.get("frames")) |frames| clip.frames = @intCast(try asInt(frames));
            if (item.object.get("fps")) |fps| clip.fps = @floatCast(try asFloat(fps));
            if (item.object.get("loop")) |loop| clip.loop = try asBool(loop);
            clips[i] = clip;
        }
        out.clips = clips;
    }
    return out;
}

fn parseTilemap(allocator: std.mem.Allocator, v: std.json.Value) !types.TilemapIR {
    if (v != .object) return JsonError.InvalidType;
    const columns_val = v.object.get("columns") orelse return JsonError.MissingField;
    const rows_val = v.object.get("rows") orelse return JsonError.MissingField;
    const tiles_val = v.object.get("tiles") orelse return JsonError.MissingField;

    var out = types.TilemapIR{
        .columns = @intCast(try asInt(columns_val)),
        .rows = @intCast(try asInt(rows_val)),
        .tiles = try parseU8Array(allocator, tiles_val),
    };
    if (v.object.get("tileWidth")) |tw| out.tile_width = @floatCast(try asFloat(tw));
    if (v.object.get("tileHeight")) |th| out.tile_height = @floatCast(try asFloat(th));
    if (v.object.get("solidTiles")) |solid| out.solid_tiles = try parseU8Array(allocator, solid);
    if (v.object.get("palette")) |palette| out.palette = try parseColorArray(allocator, palette);
    return out;
}

fn parseParticleEmitter(v: std.json.Value) !types.ParticleEmitterIR {
    if (v != .object) return JsonError.InvalidType;
    var out: types.ParticleEmitterIR = .{};
    if (v.object.get("color")) |color| out.color = try parseColor(color) orelse return JsonError.InvalidValue;
    if (v.object.get("rate")) |rate| out.rate = @floatCast(try asFloat(rate));
    if (v.object.get("lifetime")) |life| out.lifetime = @floatCast(try asFloat(life));
    if (v.object.get("speed")) |speed| out.speed = @floatCast(try asFloat(speed));
    if (v.object.get("spread")) |spread| out.spread = @floatCast(try asFloat(spread));
    if (v.object.get("radius")) |radius| out.radius = @floatCast(try asFloat(radius));
    if (v.object.get("burst")) |burst| out.burst = @intCast(try asInt(burst));
    return out;
}

fn parseTween(v: std.json.Value) !types.TweenIR {
    if (v != .object) return JsonError.InvalidType;
    const to_val = v.object.get("to") orelse return JsonError.MissingField;
    var out = types.TweenIR{ .to = try parseVec2(to_val) };
    if (v.object.get("duration")) |duration| out.duration = @floatCast(try asFloat(duration));
    if (v.object.get("loop")) |loop| out.loop = try asBool(loop);
    return out;
}

fn parseTrigger(allocator: std.mem.Allocator, v: std.json.Value) !types.TriggerIR {
    if (v != .object) return JsonError.InvalidType;

    const bounds_val = v.object.get("bounds") orelse return JsonError.MissingField;
    const action_val = v.object.get("action");

    var one_shot = false;
    if (v.object.get("oneShot")) |o| one_shot = try asBool(o);

    return .{
        .bounds = try parseRect4(bounds_val),
        .one_shot = one_shot,
        .action = if (v.object.get("actions")) |actions| try parseActionSequence(allocator, actions) else try parseTriggerAction(allocator, action_val orelse return JsonError.MissingField),
    };
}

fn parseBoxCollider(v: std.json.Value) !types.BoxColliderIR {
    if (v != .object) return JsonError.InvalidType;
    const wv = v.object.get("width") orelse return JsonError.MissingField;
    const hv = v.object.get("height") orelse return JsonError.MissingField;
    var out = types.BoxColliderIR{ .width = @floatCast(try asFloat(wv)), .height = @floatCast(try asFloat(hv)) };
    if (v.object.get("offset")) |offset| out.offset = try parseVec2(offset);
    return out;
}

fn parseInteractable(allocator: std.mem.Allocator, v: std.json.Value) !types.InteractableIR {
    if (v != .object) return JsonError.InvalidType;
    const bounds_val = v.object.get("bounds") orelse return JsonError.MissingField;
    var prompt = try dupString(allocator, "Interact");
    if (v.object.get("prompt")) |p| prompt = try dupString(allocator, try asString(p));
    var repeatable = true;
    if (v.object.get("repeatable")) |r| repeatable = try asBool(r);
    const action = if (v.object.get("actions")) |actions| try parseActionSequence(allocator, actions) else try parseTriggerAction(allocator, v.object.get("action") orelse return JsonError.MissingField);
    return .{
        .bounds = try parseRect4(bounds_val),
        .prompt = prompt,
        .repeatable = repeatable,
        .action = action,
    };
}

fn parsePortal(allocator: std.mem.Allocator, v: std.json.Value) !types.PortalIR {
    if (v != .object) return JsonError.InvalidType;
    const bounds_val = v.object.get("bounds") orelse return JsonError.MissingField;
    const scene_val = v.object.get("scene") orelse return JsonError.MissingField;
    var spawn: ?[]const u8 = null;
    if (v.object.get("spawn")) |s| spawn = try dupString(allocator, try asString(s));
    return .{
        .bounds = try parseRect4(bounds_val),
        .scene = try dupString(allocator, try asString(scene_val)),
        .spawn = spawn,
    };
}

fn parseSpawnPoint(allocator: std.mem.Allocator, v: std.json.Value) !types.SpawnPointIR {
    if (v != .object) return JsonError.InvalidType;
    const name_val = v.object.get("name") orelse return JsonError.MissingField;
    return .{ .name = try dupString(allocator, try asString(name_val)) };
}

fn parseTriggerAction(allocator: std.mem.Allocator, v: std.json.Value) ParseError!types.TriggerActionIR {
    if (v != .object) return JsonError.InvalidType;

    if (v.object.get("actions")) |actions| {
        return try parseActionSequence(allocator, actions);
    }

    if (v.object.get("startDialogue")) |sd| {
        if (sd != .object) return JsonError.InvalidType;
        var id: ?[]const u8 = null;
        var label: ?[]const u8 = null;
        if (sd.object.get("id")) |l| id = try dupString(allocator, try asString(l));
        if (sd.object.get("label")) |l| label = try dupString(allocator, try asString(l));
        return .{ .StartDialogue = .{ .id = id, .label = label } };
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

    if (v.object.get("startCombat")) |sc| {
        if (sc != .object) return JsonError.InvalidType;
        const encounter_val = sc.object.get("encounter") orelse return JsonError.MissingField;
        return .{ .StartCombat = .{ .encounter = try dupString(allocator, try asString(encounter_val)) } };
    }

    if (v.object.get("playSound")) |ps| {
        if (ps != .object) return JsonError.InvalidType;
        const id_val = ps.object.get("id") orelse return JsonError.MissingField;
        var volume: f32 = 1;
        var loop = false;
        if (ps.object.get("volume")) |vv| volume = @floatCast(try asFloat(vv));
        if (ps.object.get("loop")) |vv| loop = try asBool(vv);
        return .{ .PlaySound = .{ .id = try dupString(allocator, try asString(id_val)), .volume = volume, .loop = loop } };
    }

    if (v.object.get("setEntityActive")) |sea| {
        if (sea != .object) return JsonError.InvalidType;
        const tag_val = sea.object.get("tag") orelse return JsonError.MissingField;
        var active = true;
        if (sea.object.get("active")) |vv| active = try asBool(vv);
        return .{ .SetEntityActive = .{ .tag = try dupString(allocator, try asString(tag_val)), .active = active } };
    }

    return JsonError.InvalidValue;
}

fn parseActionSequence(allocator: std.mem.Allocator, v: std.json.Value) ParseError!types.TriggerActionIR {
    if (v != .array) return JsonError.InvalidType;
    const out = try allocator.alloc(types.TriggerActionIR, v.array.items.len);
    for (v.array.items, 0..) |item, i| {
        out[i] = try parseTriggerAction(allocator, item);
    }
    return .{ .Sequence = out };
}

fn parseMovementMode(s: []const u8) !types.MovementModeIR {
    if (std.mem.eql(u8, s, "smooth4")) return .smooth4;
    if (std.mem.eql(u8, s, "smooth8")) return .smooth8;
    if (std.mem.eql(u8, s, "grid4")) return .grid4;
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

fn parseU8Array(allocator: std.mem.Allocator, v: std.json.Value) ![]const u8 {
    if (v != .array) return JsonError.InvalidType;
    const out = try allocator.alloc(u8, v.array.items.len);
    for (v.array.items, 0..) |item, i| {
        const n = try asInt(item);
        if (n < 0 or n > 255) return JsonError.InvalidValue;
        out[i] = @intCast(n);
    }
    return out;
}

fn parseColorArray(allocator: std.mem.Allocator, v: std.json.Value) ![]const rl.Color {
    if (v != .array) return JsonError.InvalidType;
    const out = try allocator.alloc(rl.Color, v.array.items.len);
    for (v.array.items, 0..) |item, i| {
        out[i] = try parseColor(item) orelse return JsonError.InvalidValue;
    }
    return out;
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

test "scene parser accepts render layer component" {
    const text =
        \\{
        \\  "name": "layered",
        \\  "entities": [
        \\    {
        \\      "tag": "player",
        \\      "components": {
        \\        "Transform": { "position": [0, 0] },
        \\        "Layer": { "order": 20, "ySort": true }
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    const ir = try parseSceneIR(std.testing.allocator, text);
    try std.testing.expectEqual(@as(usize, 1), ir.entities.len);
    var found_layer = false;
    for (ir.entities[0].components) |component| {
        switch (component) {
            .Layer => |layer| {
                found_layer = true;
                try std.testing.expectEqual(@as(i32, 20), layer.order);
                try std.testing.expect(layer.y_sort);
            },
            else => {},
        }
    }
    try std.testing.expect(found_layer);
}

test "scene parser accepts sound and entity-active actions" {
    const text =
        \\{
        \\  "name": "actions",
        \\  "entities": [
        \\    {
        \\      "tag": "collectible",
        \\      "components": {
        \\        "Interactable": {
        \\          "bounds": [0, 0, 32, 32],
        \\          "actions": [
        \\            { "playSound": { "id": "interact", "volume": 0.8 } },
        \\            { "setEntityActive": { "tag": "collectible", "active": false } }
        \\          ]
        \\        }
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    const ir = try parseSceneIR(std.testing.allocator, text);
    const action = ir.entities[0].components[0].Interactable.action;
    try std.testing.expect(std.meta.activeTag(action) == .Sequence);
    try std.testing.expect(std.meta.activeTag(action.Sequence[0]) == .PlaySound);
    try std.testing.expectEqualStrings("interact", action.Sequence[0].PlaySound.id);
    try std.testing.expect(std.meta.activeTag(action.Sequence[1]) == .SetEntityActive);
    try std.testing.expectEqualStrings("collectible", action.Sequence[1].SetEntityActive.tag);
    try std.testing.expect(!action.Sequence[1].SetEntityActive.active);
}
