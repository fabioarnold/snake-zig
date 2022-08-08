const std = @import("std");
const panic = std.debug.panic;
const c_allocator = std.heap.c_allocator;
const rand = std.rand;
const builtin = @import("builtin");

var r = rand.DefaultPrng.init(4); // seed chosen by dice roll

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("gl2_impl.h");
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("SDL2/SDL_opengl.h");
});

extern fn gladLoadGL() callconv(.C) c_int; // init OpenGL function pointers on Windows and Linux

export fn WinMain() callconv(.C) c_int {
    main() catch return 1; // TODO report error
    return 0;
}

var sdl_window: *c.SDL_Window = undefined;

fn identityM3() [9]f32 {
    return [9]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
    };
}

fn translateM3(tx: f32, ty: f32) [9]f32 {
    return [9]f32{
        1.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        tx,  ty,  1.0,
    };
}

fn scaleM3(sx: f32, sy: f32) [9]f32 {
    return [9]f32{
        sx,  0.0, 0.0,
        0.0, sy,  0.0,
        0.0, 0.0, 1.0,
    };
}

fn rotateM3(angle: f32) [9]f32 {
    const si = @sin(angle);
    const co = @cos(angle);
    return [9]f32{
        co,  si,  0.0,
        -si, co,  0.0,
        0.0, 0.0, 1.0,
    };
}

fn multiplyM3(m0: [9]f32, m1: [9]f32) [9]f32 {
    var m = [_]f32{0.0} ** 9;
    const nums = [_]usize{ 0, 1, 2 };
    for (nums) |i| {
        for (nums) |j| {
            for (nums) |k| {
                m[3 * j + i] += m0[3 * j + k] * m1[3 * k + i];
            }
        }
    }
    return m;
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
    panic("Error compiling {any} shader:\n{s}\n", .{ kind, message });
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
        panic("Error linking shader program: {s}\n", .{message});
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
    UP,
    DOWN,
    LEFT,
    RIGHT,

    pub fn isOpposite(first: Direction, second: Direction) bool {
        return first == Direction.UP and second == Direction.DOWN or first == Direction.DOWN and second == Direction.UP or first == Direction.LEFT and second == Direction.RIGHT or first == Direction.RIGHT and second == Direction.LEFT;
    }
};

const Segment = struct {
    x: i32,
    y: i32,
    dir: Direction,

    pub fn init(x: i32, y: i32, dir: Direction) Segment {
        return Segment{
            .x = x,
            .y = y,
            .dir = dir,
        };
    }
};

const Game = struct {
    snake: [N]Segment,
    head: usize,
    tail: usize,
    dir: ?Direction,
    queued_dir: ?Direction,

    food_x: i32,
    food_y: i32,
    eaten: bool,

    gameover: bool,

    fn snakeLength(self: Game) usize {
        return ((self.head + N + 1) - self.tail) % N;
    }

    fn reset(self: *Game) void {
        self.head = 1;
        self.tail = 0;
        self.dir = null;
        self.queued_dir = null;

        self.snake[self.head] = Segment.init(W / 2, H - 3, Direction.DOWN);
        self.snake[self.tail] = Segment.init(W / 2, H - 2, Direction.DOWN);

        self.gameover = false;

        self.placeFood();
        self.eaten = false;
    }

    fn onGameover(self: *Game) void {
        self.gameover = true;
        std.debug.print("snake length: {}\n", .{self.snakeLength()});
    }

    fn placeFood(self: *Game) void {
        const len = self.snakeLength();
        var grid = [_]bool{false} ** N; // mark occupied cells
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const s = &self.snake[(self.tail + i) % N];
            grid[W * @intCast(usize, s.y) + @intCast(usize, s.x)] = true;
        }
        var f = r.random().uintLessThan(usize, N - len); // choose free cell index
        i = 0;
        while (i < N) : (i += 1) {
            if (!grid[i]) {
                if (f == 0) {
                    self.food_x = @intCast(i32, i % W);
                    self.food_y = @intCast(i32, i / W);
                    return;
                }
                f -= 1;
            }
        }
    }

    fn tick(self: *Game) void {
        if (self.gameover) return;

        var h = &self.snake[self.head];
        var next_dir = if (self.dir) |d| d else h.dir;
        self.dir = self.queued_dir;
        self.queued_dir = null;
        if (Direction.isOpposite(h.dir, next_dir)) {
            next_dir = h.dir;
        }
        if ((next_dir == Direction.UP and h.y == H - 1) or
            (next_dir == Direction.DOWN and h.y == 0) or
            (next_dir == Direction.LEFT and h.x == 0) or
            (next_dir == Direction.RIGHT and h.x == W - 1))
        {
            self.onGameover();
            return;
        }

        self.head = (self.head + 1) % N;
        switch (next_dir) {
            Direction.UP => self.snake[self.head] = Segment.init(h.x, h.y + 1, Direction.UP),
            Direction.DOWN => self.snake[self.head] = Segment.init(h.x, h.y - 1, Direction.DOWN),
            Direction.LEFT => self.snake[self.head] = Segment.init(h.x - 1, h.y, Direction.LEFT),
            Direction.RIGHT => self.snake[self.head] = Segment.init(h.x + 1, h.y, Direction.RIGHT),
        }
        h = &self.snake[self.head];

        var i: usize = self.tail;
        while (i != self.head) : (i = (i + 1) % N) {
            if (h.x == self.snake[i].x and h.y == self.snake[i].y) {
                self.onGameover();
                return;
            }
        }

        if (h.x == self.food_x and h.y == self.food_y) {
            self.eaten = true;
            if (self.head == self.tail) {
                self.onGameover();
                return;
            }
            self.placeFood();
        } else {
            self.eaten = false;
            self.tail = (self.tail + 1) % N;
        }
    }

    fn addNextDir(self: *Game, dir: Direction) void {
        if (self.dir == null) {
            self.dir = dir;
        } else if (self.queued_dir == null and dir != self.dir.?) {
            self.queued_dir = dir;
        }
    }
};
var game: Game = undefined;

var default_shader: c.GLuint = undefined;
var transform_loc: c.GLint = undefined;
var color_loc: c.GLint = undefined;
var sprite_vertex_buffer: c.GLuint = undefined;
var rect_vertex_buffer: c.GLuint = undefined;

fn initGL() void {
    default_shader = makeShader(
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
    c.glUseProgram(default_shader);
    transform_loc = c.glGetUniformLocation(default_shader, "transform");
    color_loc = c.glGetUniformLocation(default_shader, "color");

    const rect_data = [_]f32{
        -1.0, -1.0,
        1.0,  -1.0,
        1.0,  1.0,
        -1.0, 1.0,
    };
    c.glGenBuffers(1, &sprite_vertex_buffer);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, sprite_vertex_buffer);
    c.glBufferData(c.GL_ARRAY_BUFFER, 4 * vertex_buffer.len * @sizeOf(f32), null, c.GL_DYNAMIC_DRAW);
    c.glGenBuffers(1, &rect_vertex_buffer);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, rect_vertex_buffer);
    c.glBufferData(c.GL_ARRAY_BUFFER, rect_data.len * @sizeOf(f32), &rect_data[0], c.GL_STATIC_DRAW);
}

const draw_detail = 16;
var vertex_buffer: [4 * (draw_detail + 1)]f32 = undefined;

fn drawGame(alpha: f32) void {
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
    if (a0 > a1) {
        sx = a1 / a0;
    } else {
        sy = a0 / a1;
    }

    // background
    c.glBindBuffer(c.GL_ARRAY_BUFFER, rect_vertex_buffer);
    c.glEnableVertexAttribArray(0); // position
    c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2 * @sizeOf(f32), null);
    scale = scaleM3(sx, sy);
    c.glUniformMatrix3fv(transform_loc, 1, c.GL_FALSE, &scale[0]);
    c.glUniform3f(color_loc, 0.3, 0.3, 0.5);
    c.glDrawArrays(c.GL_LINE_LOOP, 0, 4);

    // sprite types
    c.glBindBuffer(c.GL_ARRAY_BUFFER, sprite_vertex_buffer);
    c.glEnableVertexAttribArray(0); // position
    c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 2 * @sizeOf(f32), null);
    for ([_]usize{ 0, 1, 2, 3 }) |s| {
        var i: usize = 0;
        while (i <= draw_detail) : (i += 1) {
            const angle = @intToFloat(f32, i) / @intToFloat(f32, draw_detail) * std.math.pi;
            vertex_buffer[2 * i + 0] = @cos(angle);
            vertex_buffer[2 * i + 1] = @sin(angle);
            vertex_buffer[2 * (draw_detail + 1 + i) + 0] = -@cos(angle);
            vertex_buffer[2 * (draw_detail + 1 + i) + 1] = -@sin(angle) - 2.0;
            if (s == 1) { // head
                vertex_buffer[2 * i + 1] += 2.0 * alpha - 2.0;
            } else if (s == 2) { // tail
                vertex_buffer[2 * (draw_detail + 1 + i) + 1] +=
                    if (game.eaten) 2.0 else 2.0 * alpha;
            } else if (s == 3) { // food
                vertex_buffer[2 * (draw_detail + 1 + i) + 1] += 2.0;
            }
        }
        c.glBufferSubData(c.GL_ARRAY_BUFFER, @intCast(c_long, s * vertex_buffer.len * @sizeOf(f32)), vertex_buffer.len * @sizeOf(f32), &vertex_buffer[0]);
    }
    const n = 2 * (draw_detail + 1);

    // snake
    scale = scaleM3(sx / W, sy / H);
    c.glUniform3f(color_loc, 0.3, 0.7, 0.1);
    var i = game.tail;
    while (true) : (i = (i + 1) % N) {
        const s = &game.snake[i];
        var stype: i32 = 0;
        if (i == game.tail) {
            stype = 2;
        } else if (i == game.head) {
            stype = 1;
        }
        const translation = translateM3(2.0 * @intToFloat(f32, s.x) - @intToFloat(f32, W) + 1.0, 2.0 * @intToFloat(f32, s.y) - @intToFloat(f32, H) + 1.0);
        var rt: i32 = undefined;
        switch (s.dir) {
            Direction.UP => rt = 0,
            Direction.DOWN => rt = 2,
            Direction.LEFT => rt = 1,
            Direction.RIGHT => rt = 3,
        }
        const rotation = rotateM3(@intToFloat(f32, rt) / 2.0 * std.math.pi);
        const tmp = multiplyM3(translation, scale);
        const transform = multiplyM3(rotation, tmp);
        c.glUniformMatrix3fv(transform_loc, 1, c.GL_FALSE, &transform[0]);

        c.glDrawArrays(c.GL_TRIANGLE_FAN, stype * n, n);
        if (i == game.head) break;
    }

    // food
    if (!game.gameover) {
        c.glUniform3f(color_loc, 1.0, 0.2, 0.0);
        var translation = translateM3(2.0 * @intToFloat(f32, game.food_x) - @intToFloat(f32, W) + 1.0, 2.0 * @intToFloat(f32, game.food_y) - @intToFloat(f32, H) + 1.0);
        var transform = multiplyM3(translation, scale);
        c.glUniformMatrix3fv(transform_loc, 1, c.GL_FALSE, &transform[0]);
        c.glDrawArrays(c.GL_TRIANGLE_FAN, 3 * n, n);
    }

    c.SDL_GL_SwapWindow(sdl_window);
}

fn sdlEventWatch(userdata: ?*anyopaque, sdl_event: [*c]c.SDL_Event) callconv(.C) c_int {
    _ = userdata;
    if (sdl_event.*.type == c.SDL_WINDOWEVENT and
        sdl_event.*.window.event == c.SDL_WINDOWEVENT_RESIZED)
    {
        drawGame(1.0); // draw while resizing
        return 0; // handled
    }
    return 1;
}

pub fn main() !void {
    const video_width: i32 = 1024;
    const video_height: i32 = 640;

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLEBUFFERS, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLESAMPLES, 4);

    sdl_window = c.SDL_CreateWindow("Snake", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, video_width, video_height, c.SDL_WINDOW_OPENGL |
        c.SDL_WINDOW_RESIZABLE |
        c.SDL_WINDOW_ALLOW_HIGHDPI) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(sdl_window);

    const gl_context = c.SDL_GL_CreateContext(sdl_window); // TODO: handle error
    defer c.SDL_GL_DeleteContext(gl_context);

    if (builtin.os.tag == .windows or builtin.os.tag == .linux) {
        _ = gladLoadGL();
    }

    _ = c.SDL_GL_SetSwapInterval(1);

    c.SDL_AddEventWatch(sdlEventWatch, null);

    initGL();

    game.reset();
    game.gameover = true;
    var last_ticks = c.SDL_GetTicks();

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => quit = true,
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.sym == c.SDLK_ESCAPE) quit = true;
                    switch (event.key.keysym.sym) {
                        c.SDLK_UP => game.addNextDir(Direction.UP),
                        c.SDLK_DOWN => game.addNextDir(Direction.DOWN),
                        c.SDLK_RIGHT => game.addNextDir(Direction.RIGHT),
                        c.SDLK_LEFT => game.addNextDir(Direction.LEFT),
                        else => {},
                    }
                    if (c.SDL_GetTicks() - last_ticks > 500 and game.gameover) {
                        game.reset();
                        last_ticks = c.SDL_GetTicks();
                        game.tick();
                    }
                },
                else => {},
            }
        }

        var alpha: f32 = 1.0;
        if (!game.gameover) {
            const ticks = c.SDL_GetTicks();
            while (ticks >= last_ticks + 120) {
                game.tick();
                last_ticks += 120;
            }
            alpha = @intToFloat(f32, ticks - last_ticks) / 120.0;
        }
        if (game.gameover) alpha = 1.0;
        drawGame(alpha);
    }
}
