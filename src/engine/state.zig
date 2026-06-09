const scenes = @import("scenes.zig");
const dialogue = @import("dialogue.zig");
const rl = @import("raylib");
const vn = @import("vn.zig");
const story = @import("story.zig");
const events = @import("events.zig");
const combat = @import("combat.zig");

pub const GameState = struct {
    manager: *scenes.SceneManager,
    sceneBuilder: *scenes.Builder,

    gameDialogue: dialogue.Runner,
    playerTexture: ?rl.Texture2D = null,
    dialogueScripts: []dialogue.Script = &.{},
    isTransitioning: bool = false,

    vnActive: bool = false,
    vnState: vn.VNState,
    vnDialogue: dialogue.Runner,
    vnDialogueScripts: []dialogue.Script = &.{},

    storyState: story.StoryState,
    eventQueue: events.EventQueue,
    combatState: combat.BattleState,
};
