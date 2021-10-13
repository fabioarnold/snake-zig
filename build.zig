const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("snake", "src/main.zig");
    exe.setBuildMode(mode);
    if (exe.target.isWindows()) {
        try exe.addVcpkgPaths(.dynamic);
        if (exe.vcpkg_bin_path) |path| {
            const sdl2dll_path = try std.fs.path.join(b.allocator, &[_][]const u8{ path, "SDL2.dll" });
            b.installBinFile(sdl2dll_path, "SDL2.dll");
        }
        exe.subsystem = .Windows;
        exe.linkSystemLibrary("Shell32");
    }
    exe.addIncludeDir("src/c");
    exe.addIncludeDir("lib/gl2/include");
    exe.addCSourceFile("src/c/gl2_impl.c", &[_][]const u8{ "-std=c99", "-D_CRT_SECURE_NO_WARNINGS", "-Ilib/gl2/include" });
    if (exe.target.isDarwin()) {
        exe.linkFramework("OpenGL");
    } else if (exe.target.isWindows()) {
        exe.linkSystemLibrary("opengl32");
    } else {
        exe.linkSystemLibrary("gl");
    }
    exe.linkSystemLibrary("SDL2");
    exe.linkLibC();
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run snake");
    run_step.dependOn(&run_cmd.step);

    if (exe.target.isWindows()) {
        const outputresource = try std.mem.join(b.allocator, "", &[_][]const u8{"-outputresource:", "zig-cache\\bin\\", exe.out_filename, ";1"});
        const mt_exe = "C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.18362.0\\x64\\mt.exe";
        const manifest_cmd = b.addSystemCommand(&[_][]const u8{ mt_exe, "-manifest", "app.manifest", outputresource });
        manifest_cmd.step.dependOn(b.getInstallStep());
        const manifest_step = b.step("manifest", "Embed manifest");
        manifest_step.dependOn(&manifest_cmd.step);
        run_cmd.step.dependOn(&manifest_cmd.step);
    }
}
