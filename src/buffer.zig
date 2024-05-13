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
const gio = @cImport({
  @cInclude("gio/gio.h");
  @cInclude("gio/gunixoutputstream.h");
});

// TODO: do we need an insert stack?
// TODO: copying between buffers
// TODO: converting between byte offests and line/cols
// TODO: detecting mmap file changes -> mark the buffer as corrupt
// TODO: buffer diffs
// TODO: force load mmaps

// Some methods have an optional "err_msg" parameter, which on failure, may be
// set to an error message from GIO. The caller is reponsible for freeing
// err_msg with the Editor's allocator afterwards.

const Fragment = struct {
  const Owner = enum {
    Allocator, Glib, Mmap
  };
  refc: i32 = 0,
  owner: Owner,
  data: []u8,

  // Data specific to mmaps
  fd: ?std.posix.fd_t = null,

  fn create(editor: *Editor, owner: Owner, data: []u8) !*Fragment {
    const self = try editor.allocator.create(Fragment);
    self.* = .{
      .owner = owner,
      .data = data,
    };
    if(owner == .Mmap) {
      try editor.mmaps.append(self);
    }
    return self;
  }

  fn ref(self: *Fragment) *Fragment {
    self.refc += 1;
    return self;
  }

  fn unref(self: *Fragment, editor: *Editor) void {
    self.refc -= 1;
    if(self.refc > 0) return;
    switch(self.owner) {
      .Allocator => {
        editor.allocator.free(self.data);
      },
      .Glib => {
        gio.g_free(self.data.ptr);
      },
      .Mmap => {
        std.posix.munmap(@alignCast(self.data));
        std.posix.close(self.fd.?);
        _ = editor.mmaps.swapRemove(std.mem.indexOfScalar(*Fragment, editor.mmaps.items, self).?);
      },
    }
    editor.allocator.destroy(self);
  }
};

const Node = struct {
  refc: i32 = 0,
  is_frozen: bool = false,
  frag: struct {
    ptr: *Fragment,
    start: usize,
    end: usize,
  },

  priority: u32,
  left: ?*Node = null,
  right: ?*Node = null,
  width: usize,

  fn create(editor: *Editor, frag: *Fragment, start: usize, end: usize) !*Node {
    const self = try editor.allocator.create(Node);
    self.* = .{
      .frag = .{
        .ptr = frag.ref(),
        .start = start,
        .end = end,
      },
      .priority = editor.rng.random().int(@TypeOf(self.priority)),
      .width = undefined,
    };
    self.update_stats();
    return self;
  }

  fn ref(self: *Node) *Node {
    self.refc += 1;
    return self;
  }

  fn unref(self: *Node, editor: *Editor) void {
    self.refc -= 1;
    if(self.refc > 0) return;
    if(self.left) |x| {
      x.unref(editor);
    }
    if(self.right) |x| {
      x.unref(editor);
    }
    self.frag.ptr.unref(editor);
    editor.allocator.destroy(self);
  }

  fn melt(self: *Node, editor: *Editor) !*Node {
    if(!self.is_frozen) {
      return self;
    }
    if(self.left) |x| {
      x.is_frozen = true;
    }
    if(self.right) |x| {
      x.is_frozen = true;
    }
    const copy = try editor.allocator.create(Node);
    copy.* = .{
      .frag = .{
        .ptr = self.frag.ptr.ref(),
        .start = self.frag.start,
        .end = self.frag.end,
      },
      .priority = self.priority,
      .width = undefined,
    };
    copy.set_left(editor, self.left);
    copy.set_right(editor, self.right);
    copy.update_stats();
    return copy;
  }

  fn set_left(self: *Node, editor: *Editor, value: ?*Node) void {
    std.debug.assert(!self.is_frozen);
    if(self.left == value) return;
    if(self.left) |x| {
      x.unref(editor);
    }
    self.left = if(value) |x| x.ref() else null;
  }

  fn set_right(self: *Node, editor: *Editor, value: ?*Node) void {
    std.debug.assert(!self.is_frozen);
    if(self.right == value) return;
    if(self.right) |x| {
      x.unref(editor);
    }
    self.right = if(value) |x| x.ref() else null;
  }

  fn update_stats(self: *Node) void {
    self.width = self.frag.end - self.frag.start;
    if(self.left) |x| {
      self.width += x.width;
    }
    if(self.right) |x| {
      self.width += x.width;
    }
  }

  fn merge(editor: *Editor, maybe_a: ?*Node, maybe_b: ?*Node) !?*Node {
    var a = maybe_a orelse return maybe_b;
    var b = maybe_b orelse return maybe_a;
    if(a.priority >= b.priority) {
      const result = try a.melt(editor);
      result.set_right(editor, try Node.merge(editor, a.right, b));
      result.update_stats();
      return result;
    } else {
      const result = try b.melt(editor);
      result.set_left(editor, try Node.merge(editor, a, b.left));
      result.update_stats();
      return result;
    }
  }

  // We do this reference juggling so that a cleanly split off child doesn't get garbage collected when unlinked from the parent.
  fn split_ref(self: *Node, editor: *Editor, offset_: usize) !struct {?*Node, ?*Node} {
    var offset = offset_;
    if(offset == 0) {
      return .{null, self.ref()};
    }

    if(self.left) |left| {
      if(offset <= left.width) {
        const b = try self.melt(editor);
        const sub = try left.split_ref(editor, offset);
        b.set_left(editor, sub[1]);
        if(sub[1]) |x| x.unref(editor);
        b.update_stats();
        return .{sub[0], b.ref()};
      }
      offset -= left.width;
    }

    if(offset < self.frag.end - self.frag.start) {
      const b = try Node.create(editor, self.frag.ptr, self.frag.start + offset, self.frag.end);
      b.set_right(editor, self.right);
      b.update_stats();
      const a = try self.melt(editor);
      a.frag.end = a.frag.start + offset;
      a.set_right(editor, null);
      a.update_stats();
      return .{a.ref(), b.ref()};
    }
    offset -= self.frag.end - self.frag.start;

    if(self.right) |right| {
      if(offset < right.width) {
        const a = try self.melt(editor);
        const sub = try right.split_ref(editor, offset);
        a.set_right(editor, sub[0]);
        if(sub[0]) |x| x.unref(editor);
        a.update_stats();
        return .{a.ref(), sub[1]};
      }
      offset -= right.width;
    }

    return if(offset == 0) .{self.ref(), null} else error.OutOfBounds;
  }

  fn read(self: *Node, offset_: usize, dest: []u8) !usize {
    var offset = offset_;
    if(offset > self.width) return error.OutOfBounds;
    if(dest.len <= 0) {
      return 0;
    }

    var readc: usize = 0;

    if(self.left) |left| {
      if(offset < left.width) {
        readc += try left.read(offset, dest);
        offset = 0;
      } else {
        offset -= left.width;
      }
    }

    const data = self.frag.ptr.data[self.frag.start .. self.frag.end];
    if(offset < data.len) {
      const data_slice = data[offset .. @min(offset + dest.len - readc, data.len)];
      std.mem.copyForwards(u8, dest[readc ..], data_slice);
      readc += data_slice.len;
      offset = 0;
    } else {
      offset -= data.len;
    }

    if(self.right) |right| {
      readc += try right.read(offset, dest[readc ..]);
    }

    return readc;
  }

  fn save(self: *Node, editor: *Editor, output: *gio.GOutputStream, err_msg: ?*?[]u8) !void {
    if(self.left) |x| {
      try x.save(editor, output, err_msg);
    }

    const data = self.frag.ptr.data[self.frag.start .. self.frag.end];
    var err: ?*gio.GError = null;
    if(gio.g_output_stream_write_all(output, data.ptr, data.len, null, null, &err) == 0) return handle_gio_error(err.?, editor.allocator, err_msg);

    if(self.right) |x| {
      try x.save(editor, output, err_msg);
    }
  }

  fn debug(self: *Node) void {
    std.debug.print("node {} {} {}\n", .{self.priority, self.frag.end - self.frag.start, self.width});
    if(self.left) |x| {
      x.debug();
    } else {
      std.debug.print("null\n", .{});
    }
    if(self.right) |x| {
      x.debug();
    } else {
      std.debug.print("null\n", .{});
    }
  }
};

pub const Buffer = struct {
  editor: *Editor,
  root: ?*Node,
  is_frozen: bool = false,
  freeze_time_ms: i64 = undefined,
  parent: ?*Buffer = null,

  fn create(editor: *Editor, root: ?*Node) !*Buffer {
    const self = try editor.allocator.create(Buffer);
    self.* = .{
      .editor = editor,
      .root = if(root) |x| x.ref() else null,
    };
    return self;
  }

  pub fn destroy(self: *Buffer) void {
    if(self.root) |x| {
      x.unref(self.editor);
    }
    self.editor.allocator.destroy(self);
  }

  pub fn freeze(self: *Buffer) void {
    self.is_frozen = true;
    if(self.root) |x| {
      x.unref(self.editor);
    }
    self.freeze_time_ms = std.time.milliTimestamp();
  }

  pub fn melt(self: *Buffer) !*Buffer {
    if(!self.is_frozen) {
      return self;
    }
    const copy = try Buffer.create(self.editor, self.root);
    copy.parent = self;
    return copy;
  }

  pub fn read(self: *Buffer, offset: usize, dest: []u8) !usize {
    if(self.root) |x| {
      return x.read(offset, dest);
    } else if(offset > 0) {
      return error.OutOfBounds;
    } else {
      return 0;
    }
  }

  pub fn save(self: *Buffer, path: []const u8, err_msg: ?*?[]u8) !void {
    const path_z = try self.editor.allocator.dupeZ(u8, path);
    defer self.editor.allocator.free(path_z);
    return self.saveZ(path_z, err_msg);
  }

  pub fn saveZ(self: *Buffer, path: [*:0]const u8, err_msg: ?*?[]u8) !void {
    var err: ?*gio.GError = null;

    var output: *gio.GOutputStream = undefined;
    if(gio.g_uri_is_valid(path, gio.G_URI_FLAGS_NONE, null) != 0) {
      const file = gio.g_file_new_for_uri(path);
      defer gio.g_object_unref(file);
      output = @ptrCast(gio.g_file_replace(file, null, 0, gio.G_FILE_CREATE_NONE, null, &err) orelse return handle_gio_error(err.?, self.editor.allocator, err_msg));

    } else {
      var fd: std.posix.fd_t = undefined;

      // This whole mess is here just to prevent us from overwriting existing
      // files mmapped by us, which would corrupt the mmaps in question. To
      // accomplish this goal of buffer integrity, we check whether the
      // destination file in question is actually mmapped, and if it is then we
      // have to move it to a temporary destination on the same drive (that's
      // what the realpath here is for) and create a new file. Oh, and by the
      // way, naively operating on paths would be prone to data races, so we
      // play with directory file descriptors instead.

      // This is morally wrong: https://insanecoding.blogspot.com/2007/11/pathmax-simply-isnt.html
      var buf: [std.fs.max_path_bytes]u8 = undefined;
      // This does return error.FileNotFound even if a symlink exists but is broken.
      const maybe_real_path = std.posix.realpathZ(path, &buf) catch |err2| if(err2 == error.FileNotFound) null else return err2;

      if(maybe_real_path) |real_path| {
        const dir_path = std.fs.path.dirname(real_path) orelse {
          return error.IsDir;
        };
        const name = std.fs.path.basename(real_path);

        const dir_fd = try std.posix.open(dir_path, .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
        var should_close_dir_fd = true;
        defer if(should_close_dir_fd) std.posix.close(dir_fd);

        fd = try std.posix.openat(dir_fd, name, .{ .ACCMODE = .WRONLY }, 0);
        var should_close_fd = true;
        defer if(should_close_fd) std.posix.close(fd);

        const stat = try std.posix.fstat(fd);

        var is_mmap = false;
        for(self.editor.mmaps.items) |mmap| {
          const mmap_stat = try std.posix.fstat(mmap.fd.?);
          if(mmap_stat.dev == stat.dev and mmap_stat.ino == stat.ino) {
            is_mmap = true;
            break;
          }
        }

        if(is_mmap) {
          // If the destination file has multiple hard links pointing it, then
          // it would be far more sensible to write directly to it, but at the
          // same time we can't do that because it's mmapped and doing that
          // would corrupt buffers, including maybe even this very one that
          // we're trying to save.
          if(stat.nlink > 1) {
            return error.MultipleHardLinks;
          }

          const new_name = try std.fmt.allocPrintZ(self.editor.allocator, ".{s}.skak-{x:0>8}", .{name, self.editor.rng.random().int(u32)});
          var should_free_new_name = true;
          defer if(should_free_new_name) self.editor.allocator.free(new_name);
          try std.posix.renameat(dir_fd, name, dir_fd, new_name);
          try self.editor.moved_mmapped_files.append(.{ .dir_fd = dir_fd, .name = new_name });
          should_close_dir_fd = false;
          should_free_new_name = false;

          // We don't want to close a file descriptor twice.
          std.posix.close(fd);
          should_close_fd = false;
          fd = try std.posix.openat(dir_fd, name, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true }, stat.mode);

        } else {
          should_close_fd = false;
        }

      } else {
        fd = try std.posix.openZ(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true }, std.fs.File.default_mode);
      }

      output = gio.g_unix_output_stream_new(fd, 1);
    }
    defer gio.g_object_unref(output);

    if(self.root) |x| {
      try x.save(self.editor, output, err_msg);
    }
    if(gio.g_output_stream_close(output, null, &err) == 0) {
      return handle_gio_error(err.?, self.editor.allocator, err_msg);
    }
  }

  pub fn insert(self: *Buffer, offset: usize, data: []const u8) !void {
    if(self.is_frozen) return error.BufferFrozen;
    if(data.len <= 0) return;

    const node = try Node.create(self.editor, try Fragment.create(self.editor, .Allocator, try self.editor.allocator.dupe(u8, data)), 0, data.len);
    if(self.root == null) {
      self.root = node.ref();
      return;
    }

    const old_root = self.root.?;
    self.root = null;
    defer old_root.unref(self.editor);

    const a, const b = try old_root.split_ref(self.editor, offset);
    defer {
      if(a) |x| x.unref(self.editor);
      if(b) |x| x.unref(self.editor);
    }
    self.root = (try Node.merge(self.editor, try Node.merge(self.editor, a, node), b)).?.ref();
  }

  pub fn delete(self: *Buffer, start: usize, end: usize) !void {
    if(self.is_frozen) return error.BufferFrozen;
    if(start >= end) return;
    if(self.root == null) return error.OutOfBounds;

    const old_root = self.root.?;
    self.root = null;
    defer old_root.unref(self.editor);

    const ab, const c = try old_root.split_ref(self.editor, end);
    defer {
      ab.?.unref(self.editor);
      if(c) |x| x.unref(self.editor);
    }
    const a, const b = try ab.?.split_ref(self.editor, start);
    defer {
      if(a) |x| x.unref(self.editor);
      b.?.unref(self.editor);
    }
    if(try Node.merge(self.editor, a, c)) |x| {
      self.root = x.ref();
    }
  }

  // pub fn copy(self: *Buffer, offset: usize, src: *Buffer, start: usize, end: usize) !void {
  //   if(self.is_frozen) {
  //     return error.BufferFrozen;
  //   } else if(!src.is_frozen) {
  //     return error.BufferNotFrozen;
  //   }
  //   std.debug.assert(self.editor == src.buffer.editor);
  //   // TODO
  // }
};

pub const Editor = struct {
  allocator: std.mem.Allocator,
  rng: std.rand.DefaultPrng,

  max_load_size: usize = 100_000_000,

  mmaps: std.ArrayList(*Fragment),
  moved_mmapped_files: std.ArrayList(struct {
    dir_fd: std.posix.fd_t,
    name: [:0]u8,
  }),

  pub fn init(allocator: std.mem.Allocator) Editor {
    var self = Editor{
      .allocator = allocator,
      .rng = std.rand.DefaultPrng.init(@bitCast(@as(i64, @truncate(std.time.nanoTimestamp())))),
      .mmaps = undefined,
      .moved_mmapped_files = undefined,
    };
    self.mmaps = @TypeOf(self.mmaps).init(allocator);
    self.moved_mmapped_files = @TypeOf(self.moved_mmapped_files).init(allocator);
    return self;
  }

  pub fn deinit(self: *Editor) void {
    self.mmaps.deinit();
    for(self.moved_mmapped_files.items) |file| {
      std.posix.unlinkatZ(file.dir_fd, file.name, 0) catch {};
      self.allocator.free(file.name);
    }
    self.moved_mmapped_files.deinit();
  }

  pub fn open(self: *Editor, path: []const u8, err_msg: ?*?[]u8) !*Buffer {
    const path_z = try self.allocator.dupeZ(u8, path);
    defer self.allocator.free(path_z);
    return self.openZ(path_z, err_msg);
  }

  pub fn openZ(self: *Editor, path: [*:0]const u8, err_msg: ?*?[]u8) !*Buffer {
    var frag: *Fragment = undefined;
    if(gio.g_uri_is_valid(path, gio.G_URI_FLAGS_NONE, null) != 0) {
      const file = gio.g_file_new_for_uri(path); // TODO: Mount admin:// locations
      defer gio.g_object_unref(file);

      var data: []u8 = undefined;
      var err: ?*gio.GError = null;
      if(gio.g_file_load_contents(file, null, @ptrCast(&data.ptr), &data.len, null, &err) == 0) return handle_gio_error(err.?, self.allocator, err_msg);
      frag = try Fragment.create(self, .Glib, data);

    } else {
      const fd = try std.posix.openZ(path, .{ .ACCMODE = .RDONLY }, 0);
      var should_close_fd = true;
      defer if(should_close_fd) std.posix.close(fd);

      const size: usize = @intCast((try std.posix.fstat(fd)).size);
      if(size <= self.max_load_size) {
        var data = try self.allocator.alloc(u8, size);
        data.len = try std.posix.read(fd, data);
        frag = try Fragment.create(self, .Allocator, data);

      } else {
        frag = try Fragment.create(self, .Mmap, try std.posix.mmap(null, size, std.posix.PROT.READ, .{ .TYPE = .PRIVATE }, fd, 0));
        frag.fd = fd;
        should_close_fd = false;
      }
    }

    return Buffer.create(self, try Node.create(self, frag, 0, frag.data.len));
  }
};

// We try to mimic std.http.Client's and std.fs.File's errors here. Note that
// this handles only the errors that matter to Editor.open and Buffer.save.
// Both Glib's and Zig's errors are just some reduction and renaming of the
// POSIX errors, so to obtain this mapping I just had to search for the Glib
// error in its source code and then search for the corresponding POSIX error
// in std.posix's source code.
fn handle_gio_error(err: *gio.GError, allocator: std.mem.Allocator, msg: ?*?[]u8) anyerror {
  defer gio.g_error_free(err);
  if(msg) |x| {
    x.* = allocator.dupe(u8, std.mem.span(err.message)) catch null;
  }
  // Normally, in C code, one would use G_DBUS_ERROR, G_IO_ERROR,
  // G_RESOLVER_ERROR and G_TLS_ERROR here, but Zig is different and we are
  // *not* allowed to do that because those are macros to function calls.
  // I mean, Zig could at least turn those forbidden macros into functions,
  // and not tell us to just go jump in the lake.
  if(err.domain == gio.g_dbus_error_quark()) {
    return switch(err.code) {
      gio.G_DBUS_ERROR_NO_MEMORY => error.OutOfMemory,
      gio.G_DBUS_ERROR_SPAWN_NO_MEMORY => error.OutOfMemory,
      else => error.DbusError,
    };
  } else if(err.domain == gio.g_io_error_quark()) {
    return switch(err.code) {
      gio.G_IO_ERROR_NOT_FOUND => error.FileNotFound,
      gio.G_IO_ERROR_IS_DIRECTORY => error.IsDir,
      gio.G_IO_ERROR_FILENAME_TOO_LONG => error.NameTooLong,
      gio.G_IO_ERROR_INVALID_FILENAME => error.BadPathName,
      gio.G_IO_ERROR_TOO_MANY_LINKS => error.SymLinkLoop,
      gio.G_IO_ERROR_NO_SPACE => error.NoSpaceLeft,
      gio.G_IO_ERROR_PERMISSION_DENIED => error.AccessDenied,
      gio.G_IO_ERROR_NOT_MOUNTED => error.FileNotMounted,
      gio.G_IO_ERROR_TIMED_OUT => error.ConnectionTimedOut,
      gio.G_IO_ERROR_BUSY => error.DeviceBusy,
      gio.G_IO_ERROR_HOST_NOT_FOUND => error.UnknownHostName,
      gio.G_IO_ERROR_TOO_MANY_OPEN_FILES => error.FdQuotaExceeded,
      gio.G_IO_ERROR_DBUS_ERROR => error.DbusError,
      gio.G_IO_ERROR_HOST_UNREACHABLE => error.NetworkUnreachable,
      gio.G_IO_ERROR_NETWORK_UNREACHABLE => error.NetworkUnreachable,
      gio.G_IO_ERROR_CONNECTION_REFUSED => error.ConnectionRefused,
      gio.G_IO_ERROR_CONNECTION_CLOSED => error.ConnectionResetByPeer,
      gio.G_IO_ERROR_NO_SUCH_DEVICE => error.NoDevice,
      else => error.Unexpected,
    };
  } else if(err.domain == gio.g_resolver_error_quark()) {
    return switch(err.code) {
      gio.G_RESOLVER_ERROR_NOT_FOUND => error.UnknownHostName,
      gio.G_RESOLVER_ERROR_TEMPORARY_FAILURE => error.TemporaryNameServerFailure,
      gio.G_RESOLVER_ERROR_INTERNAL => error.NameServerFailure,
      else => error.Unexpected,
    };
  } else if(err.domain == gio.g_tls_error_quark()) {
    return error.TlsInitializationFailed;
  } else {
    return error.Unexpected;
  }
}
