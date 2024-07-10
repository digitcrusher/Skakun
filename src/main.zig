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
const lua = @import("ziglua");
const c = @cImport(@cInclude("stdlib.h"));

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator(); // This would reference a stack variable, were it in main.
var vm: *lua.Lua = undefined;

fn cleanup() callconv(.C) void {
  // The initial comments in doString's improve stack trace legibility.
  vm.doString(
    \\-- cleanup() in main.zig
    \\local core = require('core')
    \\local errors = {}
    \\for i = #core.cleanups, 1, -1 do
    \\  local func = core.cleanups[i]
    \\  -- Removing from the list before calling prevents any mischievous
    \\  -- function from causing an exit loop.
    \\  core.cleanups[i] = nil
    \\  xpcall(func, function(err)
    \\    errors[#errors + 1] = debug.traceback(err, 2)
    \\  end)
    \\end
    \\for _, error in ipairs(errors) do
    \\  io.stderr:write(error, '\n')
    \\end
    \\if #errors > 0 then
    \\  io.stderr:write('Some errors occurred during cleanup.\n')
    \\end
  ) catch unreachable;
  vm.deinit();
  _ = gpa.deinit();
}

pub fn main() !void {
  vm = try lua.Lua.init(&allocator);
  vm.openLibs();

  try vm.getSubtable(lua.registry_index, "_LOADED");
  vm.getSubtable(-1, "core") catch {};

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

  // By putting args and exe_dir in code blocks, we ensure that the deferred
  // deallocations really run and aren't bypassed by a call to os.exit, so that
  // the allocator doesn't spew out unnecessary memory leak warnings in cleanup.
  {
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

    vm.createTable(@intCast(args.len), 0);
    for(args, 1 ..) |arg, i| {
      _ = vm.pushString(arg);
      vm.setIndex(-2, @intCast(i));
    }
    vm.setField(-2, "args");
  }

  _ = vm.pushString(build.version);
  vm.setField(-2, "version");

  {
    const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_dir);
    _ = vm.pushString(exe_dir);
    vm.setField(-2, "exe_dir");
  }

  try vm.doString(
    \\xpcall(
    \\  function()
    \\    local core = require('core')
    \\    core.cleanups = {}
    \\    function core.add_cleanup(func)
    \\      core.cleanups[#core.cleanups + 1] = func
    \\    end
    \\    if core.platform == 'windows' then
    \\      -- %APPDATA% differs from %LOCALAPPDATA% in that it is synced
    \\      -- across devices.
    \\      core.config_dir = os.getenv('APPDATA') .. '\\Skakun'
    \\    elseif core.platform == 'macos' then
    \\      -- There's also $HOME/Library/Preferences for Apple's proprietary
    \\      -- configuration file format ".plist".
    \\      core.config_dir = os.getenv('HOME') .. '/Library/Application Support/Skakun'
    \\    else
    \\      core.config_dir = (os.getenv('XDG_CONFIG_HOME') or os.getenv('HOME') .. '/.config') .. '/skakun'
    \\    end
    \\    package.path = core.exe_dir .. '/../lib/skakun/?/init.lua;' .. package.path
    \\    package.path = core.exe_dir .. '/../lib/skakun/?.lua;' .. package.path
    \\    package.cpath = core.exe_dir .. '/../lib/skakun/?.so;' .. package.cpath
    \\    package.path = core.config_dir .. '/?/init.lua;' .. package.path
    \\    package.path = core.config_dir .. '/?.lua;' .. package.path
    \\    package.cpath = core.config_dir .. '/?.so;' .. package.cpath
    \\  end,
    \\  function(err)
    \\    -- The depth has to be 1 here for some reason.
    \\    io.stderr:write(debug.traceback(err), '\n')
    \\    os.exit(1)
    \\  end
    \\)
  );
  std.debug.assert(c.atexit(cleanup) == 0);

  vm.requireF("core.buffer", lua.wrap(@import("core/buffer.zig").luaopen), false);
  vm.requireF("core.stderr", lua.wrap(@import("core/stderr.zig").luaopen), false);
  vm.requireF("core.tty.system", lua.wrap(@import("core/tty/system.zig").luaopen), false);
  if(target.os.tag == .linux) {
    vm.requireF("core.tty.linux.system", lua.wrap(@import("core/tty/linux/system.zig").luaopen), false);
  } else if(target.os.tag == .windows) {
    vm.requireF("core.tty.windows", lua.wrap(@import("core/tty/windows.zig").luaopen), false);
  } else if(target.isBSD()) {
    vm.requireF("core.tty.freebsd.system", lua.wrap(@import("core/tty/freebsd/system.zig").luaopen), false);
  }

  try vm.doString(
    \\-- main() in main.zig
    \\local core = require('core')
    \\xpcall(require, function(err)
    \\  for i = #core.cleanups, 1, -1 do
    \\    local func = core.cleanups[i]
    \\    core.cleanups[i] = nil
    \\    pcall(func)
    \\  end
    \\  io.stderr:write(debug.traceback(err, 2), '\n')
    \\  os.exit(1)
    \\end, 'user')
  );
}
