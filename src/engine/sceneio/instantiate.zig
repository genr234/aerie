const std = @import("std");
const rl = @import("raylib");

const ecs = @import("../ecs.zig");
const events = @import("../events.zig");
const types = @import("types.zig");
const scenes = @import("../scenes.zig");

pub const InstantiateError = error{
    MissingTransform,
    UnknownTexture,
    UnresolvedTagReference,
};

/// Instantiate a `SceneIR` into an existing `Scene` world.
///
/// Notes:
/// - This does not change SceneManager state; it only populates the ECS world.
/// - Tag references (e.g. Camera.followTag) are resolved in a second pass.
pub fn instantiateSceneIR(allocator: std.mem.Allocator, scene: *scenes.Scene, ir: *const types.SceneIR, textures: *const TextureTable, dialogue: DialogueBindings) !void {
    _ = allocator;

    // First pass: spawn entities + add components that don't require cross-entity resolution.
    const entities = try scene.world.allocator.alloc(ecs.Entity, ir.entities.len);
    defer scene.world.allocator.free(entities);

    for (ir.entities, 0..) |eir, i| {
        const e = scene.spawn();
        entities[i] = e;

        if (eir.tag) |t| {
            try scene.world.tags.set(scene.world.allocator, e, ecs.TagComponent.init(t));
        }

        for (eir.components) |comp| {
            try applyComponentPass1(scene, e, comp, textures, dialogue);
        }
    }

    // Second pass: resolve tag references.
    for (ir.entities, 0..) |eir, i| {
        const e = entities[i];
        for (eir.components) |comp| {
            try applyComponentPass2(scene, e, comp);
        }
    }
}

pub const TextureTable = struct {
    entries: []const Entry,

    pub const Entry = struct {
        name: []const u8,
        texture: rl.Texture2D,
    };

    pub fn get(self: *const TextureTable, name: []const u8) ?rl.Texture2D {
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry.texture;
            if (std.mem.eql(u8, std.fs.path.basename(entry.name), name)) return entry.texture;
        }
        return null;
    }
};

pub const DialogueBindings = struct {
    game: *anyopaque,
    vn: *anyopaque,
};

fn applyComponentPass1(scene: *scenes.Scene, entity: ecs.Entity, comp: types.ComponentIR, textures: *const TextureTable, dialogue: DialogueBindings) !void {
    switch (comp) {
        .Transform => |t| {
            try scene.world.transforms.set(scene.world.allocator, entity, .{ .position = t.position, .rotation = t.rotation, .scale = t.scale });
        },
        .Sprite => |s| {
            const tex = textures.get(s.texture) orelse return InstantiateError.UnknownTexture;
            var sr = ecs.SpriteRenderer.init(tex);
            sr.flip_x = s.flip_x;
            if (s.tint) |tint| sr.tint = tint;
            sr.frame_width = s.frame_width;
            sr.frame_height = s.frame_height;
            sr.frames = s.frames;
            sr.fps = s.fps;
            sr.loop = s.loop;
            try scene.world.sprite_renderers.set(scene.world.allocator, entity, sr);
        },
        .Circle => |c| {
            try scene.world.circle_renderers.set(scene.world.allocator, entity, .{ .radius = c.radius, .color = c.color });
        },
        .Rect => |r| {
            try scene.world.rect_renderers.set(scene.world.allocator, entity, .{ .width = r.width, .height = r.height, .color = r.color });
        },
        .PlayerController => |pc| {
            try scene.world.player_controllers.set(scene.world.allocator, entity, .{ .speed = pc.speed, .paused = false });
        },
        .Solid => |solid| {
            try scene.world.solids.set(scene.world.allocator, entity, .{ .enabled = solid.enabled });
        },
        .Animation => |anim| {
            const clips = try scene.world.allocator.alloc(ecs.AnimationClip, anim.clips.len);
            for (anim.clips, 0..) |clip, i| {
                clips[i] = ecs.AnimationClip.init(clip.name, clip.start, clip.frames, clip.fps, clip.loop);
            }
            try scene.world.animation_states.set(scene.world.allocator, entity, .{ .clips = clips });
            if (anim.current) |name| {
                if (scene.world.tags.get(entity)) |tag| {
                    _ = ecs.Systems.setAnimation(&scene.world, tag.get(), name);
                }
            } else if (anim.clips.len > 0) {
                if (scene.world.sprite_renderers.get(entity)) |sr| {
                    sr.start_frame = anim.clips[0].start;
                    sr.current_frame = anim.clips[0].start;
                    sr.frames = anim.clips[0].frames;
                    sr.fps = anim.clips[0].fps;
                    sr.loop = anim.clips[0].loop;
                }
            }
        },
        .Tilemap => |tm| {
            try scene.world.tilemaps.set(scene.world.allocator, entity, .{
                .columns = tm.columns,
                .rows = tm.rows,
                .tile_width = tm.tile_width,
                .tile_height = tm.tile_height,
                .tiles = tm.tiles,
                .solid_tiles = tm.solid_tiles,
                .palette = tm.palette,
            });
        },
        .ParticleEmitter => |pe| {
            try scene.world.particle_emitters.set(scene.world.allocator, entity, .{
                .color = pe.color,
                .rate = pe.rate,
                .lifetime = pe.lifetime,
                .speed = pe.speed,
                .spread = pe.spread,
                .radius = pe.radius,
                .burst = pe.burst,
            });
        },
        .Tween => |tw| {
            try scene.world.tweens.set(scene.world.allocator, entity, .{ .to = tw.to, .duration = tw.duration, .loop = tw.loop });
        },
        .Camera => |c| {
            // follow_target resolved in pass2.
            try scene.world.cameras.set(scene.world.allocator, entity, .{ .offset = c.offset, .target = .{ .x = 0, .y = 0 }, .rotation = c.rotation, .zoom = c.zoom, .follow_target = ecs.Entity.INVALID });
        },
        .Trigger => |t| {
            // TriggerCheck reads Trigger.bounds directly. We keep action event-driven.
            const action = try lowerTriggerAction(t.action, dialogue);
            try scene.world.triggers.set(scene.world.allocator, entity, .{
                .bounds = t.bounds,
                .action = action,
                .was_inside = false,
                .one_shot = t.one_shot,
                .triggered = false,
            });
        },
    }

    // Collider defaults: if it's renderable but has no collider yet, try to set one.
    // (Current triggerCheck uses either box collider or sprite size; so this is optional.)
}

fn applyComponentPass2(scene: *scenes.Scene, entity: ecs.Entity, comp: types.ComponentIR) !void {
    switch (comp) {
        .Camera => |c| {
            if (c.follow_tag) |tag| {
                const target = scene.world.findByTag(tag) orelse return InstantiateError.UnresolvedTagReference;
                const cam = scene.world.cameras.get(entity) orelse return InstantiateError.MissingTransform;
                cam.follow_target = target;
            }
        },
        .Animation => |anim| {
            if (anim.current) |name| {
                if (scene.world.tags.get(entity)) |tag| {
                    _ = ecs.Systems.setAnimation(&scene.world, tag.get(), name);
                }
            }
        },
        else => {},
    }
}

fn lowerTriggerAction(action: types.TriggerActionIR, dialogue: DialogueBindings) !ecs.TriggerAction {
    return switch (action) {
        .ShowMessage => |sm| ecs.TriggerShowMessage(sm.text, sm.duration),
        .StartDialogue => |sd| blk: {
            const runner_ptr: *anyopaque = dialogue.game;
            break :blk ecs.TriggerDialogueStart(@ptrCast(@alignCast(runner_ptr)), null, sd.id, sd.label);
        },
        .ChangeScene => |cs| blk: {
            if (cs.index) |idx| break :blk .{ .change_scene = .{ .index = idx, .use_index = true } };
            if (cs.name) |name| {
                var out: ecs.TriggerAction = .{ .change_scene = .{ .index = 0, .name = [_]u8{0} ** events.MAX_ID_LEN, .name_len = 0, .use_index = false } };
                const len = @min(name.len, events.MAX_ID_LEN - 1);
                @memcpy(out.change_scene.name[0..len], name[0..len]);
                out.change_scene.name[len] = 0;
                out.change_scene.name_len = len;
                break :blk out;
            }
            break :blk ecs.TriggerShowMessage("ChangeScene missing name", 2.0);
        },
        .SetFlag => |sf| blk: {
            var out: ecs.TriggerAction = .{ .set_flag = .{ .name = [_]u8{0} ** events.MAX_ID_LEN, .name_len = 0, .value = sf.value } };
            const len = @min(sf.name.len, events.MAX_ID_LEN - 1);
            @memcpy(out.set_flag.name[0..len], sf.name[0..len]);
            out.set_flag.name[len] = 0;
            out.set_flag.name_len = len;
            break :blk out;
        },
    };
}
