const std = @import("std");
const lua = @cImport({
  @cInclude("lauxlib.h");
  @cInclude("lualib.h");
});
const c = @cImport({
  @cInclude("stdlib.h");
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
    termios.cc[@intFromEnum(std.posix.V.TIME)] = 1;
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

const funcs = [_]lua.luaL_Reg{
  .{ .name = "enable_raw_mode", .func = @ptrCast(&enable_raw_mode) },
  .{ .name = "disable_raw_mode", .func = @ptrCast(&disable_raw_mode) },
  .{ .name = null, .func = null },
};

pub fn register(vm: *lua.lua_State) void {
  lua.luaL_register(vm, "core.termios", &funcs);
}
