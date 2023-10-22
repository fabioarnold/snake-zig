const std = @import("std");

const Self = @This();

pub const width = 25;
pub const height = 15;
const N = width * height;

var r = std.rand.DefaultPrng.init(4); // seed chosen by dice roll

pub const Direction = enum {
    up,
    down,
    left,
    right,

    pub fn opposite(self: Direction) Direction {
        return switch (self) {
            .up => .down,
            .down => .up,
            .left => .right,
            .right => .left,
        };
    }
};

const Snake = struct {
    nodes: [N]Node,
    head: usize,
    tail: usize,
    eaten: bool, // the snake has eaten during the current tick

    fn reset(self: *Snake) void {
        self.head = 1;
        self.tail = 0;
        self.nodes[self.tail] = Node.init(width / 2, height - 2, .down);
        self.nodes[self.head] = Node.init(width / 2, height - 3, .down);
        self.eaten = false;
    }

    pub fn length(self: Snake) usize {
        return ((self.head + N + 1) - self.tail) % N;
    }

    pub fn iter(self: *const Snake) Iter {
        return .{ .snake = self, .i = self.tail };
    }

    fn hitWall(self: Snake, dir: Direction) bool {
        const h = &self.nodes[self.head];
        return switch (dir) {
            .up => h.y == height - 1,
            .down => h.y == 0,
            .left => h.x == 0,
            .right => h.x == width - 1,
        };
    }

    fn moveHead(self: *Snake, dir: Direction) void {
        const h = &self.nodes[self.head];
        self.head = (self.head + 1) % N;
        self.nodes[self.head] = h.copyWithDir(dir);
    }

    fn biteTail(self: Snake) bool {
        const h = &self.nodes[self.head];
        var i: usize = self.tail;
        while (i != self.head) : (i = (i + 1) % N) {
            if (h.x == self.nodes[i].x and h.y == self.nodes[i].y) {
                return true;
            }
        }
        return false;
    }

    fn eat(self: *Snake, food_x: u16, food_y: u16) bool {
        const h = &self.nodes[self.head];
        self.eaten = h.x == food_x and h.y == food_y;
        return self.eaten;
    }

    fn moveTail(self: *Snake) void {
        self.tail = (self.tail + 1) % N;
    }

    const Node = struct {
        x: u16,
        y: u16,
        dir: Direction,

        pub fn init(x: u16, y: u16, dir: Direction) Node {
            return .{ .x = x, .y = y, .dir = dir };
        }

        fn copyWithDir(self: Node, dir: Direction) Node {
            return switch (dir) {
                .up => init(self.x, self.y + 1, dir),
                .down => init(self.x, self.y - 1, dir),
                .left => init(self.x - 1, self.y, dir),
                .right => init(self.x + 1, self.y, dir),
            };
        }
    };

    const Iter = struct {
        snake: *const Snake,
        i: usize,

        pub fn next(self: *Iter) ?Node {
            if (self.i == (self.snake.head + 1) % N) return null;
            const node = self.snake.nodes[self.i];
            self.i = (self.i + 1) % N;
            return node;
        }

        pub fn peek(self: Iter) ?Node {
            if (self.i == (self.snake.head + 1) % N) return null;
            return self.snake.nodes[self.i];
        }
    };
};

snake: Snake,

input: ?Direction,
queued_input: ?Direction,

food_x: u16,
food_y: u16,

gameover: bool,

pub fn reset(self: *Self) void {
    self.gameover = false;
    self.input = null;
    self.queued_input = null;
    self.snake.reset();
    self.placeFood();
}

fn onGameover(self: *Self) void {
    self.gameover = true;
    std.debug.print("snake length: {}\n", .{self.snake.length()});
}

fn placeFood(self: *Self) void {
    // mark occupied cells on a grid
    var grid = [_]bool{false} ** N;
    var it = self.snake.iter();
    while (it.next()) |node| {
        grid[width * node.y + node.x] = true;
    }
    // choose free cell index
    var f = r.random().uintLessThan(usize, N - self.snake.length());
    for (grid, 0..) |occupied, i| {
        if (occupied) continue;
        if (f == 0) {
            self.food_x = @intCast(i % width);
            self.food_y = @intCast(i / width);
            return;
        }
        f -= 1;
    }
}

pub fn tick(self: *Self) void {
    if (self.gameover) return;

    const dir = self.getNextInput();

    if (self.snake.hitWall(dir)) {
        self.onGameover();
        return;
    }

    self.snake.moveHead(dir);

    if (self.snake.biteTail()) {
        self.onGameover();
        return;
    }

    if (self.snake.eat(self.food_x, self.food_y)) {
        self.placeFood();
        // grow by not moving the tail
    } else {
        self.snake.moveTail();
    }
}

pub fn addNextInput(self: *Self, dir: Direction) void {
    if (self.input) |input| {
        if (self.queued_input == null and dir != input) {
            self.queued_input = dir;
        }
    } else {
        self.input = dir;
    }
}

fn getNextInput(self: *Self) Direction {
    const h = &self.snake.nodes[self.snake.head];
    const dir = self.input orelse h.dir;
    self.input = self.queued_input;
    self.queued_input = null;
    if (dir == h.dir.opposite()) return h.dir;
    return dir;
}
