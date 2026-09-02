const std = @import("std");
const js = @import("js/engine.zig");

var engine: js.JSEngine = undefined;
var initialized: bool = false;

export fn Java_com_aether_AetherEngine_nativeInit() callconv(.C) i64 {
    if (!initialized) {
        engine = js.JSEngine.init() catch return -1;
        initialized = true;
    }
    return @intFromPtr(&engine);
}

export fn Java_com_aether_AetherEngine_nativeEvaluateJS(ptr: i64, script: [*:0]const u8) callconv(.C) void {
    const eng = @as(*js.JSEngine, @ptrFromInt(@as(usize, @intCast(ptr))));
    _ = eng.eval(script) catch {};
}

export fn Java_com_aether_AetherEngine_nativeRunEventLoop(ptr: i64) callconv(.C) void {
    const eng = @as(*js.JSEngine, @ptrFromInt(@as(usize, @intCast(ptr))));
    eng.runTimers();
}
