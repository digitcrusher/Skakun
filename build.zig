const std = @import("std");

pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});

  const exe = b.addExecutable(.{
    .name = "skak",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
  });
  exe.root_module.addImport("ziglua", b.dependency("ziglua", .{
    .target = target,
    .optimize = optimize,
  }).module("ziglua"));
  exe.linkLibC();
  exe.linkSystemLibrary(if(target.result.os.tag == .linux) "gio-unix-2.0" else "gio-2.0");
  exe.linkSystemLibrary("tinfo");

  const libgrapheme = b.dependency("libgrapheme", .{
    .target = target,
    .optimize = optimize,
  });
  std.fs.accessAbsolute(libgrapheme.path("libgrapheme.a").getPath(b), .{}) catch {
    const configure = b.addSystemCommand(&.{"./configure"});
    configure.setCwd(libgrapheme.path(""));
    const make = b.addSystemCommand(&.{"make"});
    make.setCwd(libgrapheme.path(""));
    make.step.dependOn(&configure.step);
    exe.step.dependOn(&make.step);
  };
  exe.addLibraryPath(libgrapheme.path(""));
  exe.linkSystemLibrary("grapheme");
  exe.addIncludePath(libgrapheme.path(""));

  var version: []const u8 = undefined;
  if(b.option([]const u8, "version", "Application version string")) |x| {
    version = x;
  } else {
    const latest_commit = std.mem.trim(u8, b.run(&.{"git", "rev-parse", "--short", "HEAD"}), &std.ascii.whitespace);
    var git_output = std.mem.tokenizeAny(u8, b.run(&.{"git", "tag", "--sort=-v:refname"}), &std.ascii.whitespace);
    if(git_output.next()) |version_tag| {
      version = std.mem.trimLeft(u8, version_tag, "v");

      var exit_code: u8 = undefined;
      _ = b.runAllowFail(&.{"git", "diff", "--quiet", version_tag}, &exit_code, .Inherit) catch |err| if(err != error.ExitCodeFailure) {
        std.log.err("failed to git diff last version: {}", .{err});
        std.process.exit(1);
      };
      if(exit_code != 0) {
        version = std.mem.concat(b.allocator, u8, &.{version, "-dirty+", latest_commit}) catch @panic("OOM");
      }
    } else {
      version = std.mem.concat(b.allocator, u8, &.{"0.0.0+", latest_commit}) catch @panic("OOM");
    }
  }
  const options = b.addOptions();
  options.addOption([]const u8, "version", version);
  exe.root_module.addOptions("build", options);

  b.installArtifact(exe);
  b.lib_dir = "zig-out/lib/skakun";
  b.installDirectory(.{
    .source_dir = b.path("src"),
    .install_dir = .lib,
    .install_subdir = "",
    .include_extensions = &.{".lua"},
  });
  b.installDirectory(.{
    .source_dir = b.path("doc"),
    .install_dir = .{ .custom = "doc/skakun" },
    .install_subdir = "",
  });

  var run = b.addRunArtifact(exe);
  if(b.option([]const u8, "term", "The terminal to run the app in")) |term| {
    if(std.mem.eql(u8, term, "gnome-terminal")) {
      run = b.addSystemCommand(&.{"gnome-terminal", "--", "sh", "-c", "./zig-out/bin/skak \"$@\"; sh", ""});
    } else if(std.mem.eql(u8, term, "kitty")) {
      run = b.addSystemCommand(&.{"kitty", "--hold"});
      run.addArtifactArg(exe);
    } else if(std.mem.eql(u8, term, "konsole")) {
      run = b.addSystemCommand(&.{"konsole", "--hold", "-e"});
      run.addArtifactArg(exe);
    } else if(std.mem.eql(u8, term, "st")) {
      run = b.addSystemCommand(&.{"st", "-e", "sh", "-c", "./zig-out/bin/skak \"$@\"; sh", ""});
    } else if(std.mem.eql(u8, term, "xfce4-terminal")) {
      run = b.addSystemCommand(&.{"xfce4-terminal", "--hold", "-x"});
      run.addArtifactArg(exe);
    } else if(std.mem.eql(u8, term, "xterm")) {
      run = b.addSystemCommand(&.{"xterm", "-hold", "-e"});
      run.addArtifactArg(exe);
    } else {
      std.log.err("unknown terminal: {s}", .{term});
      std.process.exit(1);
    }
  }
  run.step.dependOn(b.getInstallStep());
  if(b.args) |args| {
    run.addArgs(args);
  }

  const run_step = b.step("run", "Run the app");
  run_step.dependOn(&run.step);
}
