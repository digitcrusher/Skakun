const std = @import("std");
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

  // {
  //   var editor = Editor.init(gpa.allocator());
  //   //var buffer = try editor.open("https://lacina.io/lacian/after-setup.md");
  //   var buffer = try editor.open("test");
  //   defer buffer.destroy();

  //   var data: [2048]u8 = undefined;

  //   try buffer.insert(28, "- Wyłącz komputer i pójdź do psychologa.\n");
  //   //try buffer.read(0, data[0 .. buffer.root.?.width]);
  //   //std.debug.print("{s}", .{data[0 .. buffer.root.?.width]});
  //   try buffer.delete(73, 1274);
  //   try buffer.read(0, &data);
  //   std.debug.print("{s}", .{data});
  // }

  // _ = gpa.detectLeaks();

  const vm = lua.luaL_newstate() orelse return error.SomeKindOfMemoryError;
  defer lua.lua_close(vm);

  lua.luaL_openlibs(vm);
  @import("core/terminfo.zig").register(vm);
  @import("core/termios.zig").register(vm);

  const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
  defer allocator.free(exe_dir);
  lua.lua_pushlstring(vm, exe_dir.ptr, exe_dir.len);
  lua.lua_setglobal(vm, "exe_dir");

  _ = lua.luaL_dostring(
    vm,
    \\ xpcall(
    \\   function()
    \\     local config_dir = os.getenv('XDG_CONFIG_HOME')
    \\     if config_dir then
    \\       config_dir = config_dir .. '/skakun'
    \\     else
    \\       config_dir = os.getenv('HOME')
    \\       if config_dir then
    \\         config_dir = config_dir .. '/.config/skakun'
    \\       else -- We are on Windows.
    \\         config_dir = os.getenv('APPDATA') .. '/skakun'
    \\       end
    \\     end
    \\     package.path = exe_dir .. '/../lib/skakun/?/init.lua;' .. package.path
    \\     package.path = exe_dir .. '/../lib/skakun/?.lua;' .. package.path
    \\     package.path = config_dir .. '/?/init.lua;' .. package.path
    \\     package.path = config_dir .. '/?.lua;' .. package.path
    \\     package.cpath = exe_dir .. '/../lib/skakun/?.so;' .. package.cpath
    \\     package.cpath = config_dir .. '/?.so;' .. package.cpath
    \\     require('user')
    \\   end,
    \\   function(err)
    \\     print(debug.traceback(err, 2))
    \\   end
    \\ )
  );
}
