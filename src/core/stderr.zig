// Skakun - A robust and hackable hex and text editor
// Copyright (C) 2024-2025 Karol "digitcrusher" Łacina
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
const lua = @import("ziglua");
const c = @cImport(@cInclude("unistd.h"));
const assert = std.debug.assert;
const posix = std.posix;

var original_fd: ?posix.fd_t = null;

fn redirect(vm: *lua.Lua) i32 {
  if(original_fd != null) return 0;

  assert(vm.getSubtable(lua.registry_index, "_LOADED"));
  assert(vm.getSubtable(-1, "core.stderr"));
  _ = vm.getField(-1, "path");
  const path = vm.checkString(-1);
  vm.pop(3);

  std.fs.cwd().makePath(std.fs.path.dirname(path) orelse ".") catch |err| vm.raiseErrorStr("failed to create enclosing directories: %s", .{@errorName(err).ptr});
  const new_fd = posix.openZ(path, .{ .ACCMODE = .WRONLY, .APPEND = true, .CREAT = true, .TRUNC = true }, std.fs.File.default_mode) catch |err| vm.raiseErrorStr("failed to open stderr file: %s", .{@errorName(err).ptr});
  original_fd = posix.dup(posix.STDERR_FILENO) catch |err| {
    posix.close(new_fd);
    vm.raiseErrorStr("failed to save original stderr: %s", .{@errorName(err).ptr});
  };
  posix.dup2(new_fd, posix.STDERR_FILENO) catch |err| {
    posix.close(original_fd.?);
    original_fd = null;
    posix.close(new_fd);
    vm.raiseErrorStr("failed to replace stderr: %s", .{@errorName(err).ptr});
  };

  return 0;
}

fn restore(vm: *lua.Lua) i32 {
  if(original_fd) |x| {
    posix.dup2(x, posix.STDERR_FILENO) catch |err| vm.raiseErrorStr("%s", .{@errorName(err).ptr});
    posix.close(x);
    original_fd = null;
  }
  return 0;
}

const funcs = [_]lua.FnReg{
  .{ .name = "redirect", .func = lua.wrap(redirect) },
  .{ .name = "restore", .func = lua.wrap(restore) },
};

pub fn luaopen(vm: *lua.Lua) i32 {
  const allocator = vm.allocator();
  vm.newLib(&funcs);

  const env_var = if(builtin.os.tag == .windows)
      "TEMP" // %TEMP%, unlike %LOCALAPPDATA%, is periodically cleaned by the system.
    else if(builtin.os.tag.isDarwin())
      "HOME"
    else
      "XDG_RUNTIME_DIR"; // I'm not even sure, if this is the right place.
  const base_dir = std.process.getEnvVarOwned(allocator, env_var) catch unreachable;
  defer allocator.free(base_dir);

  const path = std.fmt.allocPrintZ(
    allocator,
    if(builtin.os.tag == .windows)
      "{s}\\Skakun\\{}.log"
    else if(builtin.os.tag.isDarwin())
      "{s}/Library/Logs/Skakun/{}.log" // I absolutely adore this.
    else
      "{s}/skakun/{}.log",
    .{base_dir, c.getpid()},
  ) catch unreachable;
  defer allocator.free(path);

  _ = vm.pushString(path);
  vm.setField(-2, "path");

  vm.loadString(
    \\local stderr = ...
    \\function stderr.log(level, where, ...)
    \\  io.stderr:write(level, ' ', tostring(where), ': ')
    \\  local args = table.pack(...)
    \\  for i = 1, args.n do
    \\    io.stderr:write(tostring(args[i]))
    \\  end
    \\  io.stderr:write('\n')
    \\end
    \\function stderr.error(where, ...) stderr.log('error', where, ...) end
    \\function stderr.warn(where, ...) stderr.log('warn', where, ...) end
    \\function stderr.info(where, ...) stderr.log('info', where, ...) end
  ) catch unreachable;
  vm.pushValue(-2);
  vm.call(.{ .args = 1, .results = 0 });

  return 1;
}
