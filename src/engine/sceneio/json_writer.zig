const std = @import("std");
const rl = @import("raylib");

const types = @import("types.zig");
const scene_json = @import("json.zig");

pub fn writeSceneIR(writer: *std.Io.Writer, ir: types.SceneIR) !void {
    var stream: std.json.Stringify = .{
        .writer = writer,
        .options = .{ .whitespace = .indent_2 },
    };

    try stream.beginObject();

    try stream.objectField("name");
    try stream.write(ir.name);

    try stream.objectField("type");
    try stream.write(sceneTypeString(ir.scene_type));

    try stream.objectField("size");
    try stream.beginObject();
    try stream.objectField("width");
    try stream.write(ir.width);
    try stream.objectField("height");
    try stream.write(ir.height);
    try stream.endObject();

    try stream.objectField("entities");
    try stream.beginArray();
    for (ir.entities) |entity| {
        try writeEntity(&stream, entity);
    }
    try stream.endArray();

    try stream.endObject();
}

pub fn allocSceneIRJson(allocator: std.mem.Allocator, ir: types.SceneIR) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    try writeSceneIR(&out.writer, ir);
    return out.toOwnedSlice();
}

fn writeEntity(stream: *std.json.Stringify, entity: types.EntityIR) !void {
    try stream.beginObject();

    if (entity.tag) |tag| {
        try stream.objectField("tag");
        try stream.write(tag);
    }

    try stream.objectField("components");
    try stream.beginObject();
    for (entity.components) |component| {
        try writeComponent(stream, component);
    }
    try stream.endObject();

    try stream.endObject();
}

fn writeComponent(stream: *std.json.Stringify, component: types.ComponentIR) !void {
    switch (component) {
        .Transform => |value| {
            try stream.objectField("Transform");
            try stream.beginObject();
            try stream.objectField("position");
            try writeVec2(stream, value.position);
            try stream.objectField("rotation");
            try stream.write(value.rotation);
            try stream.objectField("scale");
            try writeVec2(stream, value.scale);
            try stream.endObject();
        },
        .Sprite => |value| {
            try stream.objectField("Sprite");
            try stream.beginObject();
            try stream.objectField("texture");
            try stream.write(value.texture);
            try stream.objectField("flipX");
            try stream.write(value.flip_x);
            if (value.tint) |tint| {
                try stream.objectField("tint");
                try writeColor(stream, tint);
            }
            try stream.endObject();
        },
        .Circle => |value| {
            try stream.objectField("Circle");
            try stream.beginObject();
            try stream.objectField("radius");
            try stream.write(value.radius);
            try stream.objectField("color");
            try writeColor(stream, value.color);
            try stream.endObject();
        },
        .Rect => |value| {
            try stream.objectField("Rect");
            try stream.beginObject();
            try stream.objectField("width");
            try stream.write(value.width);
            try stream.objectField("height");
            try stream.write(value.height);
            try stream.objectField("color");
            try writeColor(stream, value.color);
            try stream.endObject();
        },
        .Camera => |value| {
            try stream.objectField("Camera");
            try stream.beginObject();
            try stream.objectField("offset");
            try writeVec2(stream, value.offset);
            try stream.objectField("rotation");
            try stream.write(value.rotation);
            try stream.objectField("zoom");
            try stream.write(value.zoom);
            if (value.follow_tag) |tag| {
                try stream.objectField("followTag");
                try stream.write(tag);
            }
            try stream.endObject();
        },
        .PlayerController => |value| {
            try stream.objectField("PlayerController");
            try stream.beginObject();
            try stream.objectField("speed");
            try stream.write(value.speed);
            try stream.endObject();
        },
        .Trigger => |value| {
            try stream.objectField("Trigger");
            try stream.beginObject();
            try stream.objectField("bounds");
            try writeRect4(stream, value.bounds);
            try stream.objectField("oneShot");
            try stream.write(value.one_shot);
            try stream.objectField("action");
            try writeTriggerAction(stream, value.action);
            try stream.endObject();
        },
    }
}

fn writeTriggerAction(stream: *std.json.Stringify, action: types.TriggerActionIR) !void {
    try stream.beginObject();
    switch (action) {
        .StartDialogue => |value| {
            try stream.objectField("startDialogue");
            try stream.beginObject();
            if (value.label) |label| {
                try stream.objectField("label");
                try stream.write(label);
            }
            try stream.endObject();
        },
        .ShowMessage => |value| {
            try stream.objectField("showMessage");
            try stream.beginObject();
            try stream.objectField("text");
            try stream.write(value.text);
            try stream.objectField("duration");
            try stream.write(value.duration);
            try stream.endObject();
        },
        .ChangeScene => |value| {
            try stream.objectField("changeScene");
            try stream.beginObject();
            if (value.index) |index| {
                try stream.objectField("index");
                try stream.write(index);
            }
            if (value.name) |name| {
                try stream.objectField("name");
                try stream.write(name);
            }
            try stream.endObject();
        },
        .SetFlag => |value| {
            try stream.objectField("setFlag");
            try stream.beginObject();
            try stream.objectField("name");
            try stream.write(value.name);
            try stream.objectField("value");
            try stream.write(value.value);
            try stream.endObject();
        },
    }
    try stream.endObject();
}

fn writeVec2(stream: *std.json.Stringify, value: rl.Vector2) !void {
    try stream.beginArray();
    try stream.write(value.x);
    try stream.write(value.y);
    try stream.endArray();
}

fn writeRect4(stream: *std.json.Stringify, value: rl.Rectangle) !void {
    try stream.beginArray();
    try stream.write(value.x);
    try stream.write(value.y);
    try stream.write(value.width);
    try stream.write(value.height);
    try stream.endArray();
}

fn writeColor(stream: *std.json.Stringify, color: rl.Color) !void {
    var buf: [10]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "#{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{ color.r, color.g, color.b, color.a }) catch unreachable;
    try stream.write(text);
}

fn sceneTypeString(scene_type: types.SceneType) []const u8 {
    return switch (scene_type) {
        .exploration => "exploration",
        .visual_novel => "visual_novel",
    };
}

test "scene JSON writer round trips reference crossroads scene" {
    const text = @embedFile("../../../assets/reference-game/crossroads.json");
    const original = try scene_json.parseSceneIR(std.testing.allocator, text);

    const encoded = try allocSceneIRJson(std.testing.allocator, original);
    defer std.testing.allocator.free(encoded);

    const round_trip = try scene_json.parseSceneIR(std.testing.allocator, encoded);
    try std.testing.expectEqualStrings(original.name, round_trip.name);
    try std.testing.expectEqual(original.scene_type, round_trip.scene_type);
    try std.testing.expectEqual(original.width, round_trip.width);
    try std.testing.expectEqual(original.height, round_trip.height);
    try std.testing.expectEqual(original.entities.len, round_trip.entities.len);
    try std.testing.expectEqualStrings(original.entities[0].tag.?, round_trip.entities[0].tag.?);
    try std.testing.expect(std.meta.activeTag(round_trip.entities[0].components[1]) == .Sprite);
    try std.testing.expectEqualStrings("reference-game/player.png", round_trip.entities[0].components[1].Sprite.texture);
}

test "scene JSON writer round trips reference clearing scene" {
    const text = @embedFile("../../../assets/reference-game/clearing.json");
    const original = try scene_json.parseSceneIR(std.testing.allocator, text);

    const encoded = try allocSceneIRJson(std.testing.allocator, original);
    defer std.testing.allocator.free(encoded);

    const round_trip = try scene_json.parseSceneIR(std.testing.allocator, encoded);
    try std.testing.expectEqualStrings(original.name, round_trip.name);
    try std.testing.expectEqual(original.entities.len, round_trip.entities.len);
    try std.testing.expectEqualStrings("clearing", round_trip.name);
}

test "scene JSON writer emits all trigger action shapes" {
    const actions = [_]types.TriggerActionIR{
        .{ .StartDialogue = .{ .label = "intro" } },
        .{ .ShowMessage = .{ .text = "hello", .duration = 1.5 } },
        .{ .ChangeScene = .{ .name = "clearing" } },
    };
    const components = [_]types.ComponentIR{
        .{ .Trigger = .{ .bounds = .{ .x = 1, .y = 2, .width = 3, .height = 4 }, .action = actions[0] } },
        .{ .Trigger = .{ .bounds = .{ .x = 5, .y = 6, .width = 7, .height = 8 }, .action = actions[1] } },
        .{ .Trigger = .{ .bounds = .{ .x = 9, .y = 10, .width = 11, .height = 12 }, .action = actions[2] } },
    };
    const entities = [_]types.EntityIR{
        .{ .tag = "actions", .components = @constCast(&components) },
    };
    const ir = types.SceneIR{
        .name = "actions",
        .entities = @constCast(&entities),
    };

    const encoded = try allocSceneIRJson(std.testing.allocator, ir);
    defer std.testing.allocator.free(encoded);

    const round_trip = try scene_json.parseSceneIR(std.testing.allocator, encoded);
    try std.testing.expect(std.meta.activeTag(round_trip.entities[0].components[0].Trigger.action) == .StartDialogue);
    try std.testing.expect(std.meta.activeTag(round_trip.entities[0].components[1].Trigger.action) == .ShowMessage);
    try std.testing.expect(std.meta.activeTag(round_trip.entities[0].components[2].Trigger.action) == .ChangeScene);
    try std.testing.expectEqualStrings("clearing", round_trip.entities[0].components[2].Trigger.action.ChangeScene.name.?);
}
