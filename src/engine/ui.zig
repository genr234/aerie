const toast = @import("ui/toast.zig");
const events = @import("events.zig");

pub const UIStyles = struct {
    toast: toast.ToastStyle,
};

pub fn draw() void {

}

pub fn drawFromEventQueue(eq: events.EventQueue, styles: UIStyles) void {
    toast.drawEventQueueToasts(&eq, styles.toast);
}