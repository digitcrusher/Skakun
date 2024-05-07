const std = @import("std");
const lua = @cImport({
  @cInclude("lauxlib.h");
  @cInclude("lualib.h");
});
const c = @cImport({
  @cInclude("curses.h");
  @cInclude("term.h");
});

// We sadly can't use luaL_checkstring and luaL_optstring because Zig errors out
// on them.

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
  .{ .name = "getflag", .func = @ptrCast(&getflag) },
  .{ .name = "getnum", .func = @ptrCast(&getnum) },
  .{ .name = "getstr", .func = @ptrCast(&getstr) },
  .{ .name = null, .func = null },
};

pub fn register(vm: *lua.lua_State) void {
  lua.luaL_register(vm, "core.terminfo", &funcs);
}
