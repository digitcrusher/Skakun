// Skakun - A robust and hackable hex and text editor
// Copyright (C) 2024 Karol "digitcrusher" Łacina
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const target = @import("builtin").target;
const build = @import("build");
const Editor = @import("buffer.zig").Editor;
const lua = @import("ziglua");

const glyphs = [256]?[]const u8{
  "␀", "␁", "␂", "␃", "␄", "␅", "␆", "␇", "␈", "␉", "␊", "␋", "␌", "␍", "␎", "␏",
  "␐", "␑", "␒", "␓", "␔", "␕", "␖", "␗", "␘", "␙", "␚", "␛", "␜", "␝", "␞", "␟",
  null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null,
  null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null,
  null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null,
  null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null,
  null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null,
  null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, "␡",
  "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·",
  "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·",
  "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·",
  "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·",
  "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·",
  "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·",
  "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·",
  "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·", "·",
};

pub fn main() !void {
  // for(0..256) |char| {
  //   if(glyphs[char]) |s| {
  //     std.debug.print("{s}", .{s});
  //   } else {
  //     std.debug.print("{c}", .{@as(u8, @intCast(char))});
  //   }
  //   if(char % 16 == 15) {
  //     std.debug.print("\n", .{});
  //   }
  // }

  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  defer _ = gpa.deinit();
  var allocator = gpa.allocator();

  const args = try std.process.argsAlloc(allocator);
  defer std.process.argsFree(allocator, args);

  if(args.len >= 2 and std.mem.eql(u8, args[1], "--version")) {
    try std.io.getStdOut().writeAll(std.fmt.comptimePrint(
      \\Skakun {s}
      \\Copyright (C) 2024 Karol "digitcrusher" Łacina
      \\This program comes with ABSOLUTELY NO WARRANTY.
      \\This is free software, and you are welcome to redistribute it
      \\under certain conditions; see the source for copying conditions.
      \\
    , .{build.version}));
    return;
  }

  if(false) {
    var editor = Editor.init(gpa.allocator());
    editor.max_load_size = 0;
    defer editor.deinit();

    var err_msg: ?[]u8 = null;
    var buffer = editor.open(args[1], &err_msg) catch |err| {
      if(err_msg) |x| {
        defer editor.allocator.free(x);
        std.debug.print("{s}: {s}\n", .{@errorName(err), x});
      } else {
        std.debug.print("{s}\n", .{@errorName(err)});
      }
      std.process.exit(1);
    };
    defer buffer.destroy();

    //try buffer.insert(28, "- Wyłącz komputer i pójdź do psychologa.\n");
    //try buffer.delete(73, 1274);

    var buf: [1000]u8 = undefined;
    const data = buf[0 .. try buffer.read(0, &buf)];
    for(data) |*x| {
      x.* = if(std.ascii.isLower(x.*)) std.ascii.toUpper(x.*) else std.ascii.toLower(x.*);
    }
    try buffer.delete(0, data.len);
    try buffer.insert(0, data);

    try buffer.copy(200, buffer, 0, 100);
    try buffer.delete(0, 100);

    try buffer.load();

    const start = std.time.timestamp();
    while(std.time.timestamp() - start <= 10) {
      editor.check_fs_events();
    }

    buffer.save(args[2], &err_msg) catch |err| {
      if(err_msg) |x| {
        defer editor.allocator.free(x);
        std.debug.print("{s}: {s}\n", .{@errorName(err), x});
      } else {
        std.debug.print("{s}\n", .{@errorName(err)});
      }
      std.process.exit(1);
    };
  }

  _ = gpa.detectLeaks();

  if(true) {
  const vm = try lua.Lua.init(&allocator);
  defer vm.deinit();
  vm.openLibs();

  try vm.getSubtable(lua.registry_index, "_LOADED");
  vm.getSubtable(-1, "core") catch {};

  _ = vm.pushString(build.version);
  vm.setField(-2, "version");

  const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
  defer allocator.free(exe_dir);
  _ = vm.pushString(exe_dir);
  vm.setField(-2, "exe_dir");

  if(target.os.tag == .linux) {
    _ = vm.pushString("linux");
  } else if(target.os.tag == .windows) {
    _ = vm.pushString("windows");
  } else if(target.isDarwin()) {
    _ = vm.pushString("macos");
  } else if(target.isBSD()) {
    _ = vm.pushString("freebsd");
  } else {
    vm.pushNil();
  }
  vm.setField(-2, "platform");

  vm.requireF("core.tty.system", lua.wrap(@import("core/tty/system.zig").luaopen), false);
  if(target.os.tag == .linux) {
    vm.requireF("core.tty.linux.system", lua.wrap(@import("core/tty/linux/system.zig").luaopen), false);
  } else if(target.os.tag == .windows) {
    vm.requireF("core.tty.windows", lua.wrap(@import("core/tty/windows.zig").luaopen), false);
  } else if(target.isBSD()) {
    vm.requireF("core.tty.freebsd.system", lua.wrap(@import("core/tty/freebsd/system.zig").luaopen), false);
  }

  try vm.doString(
    \\local core = require('core')
    \\function core.cleanup() end
    \\xpcall(
    \\  function()
    \\    if core.platform == 'windows' then
    \\      -- %APPDATA% differs from %LOCALAPPDATA% in that it is synced
    \\      -- across devices.
    \\      core.config_dir = os.getenv('APPDATA') .. '\\Skakun'
    \\    elseif core.platform == 'macos' then
    \\      -- There's also $HOME/Library/Preferences for Apple's proprietary
    \\      -- configuration file format ".plist".
    \\      core.config_dir = os.getenv('HOME') .. '/Library/Application Support/Skakun'
    \\    else
    \\      core.config_dir = os.getenv('XDG_CONFIG_HOME')
    \\      if core.config_dir then
    \\        core.config_dir = core.config_dir .. '/skakun'
    \\      else
    \\        core.config_dir = os.getenv('HOME') .. '/.config/skakun'
    \\      end
    \\    end
    \\    package.path = core.exe_dir .. '/../lib/skakun/?/init.lua;' .. package.path
    \\    package.path = core.exe_dir .. '/../lib/skakun/?.lua;' .. package.path
    \\    package.cpath = core.exe_dir .. '/../lib/skakun/?.so;' .. package.cpath
    \\    package.path = core.config_dir .. '/?/init.lua;' .. package.path
    \\    package.path = core.config_dir .. '/?.lua;' .. package.path
    \\    package.cpath = core.config_dir .. '/?.so;' .. package.cpath
    \\    require('user')
    \\    core.cleanup()
    \\  end,
    \\  function(err)
    \\    pcall(core.cleanup)
    \\    print(debug.traceback(err, 2))
    \\    os.exit(1)
    \\  end
    \\)
  );
  }
}
