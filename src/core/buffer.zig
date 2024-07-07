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

var editor: buffer.Editor = undefined;

fn raise_err(vm: *lua.Lua, err: buffer.Error, err_msg: ?[:0]u8) noreturn {
  // Most of these were ripped straight out of glibc.
  const zig_err: [*:0]const u8 = switch(err) {
    error.AccessDenied => "permission denied",
    error.AntivirusInterference => "antivirus interfered with file operations",
    error.BadPathName => "invalid path name",
    error.BrokenPipe => "broken pipe",
    error.BufferFrozen => "buffer is frozen",
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
    error.InvalidUtf8 => "malformed UTF-8",
    error.InvalidWtf8 => "malformed WTF-8",
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
    vm.raiseErrorStr("%s (%s)", .{x.ptr, zig_err});
  } else {
    vm.raiseErrorStr("%s", .{zig_err});
  }
}

fn new(vm: *lua.Lua) i32 {
  vm.newUserdata(*Buffer, 0).* = Buffer.create(&editor, null) catch |x| raise_err(vm, x, null);
  vm.setMetatableRegistry("core.buffer");
  return 1;
}

fn open(vm: *lua.Lua) i32 {
  const path = vm.checkString(1);

  _ = vm.getField(lua.registry_index, "_LOADED");
  _ = vm.getField(-1, "core.buffer");
  _ = vm.getField(-1, "max_open_size");
  editor.max_open_size = @intCast(vm.checkInteger(-1));
  vm.pop(2);

  var err_msg: ?[:0]u8 = null;
  vm.newUserdata(*Buffer, 0).* = editor.open_z(path, &err_msg) catch |x| raise_err(vm, x, err_msg);
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
  var err_msg: ?[:0]u8 = null;
  self.save_z(path, &err_msg) catch |x| raise_err(vm, x, null);
  return 0;
}

fn __len(vm: *lua.Lua) i32 {
  vm.pushInteger(@intCast(vm.checkUserdata(*Buffer, 1, "core.buffer").*.len()));
  return 1;
}

fn read(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const start = vm.checkInteger(2);
  const end = vm.checkInteger(3);
  if(start >= end) {
    _ = vm.pushString("");
    return 1;
  }
  if(end > self.len()) {
    raise_err(vm, error.OutOfBounds, null);
  }
  var result: lua.Buffer = undefined;
  const readc = self.read(@intCast(start), result.initSize(vm, @intCast(end - start))) catch |x| raise_err(vm, x, null);
  std.debug.assert(readc == end - start);
  result.pushResultSize(readc);
  return 1;
}

fn insert(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const offset = vm.checkInteger(2);
  const data = vm.checkString(3);
  self.insert(@intCast(offset), data) catch |x| raise_err(vm, x, null);
  return 0;
}

fn delete(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const start = vm.checkInteger(2);
  const end = vm.checkInteger(3);
  self.delete(@intCast(start), @intCast(end)) catch |x| raise_err(vm, x, null);
  return 0;
}

fn copy(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  const offset = vm.checkInteger(2);
  const src = vm.checkUserdata(*Buffer, 3, "core.buffer").*;
  const start = vm.checkInteger(4);
  const end = vm.checkInteger(5);
  self.copy(@intCast(offset), src, @intCast(start), @intCast(end)) catch |x| raise_err(vm, x, null);
  return 0;
}

fn clear_copy_cache(_: *lua.Lua) i32 {
  editor.clear_copy_cache();
  return 0;
}

fn freeze(vm: *lua.Lua) i32 {
  vm.checkUserdata(*Buffer, 1, "core.buffer").*.freeze();
  return 0;
}

fn is_frozen(vm: *lua.Lua) i32 {
  vm.pushBoolean(vm.checkUserdata(*Buffer, 1, "core.buffer").*.is_frozen);
  return 1;
}

fn thaw(vm: *lua.Lua) i32 {
  const self = vm.checkUserdata(*Buffer, 1, "core.buffer").*;
  if(self.is_frozen) {
    const result = self.thaw() catch |x| raise_err(vm, x, null);
    vm.newUserdata(*Buffer, 0).* = result;
    vm.setMetatableRegistry("core.buffer");
  }
  vm.pushValue(1);
  return 1;
}

fn load(vm: *lua.Lua) i32 {
  vm.checkUserdata(*Buffer, 1, "core.buffer").*.load() catch |x| raise_err(vm, x, null);
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

fn check_fs_events(vm: *lua.Lua) i32 {
  vm.pushBoolean(editor.check_fs_events());
  return 1;
}

const funcs = [_]lua.FnReg{
  .{ .name = "new", .func = lua.wrap(new) },
  .{ .name = "open", .func = lua.wrap(open) },
  .{ .name = "save", .func = lua.wrap(save) },

  .{ .name = "read", .func = lua.wrap(read) },
  .{ .name = "insert", .func = lua.wrap(insert) },
  .{ .name = "delete", .func = lua.wrap(delete) },
  .{ .name = "copy", .func = lua.wrap(copy) },
  .{ .name = "clear_copy_cache", .func = lua.wrap(clear_copy_cache) },

  .{ .name = "freeze", .func = lua.wrap(freeze) },
  .{ .name = "is_frozen", .func = lua.wrap(is_frozen) },
  .{ .name = "thaw", .func = lua.wrap(thaw) },

  .{ .name = "load", .func = lua.wrap(load) },
  .{ .name = "has_healthy_mmap", .func = lua.wrap(has_healthy_mmap) },
  .{ .name = "has_corrupt_mmap", .func = lua.wrap(has_corrupt_mmap) },
  .{ .name = "check_fs_events", .func = lua.wrap(check_fs_events) },
};

var is_deinit = false;
fn cleanup(_: *lua.Lua) i32 {
  if(!is_deinit) {
    editor.deinit();
    is_deinit = true;
  }
  return 0;
}

pub fn luaopen(vm: *lua.Lua) i32 {
  editor = buffer.Editor.init(vm.allocator());

  vm.newLib(&funcs);
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

  _ = vm.getField(lua.registry_index, "_LOADED");
  _ = vm.getField(-1, "core");
  _ = vm.getField(-1, "add_cleanup");
  vm.pushFunction(lua.wrap(cleanup));
  vm.call(1, 0);
  vm.pop(2);

  return 1;
}