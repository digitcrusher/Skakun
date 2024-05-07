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

  b.installArtifact(exe);
  b.installDirectory(.{
    .source_dir = b.path("src"),
    .install_dir = .lib,
    .install_subdir = "",
    .include_extensions = &.{".lua"},
  });

  const terminfo_download = b.addSystemCommand(&.{"./download.sh"});
  terminfo_download.setCwd(b.path("external"));

  const terminfo = b.addSharedLibrary(.{
    .name = "C-terminfo",
    .target = target,
    .optimize = optimize,
  });
  terminfo.addCSourceFile(.{ .file = b.path("external/terminfo-1.8/C-terminfo.c") });
  terminfo.step.dependOn(&terminfo_download.step);
  terminfo.linkSystemLibrary("lua-5.1");
  terminfo.linkSystemLibrary("tinfo");

  const terminfo_install1 = b.addInstallArtifact(terminfo, .{ .dest_sub_path = "C-terminfo.so" });
  b.getInstallStep().dependOn(&terminfo_install1.step);

  const terminfo_install2 = b.addInstallLibFile(b.path("external/terminfo-1.8/terminfo.lua"), "terminfo.lua");
  terminfo_install2.step.dependOn(&terminfo_download.step);
  b.getInstallStep().dependOn(&terminfo_install2.step);

  const run_cmd = b.addRunArtifact(exe);
  run_cmd.step.dependOn(b.getInstallStep());
  if(b.args) |args| {
    run_cmd.addArgs(args);
  }

  const run_step = b.step("run", "Run the app");
  run_step.dependOn(&run_cmd.step);
}
