const std = @import("std");

pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  b.lib_dir = "zig-out/lib/skakun";

  const exe = b.addExecutable(.{
    .name = "skak",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
  });
  exe.linkLibC();
  exe.linkSystemLibrary("gio-2.0");
  exe.linkSystemLibrary("lua-5.1");
  exe.linkSystemLibrary("tinfo");

  b.installArtifact(exe);
  b.installDirectory(.{
    .source_dir = b.path("src"),
    .install_dir = .lib,
    .install_subdir = "",
    .include_extensions = &.{".lua"},
  });

  const run_cmd = b.addRunArtifact(exe);
  run_cmd.step.dependOn(b.getInstallStep());
  if(b.args) |args| {
    run_cmd.addArgs(args);
  }

  const run_step = b.step("run", "Run the app");
  run_step.dependOn(&run_cmd.step);
}
