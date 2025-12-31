const std = @import("std");
const rl = @import("raylib");
const dialogue = @import("dialogue.zig");
const sprites = @import("sprites.zig");

pub const Entity = struct {
    id: u32,
    generation: u16,

    pub const INVALID = Entity{ .id = std.math.maxInt(u32), .generation = 0 };

    pub fn isValid(self: Entity) bool {
        return self.id != std.math.maxInt(u32);
    }

    pub fn eql(self: Entity, other: Entity) bool {
        return self.id == other.id and self.generation == other.generation;
    }
};

pub const TagComponent = struct {
    name: [64]u8 = [_]u8{0} ** 64,
    len: usize = 0,

    pub fn init(name: []const u8) TagComponent {
        var tag = TagComponent{};
        const copy_len = @min(name.len, 64);
        @memcpy(tag.name[0..copy_len], name[0..copy_len]);
        tag.len = copy_len;
        return tag;
    }

    pub fn get(self: *const TagComponent) []const u8 {
        return self.name[0..self.len];
    }
};

pub const Transform = struct {
    position: rl.Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
    scale: rl.Vector2 = .{ .x = 1, .y = 1 },
};

pub const SpriteRenderer = struct {
    texture: rl.Texture2D,
    flip_x: bool = false,
    tint: rl.Color = rl.Color.white,

    pub fn init(texture: rl.Texture2D) SpriteRenderer {
        return .{ .texture = texture };
    }
};

pub const CircleRenderer = struct {
    radius: f32,
    color: rl.Color,
};

pub const RectRenderer = struct {
    width: f32,
    height: f32,
    color: rl.Color,
};

pub const PlayerController = struct {
    speed: f32 = 100,
    paused: bool = false,
};

pub const Camera = struct {
    offset: rl.Vector2 = .{ .x = 0, .y = 0 },
    target: rl.Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
    zoom: f32 = 1.0,
    follow_target: Entity = Entity.INVALID,

    pub fn toRaylib(self: *const Camera) rl.Camera2D {
        return .{
            .offset = self.offset,
            .target = self.target,
            .rotation = self.rotation,
            .zoom = self.zoom,
        };
    }
};

pub const TriggerAction = union(enum) {
    print_message: [128]u8,
    start_dialogue: struct {
        runner: *dialogue.Runner,
        context: ?*anyopaque,
    },
    run_action: dialogue.ActionFn,
};

pub fn TriggerPrintAction(msg: []const u8) TriggerAction {
    var action = TriggerAction{ .print_message = [_]u8{0} ** 128 };
    const copy_len: usize = @min(msg.len, action.print_message.len - 1);
    @memcpy(action.print_message[0..copy_len], msg[0..copy_len]);
    action.print_message[copy_len] = 0;
    return action;
}

pub const Trigger = struct {
    bounds: rl.Rectangle,
    action: TriggerAction,
    was_inside: bool = false,
    one_shot: bool = false,
    triggered: bool = false,

    pub fn reset(self: *Trigger) void {
        self.was_inside = false;
        self.triggered = false;
    }
};

pub const BoxCollider = struct {
    width: f32,
    height: f32,
    offset: rl.Vector2 = .{ .x = 0, .y = 0 },

    pub fn getRect(self: *const BoxCollider, transform: *const Transform) rl.Rectangle {
        return .{
            .x = transform.position.x + self.offset.x,
            .y = transform.position.y + self.offset.y,
            .width = self.width * @abs(transform.scale.x),
            .height = self.height * @abs(transform.scale.y),
        };
    }
};

pub const Active = struct {
    value: bool = true,
};

pub fn ComponentStorage(comptime T: type, comptime CAPACITY: usize) type {
    return struct {
        const Self = @This();

        sparse: [CAPACITY]?u32 = [_]?u32{null} ** CAPACITY,
        generations: [CAPACITY]u16 = [_]u16{0} ** CAPACITY,  // Track generation per slot
        dense_entities: [CAPACITY]u32 = undefined,
        dense_data: [CAPACITY]T = undefined,
        count: u32 = 0,

        pub fn init() Self {
            return .{};
        }

        pub fn set(self: *Self, entity: Entity, component: T) void {
            if (entity.id >= CAPACITY) return;

            if (self.sparse[entity.id]) |dense_idx| {
                if (self.generations[entity.id] <= entity.generation) {
                    self.dense_data[dense_idx] = component;
                    self.generations[entity.id] = entity.generation;
                }
            } else {
                const idx = self.count;
                self.sparse[entity.id] = idx;
                self.generations[entity.id] = entity.generation;
                self.dense_entities[idx] = entity.id;
                self.dense_data[idx] = component;
                self.count += 1;
            }
        }

        pub fn get(self: *Self, entity: Entity) ?*T {
            if (entity.id >= CAPACITY) return null;
            if (self.generations[entity.id] != entity.generation) return null;
            if (self.sparse[entity.id]) |dense_idx| {
                return &self.dense_data[dense_idx];
            }
            return null;
        }

        pub fn getConst(self: *const Self, entity: Entity) ?*const T {
            if (entity.id >= CAPACITY) return null;
            if (self.generations[entity.id] != entity.generation) return null;
            if (self.sparse[entity.id]) |dense_idx| {
                return &self.dense_data[dense_idx];
            }
            return null;
        }

        pub fn has(self: *const Self, entity: Entity) bool {
            if (entity.id >= MAX_ENTITIES) return false;
            return self.sparse[entity.id] != null;
        }

        pub fn remove(self: *Self, entity: Entity) void {
            if (entity.id >= MAX_ENTITIES) return;
            if (self.sparse[entity.id]) |dense_idx| {
                const last_idx = self.count - 1;
                if (dense_idx != last_idx) {
                    const last_entity = self.dense_entities[last_idx];
                    self.dense_entities[dense_idx] = last_entity;
                    self.dense_data[dense_idx] = self.dense_data[last_idx];
                    self.sparse[last_entity] = dense_idx;
                }
                self.sparse[entity.id] = null;
                self.count -= 1;
            }
        }

        pub fn clear(self: *Self) void {
            for (0..self.count) |i| {
                self.sparse[self.dense_entities[i]] = null;
            }
            self.count = 0;
        }

        pub fn iterator(self: *Self) Iterator {
            return .{ .storage = self, .index = 0 };
        }

        pub const Iterator = struct {
            storage: *Self,
            index: u32,

            pub fn next(self: *Iterator) ?struct { entity_id: u32, data: *T } {
                if (self.index >= self.storage.count) return null;
                const entity_id = self.storage.dense_entities[self.index];
                const data = &self.storage.dense_data[self.index];
                self.index += 1;
                return .{
                    .entity_id = entity_id,
                    .data = data,
                };
            }
        };
    };
}

pub const MAX_ENTITIES: usize = 256;

pub const World = struct {
    const Self = @This();

    entity_generations: [MAX_ENTITIES]u16 = [_]u16{0} ** MAX_ENTITIES,
    entity_alive: [MAX_ENTITIES]bool = [_]bool{false} ** MAX_ENTITIES,
    next_entity_id: u32 = 0,
    free_list: [MAX_ENTITIES]u32 = undefined,
    free_count: u32 = 0,
    entity_count: u32 = 0,

    tags: ComponentStorage(TagComponent, MAX_ENTITIES) = .{},
    transforms: ComponentStorage(Transform, MAX_ENTITIES) = .{},
    sprite_renderers: ComponentStorage(SpriteRenderer, MAX_ENTITIES) = .{},
    circle_renderers: ComponentStorage(CircleRenderer, MAX_ENTITIES) = .{},
    rect_renderers: ComponentStorage(RectRenderer, MAX_ENTITIES) = .{},
    player_controllers: ComponentStorage(PlayerController, MAX_ENTITIES) = .{},
    cameras: ComponentStorage(Camera, MAX_ENTITIES) = .{},
    triggers: ComponentStorage(Trigger, MAX_ENTITIES) = .{},
    box_colliders: ComponentStorage(BoxCollider, MAX_ENTITIES) = .{},
    actives: ComponentStorage(Active, MAX_ENTITIES) = .{},

    bounds_width: f32 = 800,
    bounds_height: f32 = 450,

    message: ?[:0]const u8 = null,
    message_timer: f32 = 0,

    pub fn init() Self {
        return .{};
    }

    pub fn entityFromId(self: *const Self, entity_id: u32) Entity {
        if (entity_id >= MAX_ENTITIES) return Entity.INVALID;
        return .{ .id = entity_id, .generation = self.entity_generations[entity_id] };
    }

    pub fn spawn(self: *Self) Entity {
        var entity_id: u32 = undefined;

        if (self.free_count > 0) {
            self.free_count -= 1;
            entity_id = self.free_list[self.free_count];
        } else {
            if (self.next_entity_id >= MAX_ENTITIES) {
                return Entity.INVALID;
            }
            entity_id = self.next_entity_id;
            self.next_entity_id += 1;
        }

        self.entity_alive[entity_id] = true;
        self.entity_count += 1;

        const entity = Entity{ .id = entity_id, .generation = self.entity_generations[entity_id] };
        self.actives.set(entity, .{ .value = true });

        return entity;
    }

    pub fn despawn(self: *Self, entity: Entity) void {
        if (!self.isAlive(entity)) return;

        self.tags.remove(entity);
        self.transforms.remove(entity);
        self.sprite_renderers.remove(entity);
        self.circle_renderers.remove(entity);
        self.rect_renderers.remove(entity);
        self.player_controllers.remove(entity);
        self.cameras.remove(entity);
        self.triggers.remove(entity);
        self.box_colliders.remove(entity);
        self.actives.remove(entity);
        // Mark as dead and increment generation
        self.entity_alive[entity.id] = false;
        self.entity_generations[entity.id] += 1;
        self.free_list[self.free_count] = entity.id;
        self.free_count += 1;
        self.entity_count -= 1;
    }

    pub fn isAlive(self: *const Self, entity: Entity) bool {
        if (entity.id >= MAX_ENTITIES) return false;
        return self.entity_alive[entity.id] and
            self.entity_generations[entity.id] == entity.generation;
    }

    pub fn isActive(self: *Self, entity: Entity) bool {
        if (!self.isAlive(entity)) return false;
        if (self.actives.get(entity)) |active| {
            return active.value;
        }
        return true;
    }

    pub fn setActive(self: *Self, entity: Entity, active: bool) void {
        if (self.actives.get(entity)) |a| {
            a.value = active;
        }
    }

    pub fn findByTag(self: *Self, name: []const u8) ?Entity {
        var it = self.tags.iterator();
        while (it.next()) |item| {
            if (std.mem.eql(u8, item.data.get(), name)) {
                const entity = self.entityFromId(item.entity_id);
                if (self.isAlive(entity)) {
                    return entity;
                }
            }
        }
        return null;
    }

    pub fn clear(self: *Self) void {
        self.tags.clear();
        self.transforms.clear();
        self.sprite_renderers.clear();
        self.circle_renderers.clear();
        self.rect_renderers.clear();
        self.player_controllers.clear();
        self.cameras.clear();
        self.triggers.clear();
        self.box_colliders.clear();
        self.actives.clear();

        for (0..MAX_ENTITIES) |i| {
            if (self.entity_alive[i]) {
                self.entity_generations[i] += 1;
            }
            self.entity_alive[i] = false;
        }
        self.next_entity_id = 0;
        self.free_count = 0;
        self.entity_count = 0;
    }
};

pub const Systems = struct {
    pub fn playerMovement(world: *World, dt: f32) void {
        var it = world.player_controllers.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            if (item.data.paused) continue;

            const transform = world.transforms.get(entity) orelse continue;
            const speed = item.data.speed;

            const right_down = rl.isKeyDown(.right);
            const left_down = rl.isKeyDown(.left);

            if (right_down) {
                transform.position.x += speed * dt;
                transform.scale.x = -1.0;
            } else if (left_down) {
                transform.position.x -= speed * dt;
                transform.scale.x = 1.0;
            } else {
                // Reset facing direction when not moving horizontally
                transform.scale.x = 1.0;
            }

            if (rl.isKeyDown(.up)) {
                transform.position.y -= speed * dt;
            }
            if (rl.isKeyDown(.down)) {
                transform.position.y += speed * dt;
            }

            var sprite_w: f32 = 32;
            var sprite_h: f32 = 32;
            if (world.sprite_renderers.get(entity)) |sr| {
                sprite_w = @floatFromInt(sr.texture.width);
                sprite_h = @floatFromInt(sr.texture.height);
            } else if (world.box_colliders.get(entity)) |col| {
                sprite_w = col.width;
                sprite_h = col.height;
            }

            if (transform.position.x < 0) transform.position.x = 0;
            if (transform.position.y < 0) transform.position.y = 0;
            if (transform.position.x + sprite_w > world.bounds_width) {
                transform.position.x = world.bounds_width - sprite_w;
            }
            if (transform.position.y + sprite_h > world.bounds_height) {
                transform.position.y = world.bounds_height - sprite_h;
            }
        }
    }

    pub fn cameraFollow(world: *World) void {
        var it = world.cameras.iterator();
        while (it.next()) |item| {
            const cam_entity = world.entityFromId(item.entity_id);
            if (!world.isActive(cam_entity)) continue;

            const cam = item.data;
            if (!cam.follow_target.isValid()) continue;
            if (!world.isAlive(cam.follow_target)) continue;

            if (world.transforms.get(cam.follow_target)) |target_transform| {
                var target_x = target_transform.position.x;
                var target_y = target_transform.position.y;

                // Center offset; if rotation is present, apply a simple rotated offset.
                if (world.sprite_renderers.get(cam.follow_target)) |sr| {
                    const w: f32 = @floatFromInt(sr.texture.width);
                    const h: f32 = @floatFromInt(sr.texture.height);
                    const angle = target_transform.rotation;
                    const half_w = w / 2;
                    const half_h = h / 2;
                    target_x += half_w * @cos(angle);
                    target_y += half_h * @sin(angle);
                } else if (world.box_colliders.get(cam.follow_target)) |col| {
                    target_x += col.width / 2;
                    target_y += col.height / 2;
                }

                cam.target = .{ .x = target_x, .y = target_y };
            }
        }
    }

    /// Check trigger collisions
    pub fn triggerCheck(world: *World) void {
        // Find player collider
        var player_entity: Entity = Entity.INVALID;
        var player_rect: rl.Rectangle = undefined;
        var have_player_rect = false;

        var player_it = world.player_controllers.iterator();
        while (player_it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            player_entity = entity;

            if (world.transforms.get(entity)) |tr| {
                if (world.box_colliders.get(entity)) |col| {
                    player_rect = col.getRect(tr);
                    have_player_rect = true;
                } else if (world.sprite_renderers.get(entity)) |sr| {
                    const abs_scale = @abs(tr.scale.x);
                    player_rect = .{
                        .x = tr.position.x,
                        .y = tr.position.y,
                        .width = @as(f32, @floatFromInt(sr.texture.width)) * abs_scale,
                        .height = @as(f32, @floatFromInt(sr.texture.height)) * abs_scale,
                    };
                    have_player_rect = true;
                }
            }
            break;
        }

        if (!player_entity.isValid() or !have_player_rect) return;

        var it = world.triggers.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;

            const trigger = item.data;
            if (trigger.one_shot and trigger.triggered) continue;

            const inside = rl.checkCollisionRecs(player_rect, trigger.bounds);

            if (inside and !trigger.was_inside) {
                // Just entered trigger
                switch (trigger.action) {
                    .print_message => |buf| {
                        const len = std.mem.indexOfScalar(u8, &buf, 0) orelse buf.len;
                        world.message = buf[0..len :0];
                        world.message_timer = 2.0;
                    },
                    .start_dialogue => |payload| {
                        payload.runner.start(payload.context);
                    },
                    .run_action => |action| {
                        action(null);
                    },
                }
                if (trigger.one_shot) trigger.triggered = true;
            }

            trigger.was_inside = inside;
        }
    }

    pub fn render(world: *World) void {
        {
            var it = world.circle_renderers.iterator();
            while (it.next()) |item| {
                const entity = world.entityFromId(item.entity_id);
                if (!world.isActive(entity)) continue;
                const tr = world.transforms.getConst(entity) orelse continue;
                rl.drawCircle(
                    @intFromFloat(tr.position.x),
                    @intFromFloat(tr.position.y),
                    item.data.radius,
                    item.data.color,
                );
            }
        }

        {
            var it = world.rect_renderers.iterator();
            while (it.next()) |item| {
                const entity = world.entityFromId(item.entity_id);
                if (!world.isActive(entity)) continue;
                const tr = world.transforms.getConst(entity) orelse continue;
                rl.drawRectangle(
                    @intFromFloat(tr.position.x),
                    @intFromFloat(tr.position.y),
                    @intFromFloat(item.data.width),
                    @intFromFloat(item.data.height),
                    item.data.color,
                );
            }
        }

        {
            var it = world.sprite_renderers.iterator();
            while (it.next()) |item| {
                const entity = world.entityFromId(item.entity_id);
                if (!world.isActive(entity)) continue;
                const tr = world.transforms.getConst(entity) orelse continue;
                const sr = item.data;

                const sprite_w: f32 = @floatFromInt(sr.texture.width);
                const sprite_h: f32 = @floatFromInt(sr.texture.height);

                const flip = sr.flip_x or tr.scale.x < 0;
                const src = rl.Rectangle{
                    .x = if (flip) sprite_w else 0,
                    .y = 0,
                    .width = if (flip) -sprite_w else sprite_w,
                    .height = sprite_h,
                };

                const abs_scale = @abs(tr.scale.x);
                const dest = rl.Rectangle{
                    .x = tr.position.x,
                    .y = tr.position.y,
                    .width = sprite_w * abs_scale,
                    .height = sprite_h * abs_scale,
                };

                rl.drawTexturePro(sr.texture, src, dest, .{ .x = 0, .y = 0 }, tr.rotation, sr.tint);
            }
        }
    }

    pub fn getActiveCamera(world: *World) !rl.Camera2D {
        var it = world.cameras.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            return item.data.toRaylib();
        }
        return error.NoActiveCamera;
    }

    pub fn getPlayerRect(world: *World) ?rl.Rectangle {
        var it = world.player_controllers.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;

            if (world.transforms.get(entity)) |tr| {
                if (world.sprite_renderers.get(entity)) |sr| {
                    const abs_scale = @abs(tr.scale.x);
                    return .{
                        .x = tr.position.x,
                        .y = tr.position.y,
                        .width = @as(f32, @floatFromInt(sr.texture.width)) * abs_scale,
                        .height = @as(f32, @floatFromInt(sr.texture.height)) * abs_scale,
                    };
                } else if (world.box_colliders.get(entity)) |col| {
                    return col.getRect(tr);
                }
            }
        }
        return null;
    }

    pub fn setCameraZoom(world: *World, zoom: f32) void {
        var it = world.cameras.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            item.data.zoom = zoom;
            break;
        }
    }

    pub fn setCameraTarget(world: *World, target: rl.Vector2) void {
        var it = world.cameras.iterator();
        while (it.next()) |item| {
            const entity = world.entityFromId(item.entity_id);
            if (!world.isActive(entity)) continue;
            item.data.target = target;
            break;
        }
    }

    pub fn setPlayerPaused(world: *World, paused: bool) void {
        var it = world.player_controllers.iterator();
        while (it.next()) |item| {
            item.data.paused = paused;
        }
    }

    pub fn resetTriggers(world: *World) void {
        var it = world.triggers.iterator();
        while (it.next()) |item| {
            item.data.reset();
        }
    }
};

pub const EntityBuilder = struct {
    world: *World,
    entity: Entity,

    pub fn init(world: *World) EntityBuilder {
        return .{
            .world = world,
            .entity = world.spawn(),
        };
    }

    pub fn withTag(self: *EntityBuilder, name: []const u8) *EntityBuilder {
        self.world.tags.set(self.entity, TagComponent.init(name));
        return self;
    }

    pub fn withTransform(self: *EntityBuilder, pos: rl.Vector2) *EntityBuilder {
        self.world.transforms.set(self.entity, .{ .position = pos });
        return self;
    }

    pub fn withTransformFull(self: *EntityBuilder, transform: Transform) *EntityBuilder {
        self.world.transforms.set(self.entity, transform);
        return self;
    }

    pub fn withSprite(self: *EntityBuilder, texture: rl.Texture) *EntityBuilder {
        self.world.sprite_renderers.set(self.entity, SpriteRenderer.init(texture));
        return self;
    }

    pub fn withCircle(self: *EntityBuilder, radius: f32, color: rl.Color) *EntityBuilder {
        self.world.circle_renderers.set(self.entity, .{ .radius = radius, .color = color });
        return self;
    }

    pub fn withRect(self: *EntityBuilder, width: f32, height: f32, color: rl.Color) *EntityBuilder {
        self.world.rect_renderers.set(self.entity, .{ .width = width, .height = height, .color = color });
        return self;
    }

    pub fn withPlayerController(self: *EntityBuilder, speed: f32) *EntityBuilder {
        self.world.player_controllers.set(self.entity, .{ .speed = speed });
        return self;
    }

    pub fn withCamera(self: *EntityBuilder, offset: rl.Vector2, follow: Entity) *EntityBuilder {
        self.world.cameras.set(self.entity, .{
            .offset = offset,
            .follow_target = follow,
        });
        return self;
    }

    pub fn withCameraFull(self: *EntityBuilder, cam: Camera) *EntityBuilder {
        self.world.cameras.set(self.entity, cam);
        return self;
    }

    pub fn withTrigger(self: *EntityBuilder, bounds: rl.Rectangle, action: TriggerAction, one_shot: bool) *EntityBuilder {
        self.world.triggers.set(self.entity, .{
            .bounds = bounds,
            .action = action,
            .one_shot = one_shot,
        });
        return self;
    }

    pub fn withBoxCollider(self: *EntityBuilder, width: f32, height: f32) *EntityBuilder {
        self.world.box_colliders.set(self.entity, .{ .width = width, .height = height });
        return self;
    }

    pub fn build(self: *EntityBuilder) Entity {
        return self.entity;
    }
};

