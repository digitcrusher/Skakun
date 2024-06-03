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
// We sadly can't use luaL_checkstring and luaL_optstring because Zig errors out on them.
const lua = @cImport({
  @cInclude("lauxlib.h");
  @cInclude("lualib.h");
});
const curses = @cImport({
  @cInclude("curses.h");
  @cInclude("term.h");
});
const c = @cImport({
  @cInclude("termios.h");
  if(builtin.target.isBSD()) {
    @cInclude("sys/consio.h");
    @cInclude("sys/kbio.h");
  } else if(builtin.target.os.tag == .linux) {
    @cInclude("linux/kd.h");
    @cInclude("linux/vt.h");
  }
});
const File = std.fs.File;
const posix = std.posix;

// man 2 ioctl_console

// The kbd project's source code was useful when writing this.

var is_open = false;
var file: if(builtin.target.os.tag == .windows) struct { in: File, out: File } else File = undefined;
var reader: File.Reader = undefined;
var writer: std.io.BufferedWriter(4096, File.Writer) = undefined;

fn open(vm: *lua.lua_State) callconv(.C) c_int {
  if(is_open) return lua.luaL_error(vm, "tty is already open");
  // We get hold of the controlling terminal directly, because stdin and stdout
  // might have been redirected to pipes.
  if(builtin.target.os.tag == .windows) {
    // On Windows we have the special device files "CONIN$", "CONOUT$" and
    // "CON". "CON" combines both input from and output to the terminal, which
    // is what we want. Thanks to backwards compatibility with MS-DOS, such
    // special names are actually symbolic links into the "\\.\" directory.
    // Moreover, we wouldn't even be able to open "CON" in Zig because it calls
    // directly into the NT api, and not Win32, and doesn't handle these special
    // devices when converting DOS paths to NT paths. Thus, we are left with
    // "\\.\CON".
    //
    // Oh wait, you don't know what the difference between DOS and NT paths is?
    // Well. Thanks to backwards compatibility again (this time with
    // Windows 9x), Windows NT has evolved two different systems of paths:
    // everyday "DOS" paths from the Win32 API and internal NT kernel paths. The
    // full path translation process is very complex and very clever, but in the
    // case of "\\.\CON", its canonical NT path is "\??\CON".
    //
    // But… "canonical" isn't the best term here since "\??" is in fact,
    // a symlink to "\DosDevices", if you haven't noticed by now.
    //
    // If we take the time to dig into Windows' internals (or just stumble upon
    // an interesting article on the Internet), we'll learn that since
    // Windows 8, the console subsystem has been served by the condrv.sys
    // driver, which places its working files in the NT directory
    // "\Device\ConDrv". I hope you can already see what's going on here…
    //
    // We can open NT paths with std.os.windows.OpenFile but that's clearly
    // a verbose, internal, low-level facility that we'd certainly like to
    // avoid. Thankfully, there is a solution! Due to a programming oversight,
    // NT paths starting with the "\??" directory are directly accessible from
    // the DOS path system, and the whole NT root directory is also symlinked as
    // "GLOBALROOT" in NT "\??", and "\\?\" is a version of "\\.\" bypassing the
    // path normalization process just like "\??\", and…
    //
    // Uhh, I think I've had enough… In some cases we can also suffix the
    // special device files with a colon, but I am too scared to proceed
    // further.
    //
    // Microsoft® Windows™ is truly a wonderful piece of software.
    //
    // Reference:
    // - https://googleprojectzero.blogspot.com/2016/02/the-definitive-guide-on-win32-to-nt.html
    // - https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/introduction-to-ms-dos-device-names
    // - https://github.com/rprichard/win32-console-docs#console-handles-modern
    // - https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
    // - https://learn.microsoft.com/en-us/sysinternals/downloads/winobj
    file.in  = std.fs.cwd().openFile("\\\\.\\CONIN$",  .{ .mode = .read_only  }) catch |err| return lua.luaL_error(vm, "failed to open CONIN$: %s", @errorName(err).ptr);
    file.out = std.fs.cwd().openFile("\\\\.\\CONOUT$", .{ .mode = .write_only }) catch |err| {
      file.in.close();
      return lua.luaL_error(vm, "failed to open CONOUT$: %s", @errorName(err).ptr);
    };
    // Yeah… uhh… it turns out CON can be opened with read or write access but not both…
    // Source: https://stackoverflow.com/questions/47534039/windows-console-handle-for-con-device#comment82036446_47534039
    reader = file.in.reader();
    writer = std.io.bufferedWriter(file.out.writer());
  } else {
    // Why "/dev/tty" exactly? Well, the answer is simple and well-documented
    // (unlike that other operating system):
    // - https://unix.stackexchange.com/q/60641
    // - https://tldp.org/HOWTO/Text-Terminal-HOWTO-7.html
    file = std.fs.cwd().openFile("/dev/tty", .{ .mode = .read_write }) catch |err| return lua.luaL_error(vm, "failed to open /dev/tty: %s", @errorName(err).ptr);
    reader = file.reader();
    writer = std.io.bufferedWriter(file.writer());
  }
  is_open = true;
  return 0;
}

fn close(_: *lua.lua_State) callconv(.C) c_int {
  if(!is_open) return 0;
  is_open = false;
  writer.flush() catch {};
  if(builtin.target.os.tag == .windows) {
    file.in.close();
    file.out.close();
  } else {
    file.close();
  }
  return 0;
}

fn write(vm: *lua.lua_State) callconv(.C) c_int {
  if(!is_open) return lua.luaL_error(vm, "tty is closed");
  for(1 .. @intCast(lua.lua_gettop(vm) + 1)) |arg_idx| {
    var string: []const u8 = undefined;
    string.ptr = lua.luaL_checklstring(vm, @intCast(arg_idx), &string.len) orelse return lua.luaL_typerror(vm, @intCast(arg_idx), lua.lua_typename(vm, lua.LUA_TSTRING));
    writer.writer().writeAll(string) catch |err| return lua.luaL_error(vm, "%s", @errorName(err).ptr);
  }
  return 0;
}

fn flush(vm: *lua.lua_State) callconv(.C) c_int {
  if(!is_open) return lua.luaL_error(vm, "tty is closed");
  writer.flush() catch |err| return lua.luaL_error(vm, "%s", @errorName(err).ptr);
  return 0;
}

fn read(vm: *lua.lua_State) callconv(.C) c_int {
  if(!is_open) return lua.luaL_error(vm, "tty is closed");

  lua.lua_getfield(vm, lua.LUA_REGISTRYINDEX, "*std.mem.Allocator");
  var allocator: *std.mem.Allocator = @alignCast(@ptrCast(lua.lua_touserdata(vm, -1) orelse unreachable));
  lua.lua_pop(vm, 1);

  const data = reader.readAllAlloc(allocator.*, 1_000_000) catch |err| return lua.luaL_error(vm, "%s", @errorName(err).ptr); // An arbitrary limit of 1MB
  defer allocator.free(data);

  lua.lua_pushlstring(vm, data.ptr, data.len);
  return 1;
}

var original_termios: ?posix.termios = null;
var original_kbmode: ?c_int = null; // The manpage incorrectly says this should be a long but does nicely inform us that we should rely on Linux's and FreeBSD's source code instead of it.

fn enable_raw_mode(vm: *lua.lua_State) callconv(.C) c_int {
  if(!is_open) return lua.luaL_error(vm, "tty is closed");

  if(original_termios == null) {
    var termios = posix.tcgetattr(file.handle) catch |err| return lua.luaL_error(vm, "failed to get original termios: %s", @errorName(err).ptr);
    original_termios = termios;

    // Further reading:
    // - https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
    // - man 3 cfmakeraw
    c.cfmakeraw(@ptrCast(&termios));
    termios.cc[@intFromEnum(posix.V.MIN)] = 0;
    termios.cc[@intFromEnum(posix.V.TIME)] = 1; // Read timeout: 100ms
    posix.tcsetattr(file.handle, .FLUSH, termios) catch |err| return lua.luaL_error(vm, "failed to set raw termios: %s", @errorName(err).ptr);
  }

  // if((builtin.target.isBSD() or builtin.target.os.tag == .linux) and original_kbmode == null) {
  //   if(std.c.ioctl(file.handle, c.KDGKBMODE, &original_kbmode) == 0) {
  //     if(std.c.ioctl(file.handle, c.KDSKBMODE, if(builtin.target.isBSD()) c.K_CODE else c.K_MEDIUMRAW) != 0) return lua.luaL_error(vm, );
  //   }
  // }

  return 0;
}

fn disable_raw_mode(vm: *lua.lua_State) callconv(.C) c_int {
  if(!is_open) return lua.luaL_error(vm, "tty is closed");

  if(original_termios) |x| {
    posix.tcsetattr(file.handle, .FLUSH, x) catch |err| return lua.luaL_error(vm, "failed to set original termios: %s", @errorName(err).ptr);
    original_termios = null;
  }

  // if(builtin.target.isBSD() or builtin.target.os.tag == .linux) {
  //   if(original_kbmode) |x| {
  //     if(std.os.linux.ioctl(file.handle, c.KDSKBMODE, original_kbmode) != 0) return lua.
  //     original_kbmode = null;
  //   }
  // }

  return 0;
}

fn getflag(vm: *lua.lua_State) callconv(.C) c_int {
  const capname = lua.luaL_checklstring(vm, 1, null) orelse return lua.luaL_typerror(vm, 1, lua.lua_typename(vm, lua.LUA_TSTRING));
  const term = if(lua.lua_isnoneornil(vm, 2)) null else lua.luaL_checklstring(vm, 2, null) orelse return lua.luaL_typerror(vm, 2, lua.lua_typename(vm, lua.LUA_TSTRING));

  const old = curses.cur_term;
  std.debug.assert(curses.setupterm(term, 0, null) == curses.OK);
  defer {
    std.debug.assert(curses.del_curterm(curses.cur_term) == curses.OK);
    _ = curses.set_curterm(old);
  }

  switch(curses.tigetflag(capname)) {
    -1 => lua.lua_pushnil(vm),
    0 => lua.lua_pushboolean(vm, 0),
    else => lua.lua_pushboolean(vm, 1),
  }
  return 1;
}

fn getnum(vm: *lua.lua_State) callconv(.C) c_int {
  const capname = lua.luaL_checklstring(vm, 1, null) orelse return lua.luaL_typerror(vm, 1, lua.lua_typename(vm, lua.LUA_TSTRING));
  const term = if(lua.lua_isnoneornil(vm, 2)) null else lua.luaL_checklstring(vm, 2, null) orelse return lua.luaL_typerror(vm, 2, lua.lua_typename(vm, lua.LUA_TSTRING));

  const old = curses.cur_term;
  std.debug.assert(curses.setupterm(term, 0, null) == curses.OK);
  defer {
    std.debug.assert(curses.del_curterm(curses.cur_term) == curses.OK);
    _ = curses.set_curterm(old);
  }

  switch(curses.tigetnum(capname)) {
    -2 => lua.lua_pushnil(vm),
    -1 => lua.lua_pushboolean(vm, 0),
    else => |x| lua.lua_pushinteger(vm, x),
  }
  return 1;
}

fn getstr(vm: *lua.lua_State) callconv(.C) c_int {
  const capname = lua.luaL_checklstring(vm, 1, null) orelse return lua.luaL_typerror(vm, 1, lua.lua_typename(vm, lua.LUA_TSTRING));
  const term = if(lua.lua_isnoneornil(vm, 2)) null else lua.luaL_checklstring(vm, 2, null) orelse return lua.luaL_typerror(vm, 2, lua.lua_typename(vm, lua.LUA_TSTRING));

  const old = curses.cur_term;
  std.debug.assert(curses.setupterm(term, 0, null) == curses.OK);
  defer {
    std.debug.assert(curses.del_curterm(curses.cur_term) == curses.OK);
    _ = curses.set_curterm(old);
  }

  const result = curses.tigetstr(capname);
  switch(@as(isize, @bitCast(@intFromPtr(result)))) {
    -1 => lua.lua_pushnil(vm),
    0 => lua.lua_pushboolean(vm, 0),
    else => lua.lua_pushstring(vm, result),
  }
  return 1;
}

// fn switch_console(vm: *lua.lua_State) callconv(.C) c_int {
//   ioctl(fd, c.VT_ACTIVATE,
//   return 0;
// }

const funcs = [_]lua.luaL_Reg{
  .{ .name = "open", .func = @ptrCast(&open) },
  .{ .name = "close", .func = @ptrCast(&close) },
  .{ .name = "write", .func = @ptrCast(&write) },
  .{ .name = "flush", .func = @ptrCast(&flush) },
  .{ .name = "read", .func = @ptrCast(&read) },
  .{ .name = "enable_raw_mode", .func = @ptrCast(&enable_raw_mode) },
  .{ .name = "disable_raw_mode", .func = @ptrCast(&disable_raw_mode) },
  .{ .name = "getflag", .func = @ptrCast(&getflag) },
  .{ .name = "getnum", .func = @ptrCast(&getnum) },
  .{ .name = "getstr", .func = @ptrCast(&getstr) },
  .{ .name = null, .func = null },
};

pub fn register(vm: *lua.lua_State) !void {
  lua.luaL_register(vm, "core.tty.system", &funcs);
}
