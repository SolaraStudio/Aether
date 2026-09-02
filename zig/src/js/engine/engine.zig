const std = @import("std");
const c = @cImport({
    @cInclude("quickjs.h");
});
const timer = @import("timer.zig");

pub const JSEngine = struct {
    runtime: *c.JSRuntime,
    context: *c.JSContext,
    timers: timer.TimerQueue,

    pub fn init() !JSEngine {
        const runtime = c.JS_NewRuntime();
        if (runtime == null) return error.OutOfMemory;
        c.JS_SetMemoryLimit(runtime, 256 * 1024 * 1024);
        c.JS_SetMaxStackSize(runtime, 1024 * 1024);
        c.JS_SetContextOpaque(context, @ptrCast(self));
        c.JS_SetContextOpaque(self.context, null);

        const context = c.JS_NewContext(runtime);
        if (context == null) {
            c.JS_FreeRuntime(runtime);
            return error.OutOfMemory;
        }

        var engine = JSEngine{
            .runtime = runtime,
            .context = context,
            .timers = timer.TimerQueue.init(),
        };

        engine.registerConsole();
        engine.registerTimers();

        return engine;
    }

    pub fn deinit(self: *JSEngine) void {
        c.JS_FreeContext(self.context);
        c.JS_FreeRuntime(self.runtime);
    }

    pub fn eval(self: *JSEngine, code: [:0]const u8) ![]const u8 {
        const result = c.JS_Eval(self.context, code.ptr, code.len, "<eval>", c.JS_EVAL_TYPE_GLOBAL);
        defer c.JS_FreeValue(self.context, result);

        if (c.JS_IsException(result)) {
            const exception = c.JS_GetException(self.context);
            defer c.JS_FreeValue(self.context, exception);
            const str = c.JS_ToString(self.context, exception);
            defer c.JS_FreeValue(self.context, str);
            const cstr = c.JS_ToCString(self.context, str);
            defer c.JS_FreeCString(self.context, cstr);
            return error.JSError;
        }

        const str = c.JS_ToString(self.context, result);
        defer c.JS_FreeValue(self.context, str);
        const cstr = c.JS_ToCString(self.context, str);
        defer c.JS_FreeCString(self.context, cstr);
        return std.mem.span(cstr);
    }

    pub fn runTimers(self: *JSEngine) void {
        _ = self.timers.process(self.context);
    }

    fn registerConsole(self: *JSEngine) void {
        const ctx = self.context;
        const console = c.JS_NewObject(ctx);
        c.JS_SetPropertyStr(ctx, console, "log", c.JS_NewCFunction(ctx, consoleLog, "log", 1));
        c.JS_SetPropertyStr(ctx, console, "warn", c.JS_NewCFunction(ctx, consoleWarn, "warn", 1));
        c.JS_SetPropertyStr(ctx, console, "error", c.JS_NewCFunction(ctx, consoleError, "error", 1));
        c.JS_SetPropertyStr(ctx, console, "info", c.JS_NewCFunction(ctx, consoleInfo, "info", 1));
        c.JS_SetPropertyStr(ctx, console, "debug", c.JS_NewCFunction(ctx, consoleDebug, "debug", 1));
        _ = c.JS_SetPropertyStr(ctx, c.JS_GetGlobalObject(ctx), "console", console);
    }

    fn registerTimers(self: *JSEngine) void {
        const ctx = self.context;
        const global = c.JS_GetGlobalObject(ctx);
        defer c.JS_FreeValue(ctx, global);

        const timeout_fn = c.JS_NewCFunction(ctx, setTimeout, "setTimeout", 2);
        _ = c.JS_SetPropertyStr(ctx, global, "setTimeout", timeout_fn);

        const interval_fn = c.JS_NewCFunction(ctx, setInterval, "setInterval", 2);
        _ = c.JS_SetPropertyStr(ctx, global, "setInterval", interval_fn);

        const clear_fn = c.JS_NewCFunction(ctx, clearTimer, "clearTimeout", 1);
        _ = c.JS_SetPropertyStr(ctx, global, "clearTimeout", clear_fn);
        const clear_interval_fn = c.JS_NewCFunction(ctx, clearTimer, "clearInterval", 1);
        _ = c.JS_SetPropertyStr(ctx, global, "clearInterval", clear_interval_fn);
    }
};

fn consoleLog(ctx: *c.JSContext, this_val: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.C) c.JSValue {
    _ = this_val;
    for (0..@intCast(argc)) |i| {
        const str = c.JS_ToString(ctx, argv[i]);
        defer c.JS_FreeValue(ctx, str);
        const cstr = c.JS_ToCString(ctx, str);
        defer c.JS_FreeCString(ctx, cstr);
        std.debug.print("{s} ", .{std.mem.span(cstr)});
    }
    std.debug.print("\n", .{});
    return c.JS_UNDEFINED;
}

fn consoleWarn(ctx: *c.JSContext, this_val: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.C) c.JSValue {
    std.debug.print("[WARN] ", .{});
    return consoleLog(ctx, this_val, argc, argv);
}

fn consoleError(ctx: *c.JSContext, this_val: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.C) c.JSValue {
    std.debug.print("[ERROR] ", .{});
    return consoleLog(ctx, this_val, argc, argv);
}

fn consoleInfo(ctx: *c.JSContext, this_val: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.C) c.JSValue {
    std.debug.print("[INFO] ", .{});
    return consoleLog(ctx, this_val, argc, argv);
}

fn consoleDebug(ctx: *c.JSContext, this_val: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.C) c.JSValue {
    std.debug.print("[DEBUG] ", .{});
    return consoleLog(ctx, this_val, argc, argv);
}

fn setTimeout(ctx: *c.JSContext, this_val: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.C) c.JSValue {
    _ = this_val;
    if (argc < 1) return c.JS_ThrowTypeError(ctx, "setTimeout: at least one argument required");
    const callback = argv[0];
    if (!c.JS_IsFunction(ctx, callback)) {
        return c.JS_ThrowTypeError(ctx, "setTimeout: first argument must be a function");
    }
    var delay: i32 = 0;
    if (argc >= 2) {
        var val = argv[1];
        var d: f64 = 0;
        _ = c.JS_ToFloat64(ctx, &d, val);
        delay = @intFromFloat(d);
        if (delay < 0) delay = 0;
    }

    const eng_ptr = c.JS_GetContextOpaque(ctx);
    const eng = @as(*JSEngine, @ptrFromInt(@intFromPtr(eng_ptr)));

    const id = eng.timers.add(callback, delay, false, ctx);
    return c.JS_NewInt32(ctx, id);
}

fn setInterval(ctx: *c.JSContext, this_val: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.C) c.JSValue {
    _ = this_val;
    if (argc < 1) return c.JS_ThrowTypeError(ctx, "setInterval: at least one argument required");
    const callback = argv[0];
    if (!c.JS_IsFunction(ctx, callback)) {
        return c.JS_ThrowTypeError(ctx, "setInterval: first argument must be a function");
    }
    var delay: i32 = 0;
    if (argc >= 2) {
        var val = argv[1];
        var d: f64 = 0;
        _ = c.JS_ToFloat64(ctx, &d, val);
        delay = @intFromFloat(d);
        if (delay < 0) delay = 0;
    }

    const eng_ptr = c.JS_GetContextOpaque(ctx);
    const eng = @as(*JSEngine, @ptrFromInt(@intFromPtr(eng_ptr)));

    const id = eng.timers.add(callback, delay, true, ctx);
    return c.JS_NewInt32(ctx, id);
}

fn clearTimer(ctx: *c.JSContext, this_val: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.C) c.JSValue {
    _ = this_val;
    if (argc < 1) return c.JS_UNDEFINED;
    var id: i32 = 0;
    _ = c.JS_ToInt32(ctx, &id, argv[0]);

    const eng_ptr = c.JS_GetContextOpaque(ctx);
    const eng = @as(*JSEngine, @ptrFromInt(@intFromPtr(eng_ptr)));
    eng.timers.remove(@intCast(id));
    return c.JS_UNDEFINED;
}
