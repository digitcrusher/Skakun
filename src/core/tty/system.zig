const std = @import("std");
const lua = @cImport({
  @cInclude("lauxlib.h");
  @cInclude("lualib.h");
});
const c = @cImport({
  @cInclude("curses.h");
  @cInclude("stdlib.h");
  @cInclude("term.h");
  @cInclude("termios.h");
});

var original_termios: ?std.posix.termios = null;
var has_registered_cleanup = false;

fn cleanup() callconv(.C) void {
  if(original_termios) |x| {
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, x) catch {};
    original_termios = null;
  }
}

fn enable_raw_mode(vm: *lua.lua_State) callconv(.C) c_int {
  if(original_termios == null) {
    var termios = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch |err| return lua.luaL_error(vm, "failed to get original termios: %s", @errorName(err).ptr);
    original_termios = termios;

    // Further reading:
    // - https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
    // - man 5 cfmakeraw
    c.cfmakeraw(@ptrCast(&termios));
    termios.cc[@intFromEnum(std.posix.V.MIN)] = 0;
    termios.cc[@intFromEnum(std.posix.V.TIME)] = 1; // Read timeout: 100ms
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, termios) catch |err| return lua.luaL_error(vm, "failed to set raw termios: %s", @errorName(err).ptr);

    if(!has_registered_cleanup) {
      has_registered_cleanup = c.atexit(cleanup) == 0; // This may fail, which is a minor annoyance.
    }
  }
  return 0;
}

fn disable_raw_mode(vm: *lua.lua_State) callconv(.C) c_int {
  if(original_termios) |x| {
    std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, x) catch |err| return lua.luaL_error(vm, "failed to set original termios: %s", @errorName(err).ptr);
    original_termios = null;
  }
  return 0;
}

// We sadly can't use luaL_checkstring and luaL_optstring because Zig errors out on them.

fn getflag(vm: *lua.lua_State) callconv(.C) c_int {
  const capname = lua.luaL_checklstring(vm, 1, null) orelse return lua.luaL_typerror(vm, 1, lua.lua_typename(vm, lua.LUA_TSTRING));
  const term = if(lua.lua_isnoneornil(vm, 2)) null else lua.luaL_checklstring(vm, 2, null) orelse return lua.luaL_typerror(vm, 2, lua.lua_typename(vm, lua.LUA_TSTRING));

  const old = c.cur_term;
  std.debug.assert(c.setupterm(term, 0, null) == c.OK);
  defer {
    std.debug.assert(c.del_curterm(c.cur_term) == c.OK);
    _ = c.set_curterm(old);
  }

  switch(c.tigetflag(capname)) {
    -1 => lua.lua_pushnil(vm),
    0 => lua.lua_pushboolean(vm, 0),
    else => lua.lua_pushboolean(vm, 1),
  }
  return 1;
}

fn getnum(vm: *lua.lua_State) callconv(.C) c_int {
  const capname = lua.luaL_checklstring(vm, 1, null) orelse return lua.luaL_typerror(vm, 1, lua.lua_typename(vm, lua.LUA_TSTRING));
  const term = if(lua.lua_isnoneornil(vm, 2)) null else lua.luaL_checklstring(vm, 2, null) orelse return lua.luaL_typerror(vm, 2, lua.lua_typename(vm, lua.LUA_TSTRING));

  const old = c.cur_term;
  std.debug.assert(c.setupterm(term, 0, null) == c.OK);
  defer {
    std.debug.assert(c.del_curterm(c.cur_term) == c.OK);
    _ = c.set_curterm(old);
  }

  switch(c.tigetnum(capname)) {
    -2 => lua.lua_pushnil(vm),
    -1 => lua.lua_pushboolean(vm, 0),
    else => |x| lua.lua_pushinteger(vm, x),
  }
  return 1;
}

fn getstr(vm: *lua.lua_State) callconv(.C) c_int {
  const capname = lua.luaL_checklstring(vm, 1, null) orelse return lua.luaL_typerror(vm, 1, lua.lua_typename(vm, lua.LUA_TSTRING));
  const term = if(lua.lua_isnoneornil(vm, 2)) null else lua.luaL_checklstring(vm, 2, null) orelse return lua.luaL_typerror(vm, 2, lua.lua_typename(vm, lua.LUA_TSTRING));

  const old = c.cur_term;
  std.debug.assert(c.setupterm(term, 0, null) == c.OK);
  defer {
    std.debug.assert(c.del_curterm(c.cur_term) == c.OK);
    _ = c.set_curterm(old);
  }

  const result = c.tigetstr(capname);
  switch(@as(isize, @bitCast(@intFromPtr(result)))) {
    -1 => lua.lua_pushnil(vm),
    0 => lua.lua_pushboolean(vm, 0),
    else => lua.lua_pushstring(vm, result),
  }
  return 1;
}

const funcs = [_]lua.luaL_Reg{
  .{ .name = "enable_raw_mode", .func = @ptrCast(&enable_raw_mode) },
  .{ .name = "disable_raw_mode", .func = @ptrCast(&disable_raw_mode) },
  .{ .name = "getflag", .func = @ptrCast(&getflag) },
  .{ .name = "getnum", .func = @ptrCast(&getnum) },
  .{ .name = "getstr", .func = @ptrCast(&getstr) },
  .{ .name = null, .func = null },
};

pub fn register(vm: *lua.lua_State) !void {
  lua.luaL_register(vm, "core.tty.system", &funcs);
  if(lua.luaL_dostring(
    vm,
    \\ local tty = require('core.tty.system')
    \\ tty.write = io.write
    \\ tty.flush = io.flush
    \\ function tty.read(count)
    \\   return io.read(count or '*a') or ''
    \\ end
    \\ local _enable = tty.enable_raw_mode
    \\ function tty.enable_raw_mode()
    \\   _enable()
    \\   io.stdout:setvbuf('full') -- Crank up boring line buffering to rad full buffering
    \\ end
    \\ local _disable = tty.disable_raw_mode
    \\ function tty.disable_raw_mode()
    \\   io.stdout:setvbuf('line') -- And back to lame line buffering again…
    \\   _disable()
    \\ end
  )) {
    return error.LuaError;
  }
}
