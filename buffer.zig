const std = @import("std");
const c = @cImport({
  @cInclude("fcntl.h");
  @cInclude("gio/gio.h");
  @cInclude("stdio.h");
  @cInclude("sys/mman.h");
  @cInclude("sys/stat.h");
});

const MemoryOwner = enum {
  Allocator, Glib, Mmap
};

const Fragment = struct {
  refc: i32 = 0,
  owner: MemoryOwner,
  data: []u8,

  fn create(editor: *Editor, owner: MemoryOwner, data: []u8) !*Fragment {
    const self = try editor.allocator.create(Fragment);
    self.* = .{
      .owner = owner,
      .data = data,
    };
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
        c.g_free(@ptrCast(self.data));
      },
      .Mmap => {
        if(c.munmap(@ptrCast(self.data), self.data.len) == 0) {
          c.perror("Failed to munmap fragment");
        }
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
    if(self.is_frozen) {
      @panic("set_left on frozen node");
    }
    if(self.left == value) return;
    if(self.left) |x| {
      x.unref(editor);
    }
    self.left = if(value) |x| x.ref() else null;
  }

  fn set_right(self: *Node, editor: *Editor, value: ?*Node) void {
    if(self.is_frozen) {
      @panic("set_right on frozen node");
    }
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
        if(sub[1]) |x| {
          x.unref(editor);
        }
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
        if(sub[0]) |x| {
          x.unref(editor);
        }
        a.update_stats();
        return .{a.ref(), sub[1]};
      }
      offset -= right.width;
    }

    return if(offset == 0) .{self.ref(), null} else error.OutOfBounds;
  }

  fn read(self: *Node, offset_: usize, dest_: []u8) !void {
    var offset = offset_;
    var dest = dest_;
    if(dest.len <= 0) return;
    if(offset + dest.len > self.width) {
      return error.OutOfBounds;
    }

    if(self.left) |left| {
      if(offset < left.width) {
        try left.read(offset, dest[0 .. @min(left.width - offset, dest.len)]);
        dest = dest[@min(left.width - offset, dest.len) ..];
        offset = 0;
      } else {
        offset -= left.width;
      }
    }

    const data = self.frag.ptr.data[self.frag.start .. self.frag.end];
    if(offset < data.len) {
      std.mem.copyForwards(u8, dest, data[offset .. @min(data.len, offset + dest.len)]);
      dest = dest[@min(data.len - offset, dest.len) ..];
      offset = 0;
    } else {
      offset -= data.len;
    }

    if(self.right) |right| {
      try right.read(offset, dest);
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

//  pub fn save(self: *Buffer, path: [:0]const u8) !void {
//
//  }
//
  pub fn read(self: *Buffer, offset: usize, dest: []u8) !void {
    if(self.root) |x| {
      try x.read(offset, dest);
    } else if(dest.len > 0) {
      return error.OutOfBounds;
    }
  }

  pub fn insert(self: *Buffer, offset: usize, data: []const u8) !void {
    if(self.is_frozen) {
      return error.BufferFrozen;
    }
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
      if(a) |x| {
        x.unref(self.editor);
      }
      if(b) |x| {
        x.unref(self.editor);
      }
    }
    self.root = (try Node.merge(self.editor, try Node.merge(self.editor, a, node), b)).?.ref();
  }

  pub fn delete(self: *Buffer, start: usize, end: usize) !void {
    if(self.is_frozen) {
      return error.BufferFrozen;
    }
    if(start >= end) return;
    if(self.root == null) {
      return error.OutOfBounds;
    }

    const old_root = self.root.?;
    self.root = null;
    defer old_root.unref(self.editor);

    const ab, const C = try old_root.split_ref(self.editor, end);
    defer {
      ab.?.unref(self.editor);
      if(C) |x| {
        x.unref(self.editor);
      }
    }
    const a, const b = try ab.?.split_ref(self.editor, start);
    defer {
      if(a) |x| {
        x.unref(self.editor);
      }
      b.?.unref(self.editor);
    }
    if(try Node.merge(self.editor, a, C)) |x| {
      self.root = x.ref();
    }
  }

  // pub fn copy(self: *Buffer, offset: usize, src: *Buffer, start: usize, end: usize) !void {
  //   if(self.is_frozen) {
  //     return error.BufferFrozen;
  //   } else if(!src.is_frozen) {
  //     return error.BufferNotFrozen;
  //   }
  //   // TODO
  // }
};

pub const Editor = struct {
  allocator: std.mem.Allocator,
  rng: std.rand.DefaultPrng,

  max_load_size: usize = 10_000_000,

  pub fn init(allocator: std.mem.Allocator) Editor {
    return .{
      .allocator = allocator,
      .rng = std.rand.DefaultPrng.init(@bitCast(@as(i64, @truncate(std.time.nanoTimestamp())))),
    };
  }

  pub fn load(self: *Editor, path: [*:0]const u8) !*Buffer {
    var owner: MemoryOwner = undefined;
    var data: []u8 = undefined;

    if(c.g_uri_is_valid(path, c.G_URI_FLAGS_NONE, null) != 0) {
      const file = c.g_file_new_for_uri(path); // TODO: Mount admin:// locations
      defer c.g_object_unref(file);

      owner = .Glib;
      var maybe_err: ?*c.GError = null;
      if(c.g_file_load_contents(file, null, @ptrCast(&data.ptr), &data.len, null, &maybe_err) == 0) {
        if(maybe_err) |err| {
          std.debug.print("Failed to load GIO file: {s}\n", .{err.message});
        } else {
          std.debug.print("Failed to load GIO file\n", .{});
        }
        return error.LoadError;
      }

    } else {
      const fd = c.open(path, c.O_RDONLY);
      if(fd == -1) {
        c.perror("Failed to open file");
        return error.OpenError;
      }
      defer if(c.close(fd) != 0) {
        c.perror("Failed to close file");
      };

      var stat: c.struct_stat = undefined;
      if(c.fstat(fd, &stat) != 0) {
        c.perror("Failed to stat file");
        return error.StatError;
      }
      const size: usize = @intCast(stat.st_size);

      if(size <= self.max_load_size) {
        owner = .Allocator;
        data = try self.allocator.alloc(u8, size);
        if(c.read(fd, @ptrCast(data), data.len) < 0) {
          c.perror("Failed to read file");
          return error.ReadError;
        }

      } else {
        owner = .Mmap;
        data = @as([*]u8, @ptrCast(c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0)))[0 .. size];
      }
    }

    return try Buffer.create(self, try Node.create(self, try Fragment.create(self, owner, data), 0, data.len));
  }
};
