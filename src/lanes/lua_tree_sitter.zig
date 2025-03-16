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
const lua = @import("ziglua");
const c = @cImport({
  @cInclude("lts/language.h");
  @cInclude("lts/query/init.h");
});
const assert = std.debug.assert;

fn clone_language(vm: *lua.Lua) i32 {
  const to = vm.toUserdata(*anyopaque, 1) catch unreachable;
  const from = vm.toUserdata(*anyopaque, 2) catch unreachable;
  to.* = from.*;
  return 0;
}

var query_refc: ?std.AutoHashMap(c.LTS_Query, i32) = null;

fn clone_query(vm: *lua.Lua) i32 {
  const to = vm.toUserdata(c.LTS_Query, 1) catch unreachable;
  const from = vm.toUserdata(c.LTS_Query, 2) catch unreachable;
  to.* = from.*;
  query_refc.?.put(from.*, (query_refc.?.get(from.*) orelse 0) + 1) catch unreachable;
  std.io.getStdErr().writer().print("clone {*} (now has {} refs)\n", .{from.query, query_refc.?.get(from.*).?}) catch unreachable;
  return 0;
}

fn unref_query(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(c.LTS_Query, 1, c.LTS_QUERY_METATABLE_NAME);
  const refc = (query_refc.?.get(self.*) orelse 1) - 1;
  std.io.getStdErr().writer().print("unref {*} (now has {} refs)\n", .{self.query, refc}) catch unreachable;
  if(refc == 0) {
    _ = query_refc.?.remove(self.*);
    assert(vm.getMetaField(-1, "_lanes_gc") catch unreachable == .function);
    vm.pushValue(-2);
    vm.call(.{ .args = 1, .results = 0 });
  } else {
    query_refc.?.put(self.*, refc) catch unreachable;
  }
  return 0;
}

export fn luaopen_lanes_lua_tree_sitter(vm: *lua.Lua) i32 {
  vm.loadString("return require('lua_tree_sitter')") catch unreachable;
  vm.call(.{ .args = 0, .results = 1 });

  assert(vm.getMetatableRegistry(c.LTS_LANGUAGE_METATABLE_NAME) == .table);
  vm.pushFunction(lua.wrap(clone_language));
  vm.setField(-2, "__lanesclone");
  vm.setField(-2, "_lanes_" ++ c.LTS_LANGUAGE_METATABLE_NAME);

  if(query_refc == null) {
    query_refc = @TypeOf(query_refc.?).init(vm.allocator());
  }
  assert(vm.getMetatableRegistry(c.LTS_QUERY_METATABLE_NAME) == .table);
  assert(vm.getField(-1, "__gc") == .function);
  vm.setField(-2, "_lanes_gc");
  vm.pushFunction(lua.wrap(clone_query));
  vm.setField(-2, "__lanesclone");
  vm.pushFunction(lua.wrap(unref_query));
  vm.setField(-2, "__gc");
  vm.setField(-2, "_lanes_" ++ c.LTS_QUERY_METATABLE_NAME);

  return 1;
}
