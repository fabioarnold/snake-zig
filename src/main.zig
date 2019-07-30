const std = @import("std");
const panic = std.debug.panic;
const warn = std.debug.warn;
const c_allocator = std.heap.c_allocator;

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("SDL2/SDL_opengl.h");
});

const SDL_WINDOWPOS_UNDEFINED = @bitCast(c_int, c.SDL_WINDOWPOS_UNDEFINED_MASK);

const SDL_GL_CONTEXT_PROFILE_MASK = @intToEnum(c.SDL_GLattr, c.SDL_GL_CONTEXT_PROFILE_MASK);
const SDL_GL_CONTEXT_MAJOR_VERSION = @intToEnum(c.SDL_GLattr, c.SDL_GL_CONTEXT_MAJOR_VERSION);
const SDL_GL_CONTEXT_MINOR_VERSION = @intToEnum(c.SDL_GLattr, c.SDL_GL_CONTEXT_MINOR_VERSION);

extern fn SDL_PollEvent(event: *c.SDL_Event) c_int;

var sdl_window: *c.SDL_Window = undefined;

fn identityM3() [9]f32 {
    return [9]f32 {
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
    };
}

fn translateM3(m: [9]f32, tx: f32, ty: f32) void {
    m[0] = 1.0; m[3] = 0.0; m[6] = tx;
    m[1] = 0.0; m[4] = 1.0; m[7] = ty;
    m[2] = 0.0; m[5] = 0.0; m[8] = 1.0;
}

fn scaleM3(sx: f32, sy: f32) [9]f32 {
    return [9]f32 {
        sx,  0.0, 0.0,
        0.0, sy,  0.0,
        0.0, 0.0, 1.0,
    };
}

fn rotateM3(m: [9]f32, angle: f32) void {
    const s = sinf(angle);
    const c = cosf(angle);
    m[0] =   c; m[3] =  -s; m[6] = 0.0;
    m[1] =   s; m[4] =   c; m[7] = 0.0;
    m[2] = 0.0; m[5] = 0.0; m[8] = 1.0;
}

fn multiplyM3(m: [9]f32, m0: [9]f32, m1: [9]f32) void {
    @memSet(m, 0, 9 * @sizeOf(f32));
    const nums = [_]i32{0, 1, 2};
    for (nums) |i|
    for (nums) |j|
    for (nums) |k|
        m[3 * j + i] += m0[3 * j + k] * m1[3 * k + i];
}

fn initGlShader(kind: c.GLenum, source: []const u8) !c.GLuint {
    const shader_id = c.glCreateShader(kind);
    const source_ptr: ?[*]const u8 = source.ptr;
    const source_len = @intCast(c.GLint, source.len);
    c.glShaderSource(shader_id, 1, &source_ptr, &source_len);
    c.glCompileShader(shader_id);

    var ok: c.GLint = undefined;
    c.glGetShaderiv(shader_id, c.GL_COMPILE_STATUS, &ok);
    if (ok != 0) return shader_id;

    var error_size: c.GLint = undefined;
    c.glGetShaderiv(shader_id, c.GL_INFO_LOG_LENGTH, &error_size);

    const message = try c_allocator.alloc(u8, @intCast(usize, error_size));
    c.glGetShaderInfoLog(shader_id, error_size, &error_size, message.ptr);
    panic("Error compiling {} shader:\n{}\n", kind, message);
}

fn makeShader(vert_src: []const u8, frag_src: []const u8) !c.GLuint {
    var ok: c.GLint = undefined;

    const vert_shader = try initGlShader(c.GL_VERTEX_SHADER, vert_src);
    const frag_shader = try initGlShader(c.GL_FRAGMENT_SHADER, frag_src);
    const program = c.glCreateProgram();
    c.glAttachShader(program, vert_shader);
    c.glAttachShader(program, frag_shader);
    c.glLinkProgram(program);
    
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &ok);
    if (ok == 0) {
        var error_size: c.GLint = undefined;
        c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &error_size);
        const message = try c_allocator.alloc(u8, @intCast(usize, error_size));
        c.glGetProgramInfoLog(program, error_size, &error_size, message.ptr);
        panic("Error linking shader program: {}\n", message);
    }

    c.glDetachShader(program, vert_shader);
    c.glDetachShader(program, frag_shader);
    c.glDeleteShader(vert_shader);
    c.glDeleteShader(frag_shader);

    return program;
}

const W = 25;
const H = 15;
const N = W * H;

const Direction = enum {
    NORTH,
    SOUTH,
    EAST,
    WEST,
};

const Segment = struct {
    x: i32,
    y: i32,
    dir: Direction,

    pub fn init(x: i32, y: i32, dir: Direction) Segment {
        return Segment {
            .x = x,
            .y = y,
            .dir = dir,
        };
    }
};

const Game = struct {
    snake: [N]Segment,
    head: i32,
    tail: i32,
    dir: Direction,

    fn snakeLength(self: Game) i32 {
        return (head + 1 - tail + N) % N;
    }

    food_x: i32,
    food_y: i32,
    eaten: bool,

    gameover: bool,

    fn reset(self: Game) void {
        head = 1;
        tail = 0;
        dir = SOUTH;

        snake[head] = Segment.init(W / 2, H - 3, SOUTH);
        snake[tail] = Segment.init(W / 2, H - 2, SOUTH);

        gameover = false;

        placeFood();
        eaten = false;
    }

    fn placeFood(self: Game) void {

    }

    fn tick(self: Game) void {
        if (gameover) return;

        var h = &snake[head];
        switch (h.dir) {
            NORTH => { if (dir == SOUTH) dir = NORTH; },
            SOUTH => { if (dir == NORTH) dir = SOUTH; },
            EAST => { if (dir == WEST) dir = EAST; },
            WEST => { if (dir == EAST) dir = WEST; },
        }
        if ((dir == NORTH and h.y == H - 1) or
            (dir == SOUTH and h.y == 0) or
            (dir == EAST  and h.x == W - 1) or
            (dir == WEST  and h.x == 0)) {
            gameover();
            return;
        }
    }
};

const App = struct {
    program: c.GLuint = undefined,
    transform_loc: c.GLint = undefined,
    color_loc: c.GLint = undefined,
    rect_vertex_buffer: c.GLuint = undefined,

    fn init() App {
        var app: App = undefined;

        app.program = makeShader(
            \\uniform mat3 transform;
            \\attribute vec2 position;
            \\void main() {
            \\    vec3 p = transform * vec3(position, 1.0);
            \\    gl_Position = vec4(p.xy, 0.0, 1.0);
            \\}
            ,
            \\uniform vec3 color;
            \\void main() {
            \\    gl_FragColor = vec4(color, 1.0);
            \\}
        ) catch 0;
        c.glUseProgram(app.program);
        app.transform_loc = c.glGetUniformLocation(app.program, c"transform");
        app.color_loc = c.glGetUniformLocation(app.program, c"color");

        const rect_data = [_]f32 {
            -1.0, -1.0,
             1.0, -1.0,
             1.0,  1.0,
            -1.0,  1.0,
        };
        c.glGenBuffers(1, &app.rect_vertex_buffer);
        //c.glBindBuffer(c.GL_ARRAY_BUFFER, app.vbos[0]);
        //c.glBufferData(c.GL_ARRAY_BUFFER, 4 * sizeof(vertex_data), null, c.GL_DYNAMIC_DRAW);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, app.rect_vertex_buffer);
        c.glBufferData(c.GL_ARRAY_BUFFER, rect_data.len * @sizeOf(f32), 
            @ptrCast(*const c_void, &rect_data[0]), c.GL_STATIC_DRAW);

        return app;
    }

    fn drawGame(self: App) void {
        var width: c_int = undefined;
        var height: c_int = undefined;
        c.SDL_GL_GetDrawableSize(sdl_window, &width, &height);
        c.glViewport(0, 0, width, height);
        c.glClearColor(1.0, 1.0, 1.0, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        var scale: [9]f32 = undefined;

        var a0: f32 = @intToFloat(f32, width) / @intToFloat(f32, height);
        var a1: f32 = @intToFloat(f32, W) / @intToFloat(f32, H);
        var sx: f32 = 1.0;
        var sy: f32 = 1.0;
        if (a0 > a1) {sx = a1 / a0;}
        else {sy = a0 / a1;}

        // background
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.rect_vertex_buffer);
        c.glEnableVertexAttribArray(0); // position
        c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2 * @sizeOf(f32), null);
        scale = scaleM3(sx, sy);
        c.glUniformMatrix3fv(self.transform_loc, 1, c.GL_FALSE, &scale[0]);
        c.glUniform3f(self.color_loc, 0.3, 0.3, 0.5);
        c.glDrawArrays(c.GL_LINE_LOOP, 0, 4);

        c.SDL_GL_SwapWindow(sdl_window);
    }
};

extern fn sdlEventWatch(userdata: ?*c_void, sdl_event: [*c]c.SDL_Event) c_int {
    var app: *App = @ptrCast(*App, @alignCast(@alignOf(*App), userdata));

    if (sdl_event.*.type == c.SDL_WINDOWEVENT and
        sdl_event.*.window.event == c.SDL_WINDOWEVENT_RESIZED) {
        app.drawGame(); // draw while resizing
        return 0; // handled
    }
    return 1;
}

pub fn main() !void {
    const video_width: i32 = 1024;
    const video_height: i32 = 640;

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log(c"Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    _ = c.SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,
        c.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY);
    _ = c.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    _ = c.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);

    sdl_window = c.SDL_CreateWindow(c"Snake",
        SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
        video_width, video_height,
        c.SDL_WINDOW_OPENGL |
        c.SDL_WINDOW_RESIZABLE |
        c.SDL_WINDOW_ALLOW_HIGHDPI) orelse
        {
        c.SDL_Log(c"Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(sdl_window);

    const gl_context = c.SDL_GL_CreateContext(sdl_window); // TODO: handle error
    defer c.SDL_GL_DeleteContext(gl_context);

    _ = c.SDL_GL_SetSwapInterval(1);

    var app = App.init();

    c.SDL_AddEventWatch(sdlEventWatch, &app);

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.sym == c.SDLK_ESCAPE) quit = true;
                },
                else => {},
            }
        }

        app.drawGame();
    }
}