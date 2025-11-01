// zig project with the main function being in C:
// https://gist.github.com/andrewrk/c1c3eebd0a102cd8c923058cae95532c
pub const _start = void;
pub const WinMainCRTStartup = void;

const std = @import("std");

const sdl = @cImport({
    @cDefine("SDL_MAIN_USE_CALLBACKS", "1");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_main.h");
});

fn printError(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    std.log.err("'{s}:{d}:{d}' -> " ++ fmt, .{ src.file, src.line, src.column } ++ args);
}

fn sdlCall(src: std.builtin.SourceLocation, result: bool) !void {
    if (!result) {
        printError(src, "SDL error: {s}", .{sdl.SDL_GetError()});
        return error.SdlError;
    }
}

const AppWindowTable = std.AutoHashMap(sdl.SDL_WindowID, AppWindow);
const renderer_backend = "vulkan";

const App = struct {
    gpa: std.heap.DebugAllocator(.{}) = undefined,
    allocator: std.mem.Allocator = undefined,
    app_window_table: AppWindowTable = undefined,

    fn init(self: *@This()) !void {
        self.gpa = .init;
        self.allocator = self.gpa.allocator();
        self.app_window_table = AppWindowTable.init(self.allocator);

        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            printError(@src(), "SDL_Init failed: {s}", .{sdl.SDL_GetError()});
            return error.SdlError;
        }

        const window = sdl.SDL_CreateWindow("SDL3 with Zig", 600, 300, 0);
        if (window == null) {
            printError(@src(), "SDL_CreateWindow failed: {s}", .{sdl.SDL_GetError()});
            return error.SdlError;
        }

        const renderer = sdl.SDL_CreateRenderer(window, renderer_backend);
        if (renderer == null) {
            printError(@src(), "SDL_CreateRenderer failed: {s}", .{sdl.SDL_GetError()});
            return error.SdlError;
        }

        try self.addAppWindow(window, renderer);
    }

    fn deinit(self: *@This()) void {
        self.app_window_table.deinit();
        std.debug.assert(self.gpa.deinit() == .ok);
    }

    fn from_ptr(ptr: ?*anyopaque) ?*@This() {
        return @ptrCast(@alignCast(ptr));
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
                    printError(@src(), "SDL_PushEvent failed: {s}", .{sdl.SDL_GetError()});
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
            printError(@src(), "SDL_SetWindowResizable failed: {s}\n", .{sdl.SDL_GetError()});
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
        const now: f64 = @as(f64, @floatFromInt(sdl.SDL_GetTicks())) / 1000.0;
        const red: f32 = @floatCast(0.5 + 0.5 * sdl.SDL_sin(now));
        const green: f32 = @floatCast(0.5 + 0.5 * sdl.SDL_sin(now + sdl.SDL_PI_D * 2 / 3));
        const blue: f32 = @floatCast(0.5 + 0.5 * sdl.SDL_sin(now + sdl.SDL_PI_D * 4 / 3));

        try sdlCall(@src(), sdl.SDL_SetRenderDrawColorFloat(self.renderer, red, green, blue, sdl.SDL_ALPHA_OPAQUE_FLOAT));
        try sdlCall(@src(), sdl.SDL_RenderClear(self.renderer));

        const rect = sdl.SDL_FRect{
            .x = self.mouse_x - 25,
            .y = self.mouse_y - 25,
            .w = 50,
            .h = 50,
        };
        try sdlCall(@src(), sdl.SDL_SetRenderDrawColorFloat(self.renderer, 1, 1, 1, sdl.SDL_ALPHA_OPAQUE_FLOAT));
        try sdlCall(@src(), sdl.SDL_RenderFillRect(self.renderer, &rect));

        try sdlCall(@src(), sdl.SDL_SetRenderDrawColorFloat(self.renderer, 1, 1, 1, sdl.SDL_ALPHA_OPAQUE_FLOAT));
        try sdlCall(@src(), sdl.SDL_SetRenderScale(self.renderer, 2, 2));
        try sdlCall(@src(), sdl.SDL_RenderDebugText(self.renderer, 5, 5, "Press Space to create a new window."));
        try sdlCall(@src(), sdl.SDL_SetRenderScale(self.renderer, 1, 1));

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

var app_buf: [@alignOf(App) + @sizeOf(App)]u8 = undefined;
var app_fba = std.heap.FixedBufferAllocator.init(&app_buf);

export fn SDL_AppInit(appstate_ptr: ?*?*anyopaque, argc: c_int, argv: [*][*:0]u8) sdl.SDL_AppResult {
    _ = argc;
    _ = argv;

    if (appstate_ptr) |appstate| {
        var app = app_fba.allocator().create(App) catch {
            printError(@src(), "App alloaction failed", .{});
            return sdl.SDL_APP_FAILURE;
        };
        app.init() catch {
            printError(@src(), "App init failed", .{});
            return sdl.SDL_APP_FAILURE;
        };
        appstate.* = app;
        return sdl.SDL_APP_CONTINUE;
    } else {
        printError(@src(), "appstate_ptr is null", .{});
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
                        const window = sdl.SDL_CreateWindow("SDL3 with Zig", 600, 300, 0);
                        if (window == null) {
                            printError(@src(), "SDL_CreateWindow failed: {s}\n", .{sdl.SDL_GetError()});
                            return sdl.SDL_APP_FAILURE;
                        }
                        const renderer = sdl.SDL_CreateRenderer(window, renderer_backend);
                        if (renderer == null) {
                            printError(@src(), "SDL_CreateRenderer failed: {s}\n", .{sdl.SDL_GetError()});
                            return sdl.SDL_APP_FAILURE;
                        }
                        app.addAppWindow(window, renderer) catch {
                            if (@errorReturnTrace()) |st| std.debug.dumpStackTrace(st);
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
                    printError(@src(), "Update failed for window: {d}.\n", .{app_window.window_id});
                    if (@errorReturnTrace()) |st| std.debug.dumpStackTrace(st);
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
