const dialogue = @import("../dialogue.zig");
const events = @import("../events.zig");
const scenes = @import("../scenes.zig");
const story = @import("../story.zig");
const combat = @import("../combat.zig");

pub const ScriptingContext = struct {
    projectRoot: []const u8,
    eventQueue: *events.EventQueue,
    storyState: *story.StoryState,
    sceneManager: *scenes.SceneManager,
    gameDialogue: *dialogue.Runner,
    vnDialogue: *dialogue.Runner,
    vnActive: *bool,
    combatState: *combat.BattleState,

    pub fn activeDialogue(self: *const ScriptingContext) *dialogue.Runner {
        return if (self.vnActive.*) self.vnDialogue else self.gameDialogue;
    }
};
