const dialogue = @import("../dialogue.zig");
const events = @import("../events.zig");
const scenes = @import("../scenes.zig");
const story = @import("../story.zig");

pub const ScriptingContext = struct {
    eventQueue: *events.EventQueue,
    storyState: *story.StoryState,
    sceneManager: *scenes.SceneManager,
    gameDialogue: *dialogue.Runner,
    vnDialogue: *dialogue.Runner,
    vnActive: *bool,

    pub fn activeDialogue(self: *const ScriptingContext) *dialogue.Runner {
        return if (self.vnActive.*) self.vnDialogue else self.gameDialogue;
    }
};
