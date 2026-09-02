const std = @import("std");
const c = @cImport({
    @cInclude("quickjs.h");
});

pub const TimerQueue = struct {
    const Timer = struct {
        id: u32,
        callback: c.JSValue,
        delay: u32,
        repeat: bool,
        ctx: *c.JSContext,
        next: ?*Timer,
    };

    head: ?*Timer = null,
    next_id: u32 = 1,

    pub fn init() TimerQueue {
        return TimerQueue{};
    }

    pub fn add(self: *TimerQueue, callback: c.JSValue, delay: i32, repeat: bool, ctx: *c.JSContext) u32 {
        const id = self.next_id;
        self.next_id += 1;

        const timer = std.heap.c_allocator.create(Timer) catch return 0;
        timer.* = Timer{
            .id = id,
            .callback = c.JS_DupValue(ctx, callback),
            .delay = @intCast(delay),
            .repeat = repeat,
            .ctx = ctx,
            .next = self.head,
        };
        self.head = timer;
        return id;
    }

    pub fn remove(self: *TimerQueue, id: u32) void {
        var prev: ?*Timer = null;
        var current = self.head;
        while (current) |t| {
            if (t.id == id) {
                if (prev) |p| {
                    p.next = t.next;
                } else {
                    self.head = t.next;
                }
                c.JS_FreeValue(t.ctx, t.callback);
                std.heap.c_allocator.destroy(t);
                return;
            }
            prev = current;
            current = t.next;
        }
    }

    pub fn process(self: *TimerQueue, ctx: *c.JSContext) u32 {
        var executed: u32 = 0;
        var prev: ?*Timer = null;
        var current = self.head;
        while (current) |t| {
            if (t.delay == 0) {
                _ = c.JS_Call(t.ctx, t.callback, c.JS_UNDEFINED, 0, null);
                executed += 1;
                if (t.repeat) {
                    t.delay = 0;
                    prev = current;
                    current = t.next;
                } else {
                    const to_remove = t;
                    if (prev) |p| {
                        p.next = t.next;
                    } else {
                        self.head = t.next;
                    }
                    current = t.next;
                    c.JS_FreeValue(to_remove.ctx, to_remove.callback);
                    std.heap.c_allocator.destroy(to_remove);
                }
            } else {
                t.delay -= 1;
                prev = current;
                current = t.next;
            }
        }
        return executed;
    }
};
