const std = @import("std");

pub fn build(b: *std.Build) void {
  const exe = b.addExecutable(.{
    .name = "skak",
    .root_source_file = .{ .path = "main.zig" },
    .target = b.standardTargetOptions(.{}),
    .optimize = b.standardOptimizeOption(.{}),
  });
  b.installArtifact(exe);
  exe.linkLibC();
  exe.linkSystemLibrary("gio-2.0");
  exe.linkSystemLibrary("lua-5.1");


//"http://luarocks.org/manifests/peterbillam/terminfo-1.8-0.src.rock"
//"terminfo-1.8.tar.gz"
// TODO: beat zig's build system into submission

  const run_cmd = b.addRunArtifact(exe);
  run_cmd.step.dependOn(b.getInstallStep());
  if(b.args) |args| {
    run_cmd.addArgs(args);
  }

  const run_step = b.step("run", "Run the app");
  run_step.dependOn(&run_cmd.step);
}
