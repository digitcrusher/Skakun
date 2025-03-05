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
const gio = @cImport({
  @cInclude("gio/gio.h");
  @cInclude("gio/gunixoutputstream.h");
});
const grapheme = @cImport(@cInclude("grapheme.h"));
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const posix = std.posix;

// Some methods have an optional "err_msg" parameter, which on failure, may be
// set to an error message from GIO. The caller is reponsible for freeing
// err_msg with the Editor's allocator afterwards.

pub const Error = Allocator.Error || error {OutOfBounds, MultipleHardLinks} || GioError || posix.OpenError || posix.ReadError || posix.MMapError || posix.RealPathError || posix.RenameError;

const Fragment = struct {
  const Owner = enum {
    Allocator, Glib, Mmap
  };
  refc: i32 = 0,
  owner: Owner,
  data: []u8,

  // Data specific to mmaps
  is_corrupt: bool = false,
  // A file descriptor's inode number is constant. Even then, an mmap is
  // technically bound to the inode, and not the file descriptor.
  st_dev: posix.dev_t = undefined,
  st_ino: posix.ino_t = undefined,
  file_monitor: ?*gio.GFileMonitor = null,

  fn create(editor: *Editor, owner: Owner, data: []u8) Allocator.Error!*Fragment {
    assert(owner != .Mmap);
    const self = try editor.allocator.create(Fragment);
    self.* = .{
      .owner = owner,
      .data = data,
    };
    return self;
  }

  fn create_mmap(editor: *Editor, data: []u8, st_dev: posix.dev_t, st_ino: posix.ino_t, path: [*:0]const u8, err_msg: ?*?[]u8) GioError!*Fragment {
    const self = try editor.allocator.create(Fragment);
    errdefer editor.allocator.destroy(self);
    self.* = .{
      .owner = .Mmap,
      .data = data,
      .st_dev = st_dev,
      .st_ino = st_ino,
    };

    const file = gio.g_file_new_for_path(path);
    defer gio.g_object_unref(file);

    gio.g_main_context_push_thread_default(editor.gio_async_ctx);
    defer gio.g_main_context_pop_thread_default(editor.gio_async_ctx);

    var err: ?*gio.GError = null;
    self.file_monitor = gio.g_file_monitor_file(file, gio.G_FILE_MONITOR_WATCH_HARD_LINKS, null, &err) orelse return handle_gio_error(err.?, editor.allocator, err_msg);
    errdefer gio.g_object_unref(self.file_monitor);

    const user_data = try editor.allocator.create(GioCallbackUserData);
    errdefer editor.allocator.destroy(user_data);
    user_data.* = .{ .self = self, .editor = editor };
    _ = gio.g_signal_connect_data(self.file_monitor, "changed", @ptrCast(&gio_file_monitor_callback), user_data, @ptrCast(&gio_destroy_user_data), gio.G_CONNECT_DEFAULT);

    try editor.mmaps.append(self);
    return self;
  }

  const GioCallbackUserData = struct { self: *Fragment, editor: *Editor };
  fn gio_file_monitor_callback(_: *gio.GFileMonitor, _: *gio.GFile, _: *gio.GFile, event: gio.GFileMonitorEvent, user_data: *GioCallbackUserData) callconv(.C) void {
    // We don't have to check for deletion since the mmap keeps the file
    // contents alive.
    if(event != gio.G_FILE_MONITOR_EVENT_CHANGED) return;
    const self = user_data.self;
    const editor = user_data.editor;

    if(self.file_monitor != null) return;
    const file_monitor = self.file_monitor.?;
    self.file_monitor = null;
    gio.g_object_unref(file_monitor);

    // Unfortunately, when the backing file is modified, the whole mmapped
    // range is trashed, so we can't zero out only the unloaded pages.
    // (I've tried.)
    self.is_corrupt = true;
    self.data = posix.mmap(@alignCast(self.data.ptr), self.data.len, posix.PROT.READ, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0) catch unreachable;
    for(editor.buffers.items) |buffer| {
      if(buffer.root) |root| {
        root.update_stats(true);
      }
    }
    var iter = editor.copy_cache.valueIterator();
    while(iter.next()) |node| {
      node.*.update_stats(true);
    }
    editor.were_mmaps_corrupted = true;
  }
  fn gio_destroy_user_data(user_data: *GioCallbackUserData, _: *gio.GClosure) callconv(.C) void {
    user_data.editor.allocator.destroy(user_data);
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
        posix.munmap(@alignCast(self.data));
        if(self.file_monitor) |x| gio.g_object_unref(x);
        _ = editor.mmaps.swapRemove(std.mem.indexOfScalar(*Fragment, editor.mmaps.items, self).?);
      },
    }
    editor.allocator.destroy(self);
  }

  fn load(self: *Fragment, editor: *Editor) Allocator.Error!void {
    if(self.owner != .Mmap or self.is_corrupt) return;

    const data = self.data;
    posix.madvise(@alignCast(data.ptr), data.len, posix.MADV.SEQUENTIAL) catch {};
    self.data = try editor.allocator.dupe(u8, data);
    self.owner = .Allocator;

    posix.munmap(@alignCast(data));
    if(self.file_monitor) |x| gio.g_object_unref(x);
    _ = editor.mmaps.swapRemove(std.mem.indexOfScalar(*Fragment, editor.mmaps.items, self).?);

    for(editor.buffers.items) |buffer| {
      if(buffer.root) |root| {
        root.update_stats(true);
      }
    }
    var iter = editor.copy_cache.valueIterator();
    while(iter.next()) |node| {
      node.*.update_stats(true);
    }
  }
};

const Node = struct {
  refc: i32 = 0,
  is_frozen: bool = false,
  frag: struct {
    ptr: *Fragment,
    start: usize,
    end: usize,

    fn slice(self: @This()) []u8 {
      return self.ptr.data[self.start .. self.end];
    }

    fn len(self: @This()) usize {
      return self.end - self.start;
    }
  },

  priority: u32,
  left: ?*Node = null,
  right: ?*Node = null,
  stats: struct {
    bytes: usize,
    has_healthy_mmap: bool,
    has_corrupt_mmap: bool,
  },

  fn create(editor: *Editor, frag: *Fragment, start: usize, end: usize) Allocator.Error!*Node {
    assert(start < end and end <= frag.data.len);
    const self = try editor.allocator.create(Node);
    self.* = .{
      .frag = .{
        .ptr = frag.ref(),
        .start = start,
        .end = end,
      },
      .priority = editor.rng.random().int(@TypeOf(self.priority)),
      .stats = undefined,
    };
    self.update_stats(false);
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

  fn thaw(self: *Node, editor: *Editor) Allocator.Error!*Node {
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
      .left = if(self.left) |x| x.ref() else null,
      .right = if(self.right) |x| x.ref() else null,
      .stats = self.stats,
    };
    return copy;
  }

  fn load(self: *Node, editor: *Editor) Allocator.Error!void {
    try self.frag.ptr.load(editor);
    if(self.left) |x| {
      try x.load(editor);
    }
    if(self.right) |x| {
      try x.load(editor);
    }
  }

  fn set_left(self: *Node, editor: *Editor, value: ?*Node) void {
    assert(!self.is_frozen);
    if(self.left == value) return;
    if(self.left) |x| {
      x.unref(editor);
    }
    self.left = if(value) |x| x.ref() else null;
  }

  fn set_right(self: *Node, editor: *Editor, value: ?*Node) void {
    assert(!self.is_frozen);
    if(self.right == value) return;
    if(self.right) |x| {
      x.unref(editor);
    }
    self.right = if(value) |x| x.ref() else null;
  }

  fn update_stats(self: *Node, should_recurse: bool) void {
    self.stats.bytes = self.frag.end - self.frag.start;
    self.stats.has_healthy_mmap = false;
    self.stats.has_corrupt_mmap = false;
    if(self.frag.ptr.owner == .Mmap) {
      if(self.frag.ptr.is_corrupt) {
        self.stats.has_corrupt_mmap = true;
      } else {
        self.stats.has_healthy_mmap = true;
      }
    }

    if(self.left) |x| {
      if(should_recurse) {
        x.update_stats(true);
      }
      self.stats.bytes += x.stats.bytes;
      if(x.stats.has_healthy_mmap) {
        self.stats.has_healthy_mmap = true;
      }
      if(x.stats.has_corrupt_mmap) {
        self.stats.has_corrupt_mmap = true;
      }
    }

    if(self.right) |x| {
      if(should_recurse) {
        x.update_stats(true);
      }
      self.stats.bytes += x.stats.bytes;
      if(x.stats.has_healthy_mmap) {
        self.stats.has_healthy_mmap = true;
      }
      if(x.stats.has_corrupt_mmap) {
        self.stats.has_corrupt_mmap = true;
      }
    }
  }

  fn read(self: *Node, offset_: usize, dest: []u8) error {OutOfBounds}!usize {
    var offset = offset_;
    if(offset > self.stats.bytes) return error.OutOfBounds;
    if(dest.len <= 0) {
      return 0;
    }

    var readc: usize = 0;

    if(self.left) |left| {
      if(offset < left.stats.bytes) {
        readc += try left.read(offset, dest);
        offset = 0;
      } else {
        offset -= left.stats.bytes;
      }
    }

    const data = self.frag.slice();
    if(offset < data.len) {
      const data_slice = data[offset .. @min(offset + dest.len - readc, data.len)];
      @memcpy(dest[readc ..], data_slice);
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

  fn save(self: *Node, editor: *Editor, output: *gio.GOutputStream, err_msg: ?*?[]u8) GioError!void {
    if(self.left) |x| {
      try x.save(editor, output, err_msg);
    }

    const data = self.frag.slice();
    var err: ?*gio.GError = null;
    if(gio.g_output_stream_write_all(output, data.ptr, data.len, null, null, &err) == 0) return handle_gio_error(err.?, editor.allocator, err_msg);

    if(self.right) |x| {
      try x.save(editor, output, err_msg);
    }
  }

  fn merge(editor: *Editor, maybe_a: ?*Node, maybe_b: ?*Node) Allocator.Error!?*Node {
    var a = maybe_a orelse return maybe_b;
    var b = maybe_b orelse return maybe_a;
    if(a.priority >= b.priority) {
      const result = try a.thaw(editor);
      result.set_right(editor, try Node.merge(editor, a.right, b));
      result.update_stats(false);
      return result;
    } else {
      const result = try b.thaw(editor);
      result.set_left(editor, try Node.merge(editor, a, b.left));
      result.update_stats(false);
      return result;
    }
  }

  // We do this reference juggling so that a cleanly split off child doesn't get
  // garbage collected when unlinked from the parent.
  fn split_ref(self: *Node, editor: *Editor, offset_: usize) (Allocator.Error || error {OutOfBounds})!struct {?*Node, ?*Node} {
    var offset = offset_;
    if(offset == 0) {
      return .{null, self.ref()};
    }

    if(self.left) |left| {
      if(offset <= left.stats.bytes) {
        const b = try self.thaw(editor);
        const sub = try left.split_ref(editor, offset);
        b.set_left(editor, sub[1]);
        if(sub[1]) |x| x.unref(editor);
        b.update_stats(false);
        return .{sub[0], b.ref()};
      }
      offset -= left.stats.bytes;
    }

    if(offset < self.frag.end - self.frag.start) {
      const b = try Node.create(editor, self.frag.ptr, self.frag.start + offset, self.frag.end);
      b.set_right(editor, self.right);
      b.update_stats(false);
      const a = try self.thaw(editor);
      a.frag.end = a.frag.start + offset;
      a.set_right(editor, null);
      a.update_stats(false);
      return .{a.ref(), b.ref()};
    }
    offset -= self.frag.end - self.frag.start;

    if(self.right) |right| {
      if(offset < right.stats.bytes) {
        const a = try self.thaw(editor);
        const sub = try right.split_ref(editor, offset);
        a.set_right(editor, sub[0]);
        if(sub[0]) |x| x.unref(editor);
        a.update_stats(false);
        return .{a.ref(), sub[1]};
      }
      offset -= right.stats.bytes;
    }

    return if(offset == 0) .{self.ref(), null} else error.OutOfBounds;
  }
};

pub const Buffer = struct {
  editor: *Editor,
  root: ?*Node,

  pub fn create(editor: *Editor, root: ?*Node) Allocator.Error!*Buffer {
    const self = try editor.allocator.create(Buffer);
    errdefer editor.allocator.destroy(self);
    self.* = .{
      .editor = editor,
      .root = if(root) |x| x.ref() else null,
    };
    try self.editor.buffers.append(self);
    return self;
  }

  pub fn destroy(self: *Buffer) void {
    if(self.root) |x| {
      x.unref(self.editor);
    }
    _ = self.editor.buffers.swapRemove(std.mem.indexOfScalar(*Buffer, self.editor.buffers.items, self).?);
    self.editor.allocator.destroy(self);
  }

  pub fn load(self: *Buffer) Allocator.Error!void {
    if(self.root) |x| {
      return x.load(self.editor);
    }
  }

  pub fn len(self: *Buffer) usize {
    return if(self.root) |x| x.stats.bytes else 0;
  }

  pub fn has_healthy_mmap(self: *Buffer) bool {
    return if(self.root) |x| x.stats.has_healthy_mmap else false;
  }

  pub fn has_corrupt_mmap(self: *Buffer) bool {
    return if(self.root) |x| x.stats.has_corrupt_mmap else false;
  }

  pub fn read(self: *Buffer, offset: usize, dest: []u8) error {OutOfBounds}!usize {
    if(self.root) |x| {
      return x.read(offset, dest);
    } else if(offset > 0) {
      return error.OutOfBounds;
    } else {
      return 0;
    }
  }

  pub fn iter(self: *Buffer, offset_: usize) error {OutOfBounds}!Iterator {
    var offset = offset_;
    if(offset > self.len()) return error.OutOfBounds;

    var result = Iterator{ .buffer = self };
    if(self.root == null) return result;
    result.descend(self.root.?);

    while(true) {
      const node = result.node();

      if(node.left) |x| {
        if(offset < x.stats.bytes) {
          result.descend(x);
          continue;
        } else {
          offset -= x.stats.bytes;
        }
      }

      if(offset < node.frag.len()) {
        result.offset_in_node = offset;
        break;
      } else {
        offset -= node.frag.len();
      }

      if(node.right) |x| {
        result.descend(x);
      } else {
        result.offset_in_node = std.math.maxInt(@TypeOf(result.offset_in_node));
        break;
      }
    }

    return result;
  }

  pub const Iterator = struct {
    buffer: *Buffer,
    // With the high-end amount of RAM in today's computers, we can only store
    // at most two billion nodes. In a perfectly balanced binary tree that would
    // result in a height of around 31 - double that should be enough to account
    // for the unbalancedness of a treap.
    path: std.BoundedArray(*Node, 64) = std.BoundedArray(*Node, 64).init(0) catch unreachable,
    offset_in_node: usize = 0,
    last_advance: usize = 0,

    pub fn deinit(self: *Iterator) void {
      while(self.path.len > 0) {
        _ = self.ascend();
      }
    }

    fn node(self: *Iterator) *Node {
      return self.path.get(self.path.len - 1);
    }

    fn descend(self: *Iterator, into: *Node) void {
      self.path.append(into.ref()) catch unreachable;
    }

    fn ascend(self: *Iterator) *Node {
      const result = self.path.pop().?;
      result.unref(self.buffer.editor);
      return result;
    }

    fn next_node(self: *Iterator) error {OutOfBounds}!void {
      if(self.path.len <= 0) {
        if(self.offset_in_node > 0 or self.buffer.root == null) {
          return error.OutOfBounds;
        }
        self.descend(self.buffer.root.?);
        while(self.node().left) |x| {
          self.descend(x);
        }

      } else if(self.node().right) |x| {
        self.descend(x);
        while(self.node().left) |y| {
          self.descend(y);
        }

      } else while(true) {
        const child = self.ascend();
        if(self.path.len <= 0) {
          self.offset_in_node = std.math.maxInt(@TypeOf(self.offset_in_node));
          return error.OutOfBounds;
        }
        const parent = self.node();
        if(child != parent.right) break;
      }

      self.offset_in_node = 0;
    }

    fn prev_node(self: *Iterator) error {OutOfBounds}!void {
      if(self.path.len <= 0) {
        if(self.offset_in_node <= 0 or self.buffer.root == null) {
          return error.OutOfBounds;
        }
        self.descend(self.buffer.root.?);
        while(self.node().right) |x| {
          self.descend(x);
        }

      } else if(self.node().left) |x| {
        self.descend(x);
        while(self.node().right) |y| {
          self.descend(y);
        }

      } else while(true) {
        const child = self.ascend();
        if(self.path.len <= 0) {
          self.offset_in_node = 0;
          return error.OutOfBounds;
        }
        const parent = self.node();
        if(child != parent.left) break;
      }

      self.offset_in_node = self.node().frag.len();
    }

    pub fn next(self: *Iterator) ?u8 {
      if(self.path.len <= 0 or self.offset_in_node >= self.node().frag.len()) {
        self.next_node() catch return null;
      }
      defer self.offset_in_node += 1;
      return self.node().frag.slice()[self.offset_in_node];
    }

    pub fn prev(self: *Iterator) ?u8 {
      if(self.path.len <= 0 or self.offset_in_node <= 0) {
        self.prev_node() catch return null;
      }
      self.offset_in_node -= 1;
      return self.node().frag.slice()[self.offset_in_node];
    }

    pub fn rewind(self: *Iterator, count_: usize) error {OutOfBounds}!void {
      var count = count_;
      if(self.path.len <= 0) {
        try self.prev_node();
      }
      while(count > 0) {
        if(self.offset_in_node <= 0) {
          try self.prev_node();
        }
        const subtrahend = @min(count, self.offset_in_node);
        count -= subtrahend;
        self.offset_in_node -= subtrahend;
      }
    }

    // Deviates from Subsection "U+FFFD Substitution of Maximal Subparts",
    // Chapter 3 only in the handling of truncated overlong encodings and
    // truncated surrogate halves.
    pub fn next_codepoint(self: *Iterator) error {InvalidUtf8}!?u21 {
      var buf: [4]u8 = undefined;
      buf[0] = self.next() orelse return null;
      self.last_advance = 1;

      const bytec = std.unicode.utf8ByteSequenceLength(buf[0]) catch return error.InvalidUtf8;
      for(1 .. bytec) |i| {
        buf[i] = self.next() orelse return error.InvalidUtf8;
        if(buf[i] & 0b1100_0000 == 0b1000_0000) {
          self.last_advance += 1;
        } else {
          self.rewind(1) catch unreachable;
          return error.InvalidUtf8;
        }
      }

      return std.unicode.utf8Decode(buf[0 .. bytec]) catch {
        self.rewind(bytec - 1) catch unreachable;
        self.last_advance = 1;
        return error.InvalidUtf8;
      };
    }

    // Writing the result into a fixed-size buffer is inherently unsafe
    // because grapheme clusters can be arbitrarily long - see "Zalgo text".
    // Stops at a grapheme cluster break, or before the first UTF-8 error.
    pub fn next_grapheme(self: *Iterator, dest: *std.ArrayList(u8)) (Allocator.Error || error {InvalidUtf8})!?[]u8 {
      const start = dest.items.len;

      var buf: [4]u8 = undefined;
      var last_codepoint = try self.next_codepoint() orelse return null;
      try dest.appendSlice(buf[0 .. std.unicode.utf8Encode(last_codepoint, &buf) catch unreachable]);
      var last_advance = self.last_advance;
      defer self.last_advance = last_advance;

      var state: u16 = 0;
      while(true) {
        const lookahead = self.next_codepoint() catch {
          self.rewind(self.last_advance) catch unreachable;
          break;
        } orelse break;
        if(grapheme.grapheme_is_character_break(last_codepoint, lookahead, &state)) {
          self.rewind(self.last_advance) catch unreachable;
          break;
        }
        try dest.appendSlice(buf[0 .. std.unicode.utf8Encode(lookahead, &buf) catch unreachable]);
        last_codepoint = lookahead;
        last_advance += self.last_advance;
      }

      return dest.items[start ..];
    }
  };

  pub fn save(self: *Buffer, path: []const u8, err_msg: ?*?[]u8) (GioError || posix.OpenError || posix.RealPathError || posix.RenameError || error {MultipleHardLinks})!void {
    const path_z = try self.editor.allocator.dupeZ(u8, path);
    defer self.editor.allocator.free(path_z);
    return self.save_z(path_z, err_msg);
  }

  pub fn save_z(self: *Buffer, path: [*:0]const u8, err_msg: ?*?[]u8) (GioError || posix.OpenError || posix.RealPathError || posix.RenameError || error {MultipleHardLinks})!void {
    var err: ?*gio.GError = null;

    var output: *gio.GOutputStream = undefined;
    if(gio.g_uri_is_valid(path, gio.G_URI_FLAGS_NONE, null) != 0) {
      const file = gio.g_file_new_for_uri(path);
      defer gio.g_object_unref(file);
      output = @ptrCast(gio.g_file_replace(file, null, 0, gio.G_FILE_CREATE_NONE, null, &err) orelse return handle_gio_error(err.?, self.editor.allocator, err_msg));

    } else {
      var fd: posix.fd_t = undefined;

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
      const maybe_real_path = posix.realpathZ(path, &buf) catch |x| if(x == error.FileNotFound) null else return x;

      if(maybe_real_path) |real_path| {
        const dir_path = std.fs.path.dirname(real_path) orelse {
          return error.IsDir;
        };
        const name = std.fs.path.basename(real_path);

        const dir_fd = try posix.open(dir_path, .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
        var should_close_dir_fd = true;
        defer if(should_close_dir_fd) posix.close(dir_fd);

        fd = try posix.openat(dir_fd, name, .{ .ACCMODE = .WRONLY }, 0);
        var should_close_fd = true;
        defer if(should_close_fd) posix.close(fd);

        const stat = try posix.fstat(fd);

        var is_mmap = false;
        for(self.editor.mmaps.items) |mmap| {
          if(mmap.st_dev == stat.dev and mmap.st_ino == stat.ino) {
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
          try posix.renameat(dir_fd, name, dir_fd, new_name);
          try self.editor.moved_mmapped_files.append(.{ .dir_fd = dir_fd, .name = new_name });
          should_close_dir_fd = false;

          posix.close(fd);
          should_close_fd = false;
          fd = try posix.openat(dir_fd, name, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true }, stat.mode);

        } else {
          should_close_fd = false;
        }

      } else {
        fd = try posix.openZ(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true }, std.fs.File.default_mode);
      }

      output = gio.g_unix_output_stream_new(fd, 1);
    }
    defer gio.g_object_unref(output);

    if(self.root) |x| {
      try x.save(self.editor, output, err_msg);
    }
    if(gio.g_output_stream_close(output, null, &err) == 0) return handle_gio_error(err.?, self.editor.allocator, err_msg);
  }

  pub fn insert(self: *Buffer, offset: usize, data: []const u8) (Allocator.Error || error {OutOfBounds})!void {
    if(data.len <= 0) return;

    const copied_data = try self.editor.allocator.dupe(u8, data);
    errdefer self.editor.allocator.free(copied_data);
    const frag = try Fragment.create(self.editor, .Allocator, copied_data);
    errdefer frag.ref().unref(self.editor);
    const node = try Node.create(self.editor, frag, 0, data.len);
    errdefer node.ref().unref(self.editor);

    if(self.root) |root| {
      self.root = null;
      defer root.unref(self.editor);

      const a, const b = try root.split_ref(self.editor, offset);
      defer {
        if(a) |x| x.unref(self.editor);
        if(b) |x| x.unref(self.editor);
      }
      self.root = (try Node.merge(self.editor, try Node.merge(self.editor, a, node), b)).?.ref();

    } else {
      if(offset > 0) return error.OutOfBounds;
      self.root = node.ref();
    }
  }

  pub fn delete(self: *Buffer, start: usize, end: usize) (Allocator.Error || error {OutOfBounds})!void {
    if(start >= end) return;
    if(self.root == null) return error.OutOfBounds;

    const root = self.root.?;
    self.root = null;
    defer root.unref(self.editor);

    const ab, const c = try root.split_ref(self.editor, end);
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

  pub fn copy(self: *Buffer, offset: usize, src: *Buffer, start: usize, end: usize) (Allocator.Error || error {OutOfBounds})!void {
    assert(self.editor == src.editor);
    if(start >= end) return;
    if(src.root == null) return error.OutOfBounds;

    const node = if(self.editor.copy_cache.get(.{ .src = src.root.?, .start = start, .end = end })) |x| x else b: {
      src.root.?.is_frozen = true;
      const ab, const c = try src.root.?.split_ref(self.editor, end);
      defer {
        ab.?.unref(self.editor);
        if(c) |x| x.unref(self.editor);
      }
      const a, const b = try ab.?.split_ref(self.editor, start);
      defer {
        if(a) |x| x.unref(self.editor);
        b.?.unref(self.editor);
      }

      b.?.is_frozen = true; // …before we put it in the cache.
      try self.editor.copy_cache.putNoClobber(.{ .src = src.root.?, .start = start, .end = end }, b.?.ref());

      break :b b.?;
    };

    if(self.root) |root| {
      self.root = null;
      defer root.unref(self.editor);

      const a, const b = try root.split_ref(self.editor, offset);
      defer {
        if(a) |x| x.unref(self.editor);
        if(b) |x| x.unref(self.editor);
      }
      self.root = (try Node.merge(self.editor, try Node.merge(self.editor, a, node), b)).?.ref();

    } else {
      if(offset > 0) return error.OutOfBounds;
      self.root = node.ref();
    }
  }
};

pub const Editor = struct {
  allocator: Allocator,
  rng: std.Random.DefaultPrng,

  // This is actually a real configuration variable.
  max_open_size: usize = 100_000_000,

  mmaps: std.ArrayList(*Fragment),
  buffers: std.ArrayList(*Buffer),
  moved_mmapped_files: std.ArrayList(struct {
    dir_fd: posix.fd_t,
    name: [:0]u8,
  }),
  gio_async_ctx: *gio.GMainContext,
  were_mmaps_corrupted: bool = false,

  copy_cache: std.AutoHashMap(struct {
    src: *Node,
    start: usize,
    end: usize,
  }, *Node),

  pub fn init(allocator: Allocator) Editor {
    var self: Editor = undefined;
    self = .{
      .allocator = allocator,
      .rng = @TypeOf(self.rng).init(@bitCast(@as(i64, @truncate(std.time.nanoTimestamp())))),
      .mmaps = @TypeOf(self.mmaps).init(allocator),
      .buffers = @TypeOf(self.buffers).init(allocator),
      .moved_mmapped_files = @TypeOf(self.moved_mmapped_files).init(allocator),
      .gio_async_ctx = gio.g_main_context_new().?,
      .copy_cache = @TypeOf(self.copy_cache).init(allocator),
    };
    return self;
  }

  pub fn deinit(self: *Editor) void {
    self.mmaps.deinit();
    for(self.buffers.items) |x| {
      x.destroy();
    }
    self.buffers.deinit();
    for(self.moved_mmapped_files.items) |file| {
      // Multiple fragments can refer to the same file, just how there can be
      // many file descriptors referring to one file.
      posix.unlinkatZ(file.dir_fd, file.name, 0) catch {};
      posix.close(file.dir_fd);
      self.allocator.free(file.name);
    }
    self.moved_mmapped_files.deinit();
    gio.g_main_context_unref(self.gio_async_ctx);
    self.clear_copy_cache();
    self.copy_cache.deinit();
  }

  pub fn clear_copy_cache(self: *Editor) void {
    var iter = self.copy_cache.valueIterator();
    while(iter.next()) |node| {
      node.*.unref(self);
    }
    self.copy_cache.clearAndFree();
  }

  pub fn open(self: *Editor, path: []const u8, err_msg: ?*?[]u8) (GioError || posix.OpenError || posix.ReadError || posix.MMapError)!*Buffer {
    const path_z = try self.allocator.dupeZ(u8, path);
    defer self.allocator.free(path_z);
    return self.open_z(path_z, err_msg);
  }

  pub fn open_z(self: *Editor, path: [*:0]const u8, err_msg: ?*?[]u8) (GioError || posix.OpenError || posix.ReadError || posix.MMapError)!*Buffer {
    var err: ?*gio.GError = null;

    var frag: *Fragment = undefined;
    if(gio.g_uri_is_valid(path, gio.G_URI_FLAGS_NONE, null) != 0) {
      const file = gio.g_file_new_for_uri(path); // TODO: Mount admin:// locations
      defer gio.g_object_unref(file);

      var data: []u8 = undefined;
      if(gio.g_file_load_contents(file, null, @ptrCast(&data.ptr), &data.len, null, &err) == 0) return handle_gio_error(err.?, self.allocator, err_msg);
      errdefer gio.g_free(data.ptr);
      frag = try Fragment.create(self, .Glib, data);

    } else {
      const fd = try posix.openZ(path, .{ .ACCMODE = .RDONLY }, 0);
      defer posix.close(fd);
      const stat = try posix.fstat(fd);

      const size: usize = @intCast(stat.size);
      if(size <= self.max_open_size) {
        var data = try self.allocator.alloc(u8, size);
        errdefer self.allocator.free(data);
        data.len = try posix.read(fd, data);
        frag = try Fragment.create(self, .Allocator, data);

      } else {
        const data = try posix.mmap(null, size, posix.PROT.READ, .{ .TYPE = .PRIVATE }, fd, 0);
        errdefer posix.munmap(@alignCast(data));
        frag = try Fragment.create_mmap(self, data, stat.dev, stat.ino, path, err_msg);
      }
    }

    if(frag.data.len > 0) {
      errdefer frag.ref().unref(self);
      const root = try Node.create(self, frag, 0, frag.data.len);
      errdefer root.ref().unref(self);
      return Buffer.create(self, root);
    } else {
      frag.ref().unref(self);
      return Buffer.create(self, null);
    }
  }

  pub fn validate_mmaps(self: *Editor) bool {
    self.were_mmaps_corrupted = false;
    _ = gio.g_main_context_iteration(self.gio_async_ctx, 0);
    return self.were_mmaps_corrupted;
  }
};

pub const GioError = error {
  AccessDenied,
  BadPathName,
  ConnectionRefused,
  ConnectionResetByPeer,
  ConnectionTimedOut,
  DbusFailure,
  DeviceBusy,
  FdQuotaExceeded,
  FileNotFound,
  FileNotMounted,
  IsDir,
  LinkQuotaExceeded,
  NameServerFailure,
  NameTooLong,
  NetworkUnreachable,
  NoDevice,
  NoSpaceLeft,
  OutOfMemory,
  TemporaryNameServerFailure,
  TlsInitializationFailed,
  Unexpected,
  UnknownHostName,
};

// We try to mimic std.http.Client's and std.fs.File's errors here. Note that
// this handles only the errors that matter to Editor.open and Buffer.save.
// Both Glib's and Zig's errors are just some reduction and renaming of the
// POSIX errors, so to obtain this mapping I just had to search for the Glib
// error in its source code and then search for the corresponding POSIX error
// in std.posix's source code.
fn handle_gio_error(err: *gio.GError, allocator: Allocator, msg: ?*?[]u8) GioError {
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
      else => error.DbusFailure,
    };
  } else if(err.domain == gio.g_io_error_quark()) {
    return switch(err.code) {
      gio.G_IO_ERROR_NOT_FOUND => error.FileNotFound,
      gio.G_IO_ERROR_IS_DIRECTORY => error.IsDir,
      gio.G_IO_ERROR_FILENAME_TOO_LONG => error.NameTooLong,
      gio.G_IO_ERROR_INVALID_FILENAME => error.BadPathName,
      gio.G_IO_ERROR_TOO_MANY_LINKS => error.LinkQuotaExceeded,
      gio.G_IO_ERROR_NO_SPACE => error.NoSpaceLeft,
      gio.G_IO_ERROR_PERMISSION_DENIED => error.AccessDenied,
      gio.G_IO_ERROR_NOT_MOUNTED => error.FileNotMounted,
      gio.G_IO_ERROR_TIMED_OUT => error.ConnectionTimedOut,
      gio.G_IO_ERROR_BUSY => error.DeviceBusy,
      gio.G_IO_ERROR_HOST_NOT_FOUND => error.UnknownHostName,
      gio.G_IO_ERROR_TOO_MANY_OPEN_FILES => error.FdQuotaExceeded,
      gio.G_IO_ERROR_DBUS_ERROR => error.DbusFailure,
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
