const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sdl_prefix = b.option([]const u8, "sdl-prefix", "Homebrew prefix for SDL2") orelse "/opt/homebrew";
    const mupdf_jobs = b.option(u32, "mupdf-jobs", "Parallelism for the vendored MuPDF build") orelse 4;

    const mupdf_build = b.addSystemCommand(&.{
        "make",
        "-C",
        "mupdf",
        "HAVE_GLUT=no",
        b.fmt("-j{d}", .{mupdf_jobs}),
        "libs",
    });

    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "sioyek",
        .root_module = module,
    });
    exe.step.dependOn(&mupdf_build.step);
    exe.linkLibC();
    exe.linkLibCpp();

    exe.addIncludePath(b.path("src/c"));
    exe.addIncludePath(b.path("mupdf/include"));
    exe.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include/SDL2", .{sdl_prefix}) });
    exe.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{sdl_prefix}) });
    exe.addRPath(.{ .cwd_relative = b.fmt("{s}/lib", .{sdl_prefix}) });

    exe.addCSourceFile(.{
        .file = b.path("src/c/mupdf_wrapper.c"),
        .flags = &.{
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Wno-unused-parameter",
        },
    });

    exe.addObjectFile(b.path("mupdf/build/release/libmupdf.a"));
    exe.addObjectFile(b.path("mupdf/build/release/libmupdf-third.a"));

    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("m");
    exe.linkSystemLibrary("z");
    exe.linkSystemLibrary("bz2");

    if (target.result.os.tag == .macos) {
        exe.linkFramework("AppKit");
        exe.linkFramework("ApplicationServices");
        exe.linkFramework("CoreFoundation");
        exe.linkFramework("CoreGraphics");
        exe.linkFramework("CoreVideo");
        exe.linkFramework("Foundation");
        exe.linkFramework("IOKit");
        exe.linkFramework("Metal");
        exe.linkFramework("QuartzCore");
        exe.linkFramework("Security");
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Build and run the Zig rewrite");
    run_step.dependOn(&run_cmd.step);
}
