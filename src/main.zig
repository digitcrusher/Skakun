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
const builtin = @import("builtin");
const build = @import("build");
const Editor = @import("buffer.zig").Editor;
const lua = @cImport({
  @cInclude("lauxlib.h");
  @cInclude("lualib.h");
});

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
  const allocator = gpa.allocator();

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

  {
    var editor = Editor.init(gpa.allocator());
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

  if(false) {
  const vm = lua.luaL_newstate() orelse return error.OutOfMemory;
  defer lua.lua_close(vm);
  lua.luaL_openlibs(vm);

  // I suspect this code may work only in Lua 5.1…
  lua.lua_getfield(vm, lua.LUA_REGISTRYINDEX, "_LOADED"); // Push _LOADED (the table of loaded modules) onto the stack
  lua.lua_newtable(vm); // Create a new table for our runtime variables and push it

  lua.lua_pushlstring(vm, build.version.ptr, build.version.len);
  lua.lua_setfield(vm, -2, "version");

  const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
  defer allocator.free(exe_dir);
  lua.lua_pushlstring(vm, exe_dir.ptr, exe_dir.len);
  lua.lua_setfield(vm, -2, "exe_dir");

  lua.lua_setfield(vm, -2, "core"); // Set _LOADED['core'] to our table and pop it
  lua.lua_pop(vm, 1); // Pop _LOADED

  try @import("core/tty/system.zig").register(vm);

  if(lua.luaL_dostring(
    vm,
    \\xpcall(
    \\  function()
    \\    local core = require('core')
    ++
    if(builtin.target.isDarwin())
      \\  -- There's also $HOME/Library/Preferences for Apple's proprietary
      \\  -- configuration file format ".plist".
      \\  core.config_dir = os.getenv('HOME') .. '/Library/Application Support/Skakun'
    else if(builtin.target.os.tag == .windows)
      \\  -- %APPDATA% differs from %LOCALAPPDATA% in that it is synced
      \\  -- across devices.
      \\  core.config_dir = os.getenv('APPDATA') .. '/Skakun'
    else
      \\  core.config_dir = os.getenv('XDG_CONFIG_HOME')
      \\  if core.config_dir then
      \\    core.config_dir = core.config_dir .. '/skakun'
      \\  else
      \\    core.config_dir = os.getenv('HOME') .. '/.config/skakun'
      \\  end
    ++
    \\    package.path = core.exe_dir .. '/../lib/skakun/?/init.lua;' .. package.path
    \\    package.path = core.exe_dir .. '/../lib/skakun/?.lua;' .. package.path
    \\    package.cpath = core.exe_dir .. '/../lib/skakun/?.so;' .. package.cpath
    \\    package.path = core.config_dir .. '/?/init.lua;' .. package.path
    \\    package.path = core.config_dir .. '/?.lua;' .. package.path
    \\    package.cpath = core.config_dir .. '/?.so;' .. package.cpath
    \\    require('user')
    \\  end,
    \\  function(err)
    \\    print(debug.traceback(err, 2))
    \\  end
    \\)
  )) {
    return error.LuaError;
  }
  }
}
