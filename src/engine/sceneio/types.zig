const std = @import("std");
const rl = @import("raylib");

pub const SceneType = enum {
    exploration,
    visual_novel,
};

pub const SceneIR = struct {
    name: []const u8,
    scene_type: SceneType = .exploration,
    width: i32 = 800,
    height: i32 = 450,
    background_color: ?rl.Color = null,
    entities: []EntityIR,
};

pub const EntityIR = struct {
    tag: ?[]const u8 = null,
    components: []ComponentIR,
};

pub const ComponentIR = union(enum) {
    Transform: TransformIR,
    Sprite: SpriteIR,
    Circle: CircleIR,
    Rect: RectIR,
    Camera: CameraIR,
    PlayerController: PlayerControllerIR,
    Solid: SolidIR,
    Animation: AnimationIR,
    Tilemap: TilemapIR,
    ParticleEmitter: ParticleEmitterIR,
    Tween: TweenIR,
    Trigger: TriggerIR,
};

pub const TransformIR = struct {
    position: rl.Vector2 = .{ .x = 0, .y = 0 },
    rotation: f32 = 0,
    scale: rl.Vector2 = .{ .x = 1, .y = 1 },
};

pub const SpriteIR = struct {
    texture: []const u8,
    flip_x: bool = false,
    tint: ?rl.Color = null,
    frame_width: f32 = 0,
    frame_height: f32 = 0,
    frames: usize = 1,
    fps: f32 = 0,
    loop: bool = true,
};

pub const CircleIR = struct {
    radius: f32,
    color: rl.Color,
};

pub const RectIR = struct {
    width: f32,
    height: f32,
    color: rl.Color,
};

pub const CameraIR = struct {
    offset: rl.Vector2,
    rotation: f32 = 0,
    zoom: f32 = 1.0,
    follow_tag: ?[]const u8 = null,
};

pub const PlayerControllerIR = struct {
    speed: f32 = 100,
};

pub const SolidIR = struct {
    enabled: bool = true,
};

pub const AnimationClipIR = struct {
    name: []const u8,
    start: usize = 0,
    frames: usize = 1,
    fps: f32 = 8,
    loop: bool = true,
};

pub const AnimationIR = struct {
    current: ?[]const u8 = null,
    clips: []AnimationClipIR = &.{},
};

pub const TilemapIR = struct {
    columns: usize,
    rows: usize,
    tile_width: f32 = 16,
    tile_height: f32 = 16,
    tiles: []const u8,
    solid_tiles: []const u8 = &.{},
    palette: []const rl.Color = &.{},
};

pub const ParticleEmitterIR = struct {
    color: rl.Color = rl.Color.white,
    rate: f32 = 12,
    lifetime: f32 = 0.6,
    speed: f32 = 40,
    spread: f32 = 6.28,
    radius: f32 = 2,
    burst: usize = 0,
};

pub const TweenIR = struct {
    to: rl.Vector2,
    duration: f32 = 1,
    loop: bool = false,
};

pub const TriggerIR = struct {
    bounds: rl.Rectangle,
    one_shot: bool = false,
    action: TriggerActionIR,
};

pub const TriggerActionIR = union(enum) {
    StartDialogue: struct { id: ?[]const u8 = null, label: ?[]const u8 = null },
    ShowMessage: struct { text: []const u8, duration: f32 = 2.0 },
    ChangeScene: struct { index: ?usize = null, name: ?[]const u8 = null },
    SetFlag: struct { name: []const u8, value: bool = true },
};

pub fn parseColor(name: []const u8) ?rl.Color {
    if (std.ascii.eqlIgnoreCase(name, "red")) return rl.Color.red;
    if (std.ascii.eqlIgnoreCase(name, "green")) return rl.Color.green;
    if (std.ascii.eqlIgnoreCase(name, "blue")) return rl.Color.blue;
    if (std.ascii.eqlIgnoreCase(name, "black")) return rl.Color.black;
    if (std.ascii.eqlIgnoreCase(name, "white")) return rl.Color.white;
    return null;
}

pub fn parseColorHex(hex: []const u8) ?rl.Color {
    // Accept #RRGGBB or #RRGGBBAA.
    if (hex.len != 7 and hex.len != 9) return null;
    if (hex[0] != '#') return null;

    const r = std.fmt.parseInt(u8, hex[1..3], 16) catch return null;
    const g = std.fmt.parseInt(u8, hex[3..5], 16) catch return null;
    const b = std.fmt.parseInt(u8, hex[5..7], 16) catch return null;
    const a: u8 = if (hex.len == 9) (std.fmt.parseInt(u8, hex[7..9], 16) catch return null) else 255;

    return rl.Color{ .r = r, .g = g, .b = b, .a = a };
}
