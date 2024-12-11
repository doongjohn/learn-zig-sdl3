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
    std.debug.print("[ERROR]: \"{s}:{d}:{d}\" ", .{ src.file.ptr, src.line, src.column });
    std.debug.print(fmt, args);
}

const AppWindowTable = std.AutoHashMap(sdl.SDL_WindowID, AppWindow);

const App = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined,
    allocator: std.mem.Allocator = undefined,
    app_window_table: AppWindowTable = undefined,
    app_quit_event: sdl.SDL_Event = .{ .type = sdl.SDL_EVENT_QUIT },

    fn from_ptr(ptr: ?*anyopaque) ?*@This() {
        return @alignCast(@ptrCast(ptr));
    }

    fn init(self: *@This()) !void {
        self.gpa = std.heap.GeneralPurposeAllocator(.{}){};
        self.allocator = self.gpa.allocator();
        self.app_window_table = AppWindowTable.init(self.allocator);

        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            printError(@src(), "SDL_Init failed: {s}\n", .{sdl.SDL_GetError()});
            return error.AppInitFailure;
        }

        var window: ?*sdl.SDL_Window = null;
        var renderer: ?*sdl.SDL_Renderer = null;
        if (!sdl.SDL_CreateWindowAndRenderer("SDL3 with Zig", 600, 300, 0, &window, &renderer)) {
            printError(@src(), "SDL_CreateWindowAndRenderer failed: {s}\n", .{sdl.SDL_GetError()});
            return error.AppInitFailure;
        }
        try self.addAppWindow(window, renderer);
    }

    fn deinit(self: *@This()) void {
        self.app_window_table.deinit();
    }

    fn addAppWindow(self: *@This(), window: ?*sdl.SDL_Window, renderer: ?*sdl.SDL_Renderer) !void {
        const window_id = sdl.SDL_GetWindowID(window);
        if (self.app_window_table.contains(window_id)) {
            return;
        }

        try self.app_window_table.put(window_id, .{
            .window_id = window_id,
            .window = window,
            .renderer = renderer,
        });

        if (self.app_window_table.getPtr(window_id)) |aw| {
            aw.init() catch {
                self.removeAppWindow(aw);
                if (self.app_window_table.count() == 0) {
                    _ = sdl.SDL_PushEvent(&self.app_quit_event);
                }
            };
        }
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
            return error.AppWindowInitFaliure;
        }
    }

    fn deinit(self: *@This()) void {
        sdl.SDL_DestroyRenderer(self.renderer);
        sdl.SDL_DestroyWindow(self.window);
    }

    fn update(self: *@This()) void {
        const now: f64 = @as(f64, @floatFromInt(sdl.SDL_GetTicks())) / 1000.0;
        const red: f32 = @floatCast(0.5 + 0.5 * sdl.SDL_sin(now));
        const green: f32 = @floatCast(0.5 + 0.5 * sdl.SDL_sin(now + sdl.SDL_PI_D * 2 / 3));
        const blue: f32 = @floatCast(0.5 + 0.5 * sdl.SDL_sin(now + sdl.SDL_PI_D * 4 / 3));

        _ = sdl.SDL_SetRenderDrawColorFloat(self.renderer, red, green, blue, sdl.SDL_ALPHA_OPAQUE_FLOAT);
        _ = sdl.SDL_RenderClear(self.renderer);

        const rect = sdl.SDL_FRect{
            .x = self.mouse_x - 25,
            .y = self.mouse_y - 25,
            .w = 50,
            .h = 50,
        };
        _ = sdl.SDL_SetRenderDrawColorFloat(self.renderer, 1, 1, 1, sdl.SDL_ALPHA_OPAQUE_FLOAT);
        _ = sdl.SDL_RenderFillRect(self.renderer, &rect);

        _ = sdl.SDL_RenderPresent(self.renderer);
    }

    fn processEvent(self: *@This(), event: *sdl.SDL_Event) void {
        switch (event.type) {
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                const button = event.button.button;
                std.debug.print("mouse down: {d}\n", .{button});
            },
            sdl.SDL_EVENT_MOUSE_MOTION => {
                self.mouse_x = event.motion.x;
                self.mouse_y = event.motion.y;
            },
            else => {},
        }
    }
};

var app_buffer: [@sizeOf(App)]u8 = undefined;
var app_fba = std.heap.FixedBufferAllocator.init(&app_buffer);

export fn SDL_AppInit(appstate_ptr: ?*?*anyopaque, argc: c_int, argv: [*][*:0]u8) sdl.SDL_AppResult {
    _ = argc;
    _ = argv;

    if (appstate_ptr) |appstate| {
        var app = app_fba.allocator().create(App) catch {
            return sdl.SDL_APP_FAILURE;
        };
        app.init() catch {
            return sdl.SDL_APP_FAILURE;
        };
        appstate.* = app;
    } else {
        return sdl.SDL_APP_FAILURE;
    }

    return sdl.SDL_APP_CONTINUE;
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
                        var window: ?*sdl.SDL_Window = null;
                        var renderer: ?*sdl.SDL_Renderer = null;
                        if (!sdl.SDL_CreateWindowAndRenderer("SDL3 with Zig", 600, 300, 0, &window, &renderer)) {
                            printError(@src(), "SDL_CreateWindowAndRenderer failed: {s}\n", .{sdl.SDL_GetError()});
                            return sdl.SDL_APP_FAILURE;
                        }
                        app.addAppWindow(window, renderer) catch {
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
            app_window.update();
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
