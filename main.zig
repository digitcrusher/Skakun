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

  // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  // defer _ = gpa.deinit();

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
  lua.luaL_openlibs(vm);
  _ = lua.luaL_dostring(
    vm,
    \\ xpcall(
    \\   function()
    \\     require('init')
    \\   end,
    \\   function(err)
    \\     print(debug.traceback(err, 2))
    \\   end
    \\ )
  );
  lua.lua_close(vm);
}
