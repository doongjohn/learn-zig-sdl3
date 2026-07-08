// zig project with the main function being in C:
// https://gist.github.com/andrewrk/c1c3eebd0a102cd8c923058cae95532c
pub const _start = void;
pub const WinMainCRTStartup = void;

const builtin = @import("builtin");
const is_wasm = builtin.cpu.arch.isWasm();

const std = @import("std");
const sdl = @import("sdl");

const use_debug_allocator = !is_wasm and switch (builtin.mode) {
    .Debug => true,
    .ReleaseSafe => !builtin.link_libc,
    .ReleaseFast, .ReleaseSmall => !builtin.link_libc and builtin.single_threaded,
};
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

fn printWithLoc(src: std.lang.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    std.log.err("'{s}:{d}:{d}' -> " ++ fmt, .{ src.file, src.line, src.column } ++ args);
}

fn sdlCall(src: std.lang.SourceLocation, result: bool) !void {
    if (!result) {
        printWithLoc(src, "SDL error: {s}", .{sdl.SDL_GetError()});
        return error.SdlError;
    }
}

const renderer_backend = "vulkan";

const AppWindowTable = std.AutoHashMap(sdl.SDL_WindowID, AppWindow);

const CreateWindowResult = struct {
    window: ?*sdl.SDL_Window = null,
    renderer: ?*sdl.SDL_Renderer = null,
};

const App = struct {
    allocator: std.mem.Allocator = undefined,
    app_window_table: AppWindowTable = undefined,

    fn init(self: *@This()) !void {
        self.allocator = if (use_debug_allocator)
            debug_allocator.allocator()
        else if (builtin.link_libc)
            std.heap.c_allocator
        else if (is_wasm)
            std.heap.wasm_allocator
        else if (!builtin.single_threaded)
            std.heap.smp_allocator
        else
            comptime unreachable;

        self.app_window_table = AppWindowTable.init(self.allocator);

        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            printWithLoc(@src(), "SDL_Init failed: {s}", .{sdl.SDL_GetError()});
            return error.SdlError;
        }

        const result = try App.createWindow("SDL3 with Zig", 600, 300);
        try self.addAppWindow(result.window, result.renderer);
    }

    fn deinit(self: *@This()) void {
        self.app_window_table.deinit();
        if (use_debug_allocator) {
            std.debug.assert(debug_allocator.deinit() == .ok);
        }
    }

    fn from_ptr(ptr: ?*anyopaque) ?*@This() {
        return @ptrCast(@alignCast(ptr));
    }

    fn createWindow(title: [:0]const u8, w: i64, h: i64) !CreateWindowResult {
        const props = sdl.SDL_CreateProperties();
        defer sdl.SDL_DestroyProperties(props);

        try sdlCall(@src(), sdl.SDL_SetStringProperty(props, sdl.SDL_PROP_WINDOW_CREATE_TITLE_STRING, title));
        try sdlCall(@src(), sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, w));
        try sdlCall(@src(), sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, h));
        try sdlCall(@src(), sdl.SDL_SetBooleanProperty(props, sdl.SDL_PROP_WINDOW_CREATE_HIDDEN_BOOLEAN, true));

        const window = sdl.SDL_CreateWindowWithProperties(props);
        if (window == null) {
            printWithLoc(@src(), "SDL_CreateWindowWithProperties failed: {s}", .{sdl.SDL_GetError()});
            return error.SdlError;
        }

        const renderer = sdl.SDL_CreateRenderer(window, renderer_backend);
        if (renderer == null) {
            printWithLoc(@src(), "SDL_CreateRenderer failed: {s}", .{sdl.SDL_GetError()});
            return error.SdlError;
        }

        // Show window after the renderer is created.
        try sdlCall(@src(), sdl.SDL_SetRenderDrawColorFloat(renderer, 0, 0, 0, 1));
        try sdlCall(@src(), sdl.SDL_RenderClear(renderer));
        try sdlCall(@src(), sdl.SDL_RenderPresent(renderer));
        try sdlCall(@src(), sdl.SDL_ShowWindow(window));

        return .{
            .window = window,
            .renderer = renderer,
        };
    }

    fn addAppWindow(self: *@This(), window: ?*sdl.SDL_Window, renderer: ?*sdl.SDL_Renderer) !void {
        if (window == null or renderer == null) {
            return error.InvalidParameter;
        }

        const window_id = sdl.SDL_GetWindowID(window);
        if (self.app_window_table.contains(window_id)) {
            return;
        }

        try self.app_window_table.put(window_id, .{
            .window_id = window_id,
            .window = window,
            .renderer = renderer,
        });

        var app_window = self.app_window_table.getPtr(window_id).?;

        app_window.init() catch {
            self.removeAppWindow(app_window);
            if (self.app_window_table.count() == 0) {
                var quit_event = sdl.SDL_Event{ .type = sdl.SDL_EVENT_QUIT };
                if (!sdl.SDL_PushEvent(&quit_event)) {
                    printWithLoc(@src(), "SDL_PushEvent failed: {s}", .{sdl.SDL_GetError()});
                }
            }
            return error.InitError;
        };
    }

    fn removeAppWindow(self: *@This(), app_window: *AppWindow) void {
        app_window.deinit();
        _ = self.app_window_table.remove(app_window.window_id);
    }
};

const AppWindow = struct {
    window_id: sdl.SDL_WindowID,
    window: ?*sdl.SDL_Window = null,
    renderer: ?*sdl.SDL_Renderer = null,

    mouse_x: f32 = 0,
    mouse_y: f32 = 0,

    fn init(self: *@This()) !void {
        if (!sdl.SDL_SetWindowResizable(self.window, true)) {
            printWithLoc(@src(), "SDL_SetWindowResizable failed: {s}\n", .{sdl.SDL_GetError()});
            return error.SdlError;
        }

        var window_w: c_int = 0;
        var window_h: c_int = 0;
        if (sdl.SDL_GetWindowSize(self.window, &window_w, &window_h)) {
            self.mouse_x = @floatFromInt(@divFloor(window_w, 2));
            self.mouse_y = @floatFromInt(@divFloor(window_h, 2));
        }
    }

    fn deinit(self: *@This()) void {
        sdl.SDL_DestroyRenderer(self.renderer);
        sdl.SDL_DestroyWindow(self.window);
    }

    fn update(self: *@This()) !void {
        // Clear color.
        const now: f64 = @as(f64, @floatFromInt(sdl.SDL_GetTicks())) / 1000.0;
        const red: f32 = @floatCast(0.5 + 0.5 * sdl.SDL_sin(now));
        const green: f32 = @floatCast(0.5 + 0.5 * sdl.SDL_sin(now + sdl.SDL_PI_D * 2 / 3));
        const blue: f32 = @floatCast(0.5 + 0.5 * sdl.SDL_sin(now + sdl.SDL_PI_D * 4 / 3));
        try sdlCall(@src(), sdl.SDL_SetRenderDrawColorFloat(self.renderer, red, green, blue, 1));
        try sdlCall(@src(), sdl.SDL_RenderClear(self.renderer));

        // Draw rect.
        const rect = sdl.SDL_FRect{
            .x = self.mouse_x - 25,
            .y = self.mouse_y - 25,
            .w = 50,
            .h = 50,
        };
        try sdlCall(@src(), sdl.SDL_SetRenderDrawColorFloat(self.renderer, 1, 1, 1, 1));
        try sdlCall(@src(), sdl.SDL_RenderFillRect(self.renderer, &rect));

        // Draw text.
        try sdlCall(@src(), sdl.SDL_SetRenderDrawColorFloat(self.renderer, 1, 1, 1, 1));
        try sdlCall(@src(), sdl.SDL_SetRenderScale(self.renderer, 2, 2));
        try sdlCall(@src(), sdl.SDL_RenderDebugText(self.renderer, 5, 5, "Press Space to create a new window."));
        try sdlCall(@src(), sdl.SDL_SetRenderScale(self.renderer, 1, 1));

        // Update the screen.
        try sdlCall(@src(), sdl.SDL_RenderPresent(self.renderer));
    }

    fn processEvent(self: *@This(), event: *sdl.SDL_Event) void {
        switch (event.type) {
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                const button = event.button.button;
                std.debug.print("window: {d}, mouse down: {d}\n", .{ self.window_id, button });
            },
            sdl.SDL_EVENT_MOUSE_MOTION => {
                self.mouse_x = event.motion.x;
                self.mouse_y = event.motion.y;
            },
            else => {},
        }
    }
};

var app_obj: App = .{};

export fn SDL_AppInit(appstate_ptr: ?*?*anyopaque, argc: c_int, argv: [*][*:0]u8) sdl.SDL_AppResult {
    _ = argc;
    _ = argv;

    if (appstate_ptr) |appstate| {
        app_obj.init() catch {
            printWithLoc(@src(), "App init failed", .{});
            return sdl.SDL_APP_FAILURE;
        };
        appstate.* = &app_obj;
        return sdl.SDL_APP_CONTINUE;
    } else {
        printWithLoc(@src(), "appstate_ptr is null", .{});
        return sdl.SDL_APP_FAILURE;
    }
}

export fn SDL_AppEvent(appstate: ?*anyopaque, event_ptr: ?*sdl.SDL_Event) sdl.SDL_AppResult {
    if (App.from_ptr(appstate)) |app| {
        if (event_ptr) |event| {
            const window_id = event.window.windowID;

            switch (event.type) {
                sdl.SDL_EVENT_QUIT => {
                    return sdl.SDL_APP_SUCCESS;
                },
                sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    if (app.app_window_table.getPtr(window_id)) |app_window| {
                        app.removeAppWindow(app_window);
                    }
                },
                sdl.SDL_EVENT_KEY_DOWN => {
                    if (event.key.key == sdl.SDLK_SPACE) {
                        const result = App.createWindow("SDL3 with Zig", 600, 300) catch {
                            printWithLoc(@src(), "createAppWindow failed\n", .{});
                            if (@errorReturnTrace()) |et| std.debug.dumpErrorReturnTrace(et);
                            return sdl.SDL_APP_FAILURE;
                        };

                        app.addAppWindow(result.window, result.renderer) catch {
                            printWithLoc(@src(), "addAppWindow failed\n", .{});
                            if (@errorReturnTrace()) |et| std.debug.dumpErrorReturnTrace(et);
                            return sdl.SDL_APP_FAILURE;
                        };
                    }
                },
                else => {
                    if (app.app_window_table.getPtr(window_id)) |app_window| {
                        app_window.processEvent(event);
                    }
                },
            }
        }
    }

    return sdl.SDL_APP_CONTINUE;
}

export fn SDL_AppIterate(appstate: ?*anyopaque) sdl.SDL_AppResult {
    if (App.from_ptr(appstate)) |app| {
        var iterator = app.app_window_table.valueIterator();
        while (iterator.next()) |app_window| {
            app_window.update() catch |err| switch (err) {
                error.SdlError => {
                    printWithLoc(@src(), "Update failed for window: {d}.\n", .{app_window.window_id});
                    if (@errorReturnTrace()) |et| std.debug.dumpErrorReturnTrace(et);
                    return sdl.SDL_APP_FAILURE;
                },
            };
        }
    }

    return sdl.SDL_APP_CONTINUE;
}

export fn SDL_AppQuit(appstate: ?*anyopaque, result: sdl.SDL_AppResult) void {
    _ = result;

    if (App.from_ptr(appstate)) |app| {
        app.deinit();
    }
}
