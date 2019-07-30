const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("snake", "src/main.zig");
    exe.setBuildMode(mode);
    //exe.addIncludeDir("/usr/local/include/SDL2");
    exe.linkSystemLibrary("SDL2");
    exe.linkFramework("OpenGL");
    exe.linkSystemLibrary("c");

    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);

    const run_cmd = exe.run();

    const run_step = b.step("run", "Run snake");
    run_step.dependOn(&run_cmd.step);
    run_step.dependOn(&exe.step);
}