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
const lua = @import("ziglua");
const buffer = @import("../buffer.zig");
const Buffer = buffer.Buffer;
const c = @cImport(@cInclude("stdlib.h"));

var editor: buffer.Editor = undefined;

fn raise_err(vm: *lua.Lua, err: buffer.Error, err_msg: ?[]u8) noreturn {
  // Most of these were ripped straight out of glibc.
  const zig_err = switch(err) {
    error.AccessDenied => "permission denied",
    error.AntivirusInterference => "antivirus interfered with file operations",
    error.BadPathName => "invalid path name",
    error.BrokenPipe => "broken pipe",
    error.ConnectionRefused => "connection refused",
    error.ConnectionResetByPeer => "connection reset by peer",
    error.ConnectionTimedOut => "connection timed out",
    error.DbusFailure => "dbus failure",
    error.DeviceBusy => "device or resource busy",
    error.DiskQuota => "disk quota exceeded",
    error.FdQuotaExceeded => "too many open files",
    error.FileBusy => "device or resource busy",
    error.FileLocksNotSupported => unreachable, // We don't use O_TMPFILE.
    error.FileNotFound => "no such file or directory",
    error.FileNotMounted => "file not mounted",
    error.FileSystem => unreachable, // Never actually generated with libc - from posix.realPath in Buffer.save
    error.FileTooBig => "file too large",
    error.InputOutput => "input/output error",
    error.InvalidUtf8 => "invalid UTF-8 code",
    error.InvalidWtf8 => "invalid WTF-8 code",
    error.IsDir => "is a directory",
    error.LinkQuotaExceeded => "too many links",
    error.LockedMemoryLimitExceeded => unreachable, // We don't use MAP_LOCKED.
    error.MemoryMappingNotSupported => "mmap not supported",
    error.MultipleHardLinks => "file has multiple hard links",
    error.NameServerFailure => "unknown failure in name resolution",
    error.NameTooLong => "file name too long",
    error.NetworkNotFound => "no such file or directory on network",
    error.NetworkUnreachable => "network is unreachable",
    error.NoDevice => "no such device",
    error.NoSpaceLeft => "no space left on device",
    error.NotDir => "not a directory",
    error.NotOpenForReading => unreachable, // from posix.read in Editor.open
    error.NotSupported => "operation not supported",
    error.OperationAborted => unreachable, // Never actually generated.
    error.OutOfBounds => "index out of bounds",
    error.OutOfMemory => "cannot allocate memory",
    error.PathAlreadyExists => unreachable, // Always a race condition - from posix.open in Buffer.save
    error.PermissionDenied => unreachable, // We don't use PROT_EXEC.
    error.PipeBusy => "all pipe instances are busy",
    error.ProcessFdQuotaExceeded => "too many open files",
    error.ReadOnlyFileSystem => "read-only file system",
    error.RenameAcrossMountPoints => unreachable, // from posix.rename in Buffer.save
    error.SharingViolation => unreachable, // Never actually generated.
    error.SocketNotConnected => unreachable, // from posix.read in Editor.open
    error.SymLinkLoop => "too many levels of symbolic links",
    error.SystemFdQuotaExceeded => "too many open files in system",
    error.SystemResources => "cannot allocate memory",
    error.TemporaryNameServerFailure => "temporary failure in name resolution",
    error.TlsInitializationFailed => "tls initialization failed",
    error.Unexpected => "unexpected error",
    error.UnknownHostName => "name or service not known",
    error.UnrecognizedVolume => "unrecognized volume file system",
    error.WouldBlock => unreachable, // We don't use O_NONBLOCK.
  };
  if(err_msg) |x| {
    vm.raiseErrorStr("%s (%s)", .{x.ptr, zig_err.ptr});
  } else {
    vm.raiseErrorStr("%s", .{zig_err.ptr});
  }
}

fn new(vm: *lua.Lua) i32 {
  vm.newUserdata(*Buffer, 0).* = Buffer.create(&editor, null) catch |err| raise_err(vm, err, null);
  vm.setMetatableRegistry("core.buffer");
  return 1;
}

fn open(vm: *lua.Lua) i32 {
  const path = vm.checkString(1);

  vm.getSubtable(lua.registry_index, "_LOADED") catch unreachable;
  vm.getSubtable(-1, "core.buffer") catch unreachable;
  _ = vm.getField(-1, "max_open_size");
  editor.max_open_size = @intCast(vm.checkInteger(-1));
  vm.pop(3);

  var err_msg: ?[]u8 = null;
  vm.newUserdata(*Buffer, 0).* = editor.open_z(path, &err_msg) catch |err| raise_err(vm, err, err_msg);
  vm.setMetatableRegistry("core.buffer");
  return 1;
}

fn __gc(vm: *lua.Lua) i32 {
  vm.checkUserdata(*Buffer, 1, "core.buffer").*.destroy();
  return 0;
}

fn save(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const path = vm.checkString(2);
  var err_msg: ?[]u8 = null;
  self.save_z(path, &err_msg) catch |err| raise_err(vm, err, null);
  return 0;
}

fn __len(vm: *lua.Lua) i32 {
  vm.pushInteger(@intCast(vm.checkUserdata(*Buffer, 1, "core.buffer").*.len()));
  return 1;
}

fn read(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const from = vm.checkInteger(2);
  const to = vm.checkInteger(3);
  if(from > to) {
    _ = vm.pushString("");
    return 1;
  }
  if(to > self.len()) {
    raise_err(vm, error.OutOfBounds, null);
  }
  var result: lua.Buffer = undefined;
  const readc = self.read(@intCast(from - 1), result.initSize(vm, @intCast(to - from + 1))) catch |err| raise_err(vm, err, null);
  std.debug.assert(readc == to - from + 1);
  result.pushResultSize(readc);
  return 1;
}

fn iter(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const from = vm.optInteger(2) orelse 1;
  vm.newUserdata(Buffer.Iterator, 0).* = self.iter(@intCast(from - 1)) catch |err| raise_err(vm, err, null);
  vm.setMetatableRegistry("core.buffer.iter");
  return 1;
}

fn insert(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const idx = vm.checkInteger(2);
  const data = vm.checkString(3);
  self.insert(@intCast(idx - 1), data) catch |err| raise_err(vm, err, null);
  return 0;
}

fn delete(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const from = vm.checkInteger(2);
  const to = vm.checkInteger(3);
  self.delete(@intCast(from - 1), @intCast(to)) catch |err| raise_err(vm, err, null);
  return 0;
}

fn copy(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const idx = vm.checkInteger(2);
  const src = vm.checkUserdata(*Buffer, 3, "core.buffer").*;
  const from = vm.checkInteger(4);
  const to = vm.checkInteger(5);
  self.copy(@intCast(idx - 1), src, @intCast(from - 1), @intCast(to)) catch |err| raise_err(vm, err, null);
  return 0;
}

fn clear_copy_cache(_: *lua.Lua) i32 {
  editor.clear_copy_cache();
  return 0;
}

fn load(vm: *lua.Lua) i32 {
  vm.checkUserdata(*Buffer, 1, "core.buffer").*.load() catch |err| raise_err(vm, err, null);
  return 0;
}

fn has_healthy_mmap(vm: *lua.Lua) i32 {
  vm.pushBoolean(vm.checkUserdata(*Buffer, 1, "core.buffer").*.has_healthy_mmap());
  return 1;
}

fn has_corrupt_mmap(vm: *lua.Lua) i32 {
  vm.pushBoolean(vm.checkUserdata(*Buffer, 1, "core.buffer").*.has_corrupt_mmap());
  return 1;
}

fn validate_mmaps(vm: *lua.Lua) i32 {
  vm.pushBoolean(editor.validate_mmaps());
  return 1;
}

const buffer_methods = [_]lua.FnReg{
  .{ .name = "new", .func = lua.wrap(new) },
  .{ .name = "open", .func = lua.wrap(open) },
  .{ .name = "save", .func = lua.wrap(save) },

  .{ .name = "read", .func = lua.wrap(read) },
  .{ .name = "iter", .func = lua.wrap(iter) },

  .{ .name = "insert", .func = lua.wrap(insert) },
  .{ .name = "delete", .func = lua.wrap(delete) },
  .{ .name = "copy", .func = lua.wrap(copy) },
  .{ .name = "clear_copy_cache", .func = lua.wrap(clear_copy_cache) },

  .{ .name = "load", .func = lua.wrap(load) },
  .{ .name = "has_healthy_mmap", .func = lua.wrap(has_healthy_mmap) },
  .{ .name = "has_corrupt_mmap", .func = lua.wrap(has_corrupt_mmap) },
  .{ .name = "validate_mmaps", .func = lua.wrap(validate_mmaps) },
};

fn __gc_iter(vm: *lua.Lua) i32 {
  vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter").deinit();
  return 0;
}

fn next(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  vm.pushAny(self.next()) catch unreachable;
  return 1;
}

fn prev(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  vm.pushAny(self.prev()) catch unreachable;
  return 1;
}

fn rewind(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  const count = vm.checkInteger(2);
  self.rewind(@intCast(count)) catch |err| raise_err(vm, err, null);
  return 0;
}

fn next_codepoint(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  vm.pushAny(self.next_codepoint() catch |err| raise_err(vm, err, null)) catch unreachable;
  return 1;
}

fn next_grapheme(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");

  var dest = std.ArrayList(u21).init(vm.allocator());
  defer dest.deinit();
  const maybe_grapheme = self.next_grapheme(&dest) catch |err| {
    dest.deinit();
    raise_err(vm, err, null);
  };

  if(maybe_grapheme) |grapheme| {
    var result: lua.Buffer = undefined;
    var len: usize = 0;
    for(grapheme) |codepoint| {
      len += std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
    }
    const buf = result.initSize(vm, len);
    var i: usize = 0;
    for(grapheme) |codepoint| {
      i += std.unicode.utf8Encode(codepoint, buf[i ..]) catch unreachable;
    }
    result.pushResultSize(len);
  } else {
    vm.pushNil();
  }
  return 1;
}

fn last_advance(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(Buffer.Iterator, 1, "core.buffer.iter");
  vm.pushInteger(@intCast(self.last_advance));
  return 1;
}

const iter_methods = [_]lua.FnReg{
  .{ .name = "next", .func = lua.wrap(next) },
  .{ .name = "prev", .func = lua.wrap(prev) },
  .{ .name = "rewind", .func = lua.wrap(rewind) },
  .{ .name = "next_codepoint", .func = lua.wrap(next_codepoint) },
  .{ .name = "next_grapheme", .func = lua.wrap(next_grapheme) },
  .{ .name = "last_advance", .func = lua.wrap(last_advance) },
};

fn cleanup() callconv(.C) void {
  editor.deinit();
}

pub fn luaopen(vm: *lua.Lua) i32 {
  editor = buffer.Editor.init(vm.allocator());
  std.debug.assert(c.atexit(cleanup) == 0);

  vm.newLib(&buffer_methods);
  vm.pushInteger(@intCast(editor.max_open_size));
  vm.setField(-2, "max_open_size");

  vm.newMetatable("core.buffer") catch unreachable;
  vm.pushValue(-2);
  vm.setField(-2, "__index");
  vm.pushFunction(lua.wrap(__gc));
  vm.setField(-2, "__gc");
  vm.pushFunction(lua.wrap(__len));
  vm.setField(-2, "__len");
  vm.pop(1);

  vm.newMetatable("core.buffer.iter") catch unreachable;
  vm.newLib(&iter_methods);
  vm.setField(-2, "__index");
  vm.pushFunction(lua.wrap(__gc_iter));
  vm.setField(-2, "__gc");
  vm.pop(1);

  return 1;
}
