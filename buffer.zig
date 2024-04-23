const std = @import("std");
const c = @cImport({
  @cInclude("fcntl.h");
  @cInclude("gio/gio.h");
  @cInclude("stdio.h");
  @cInclude("sys/mman.h");
  @cInclude("sys/stat.h");
});

const Owner = enum {
  Allocator, Glib, Mmap
};

const Fragment = struct {
  refc: i32 = 0,
  owner: Owner,
  data: []u8,

  fn create(buf: *Buffer, owner: Owner, data: []u8) !*Fragment {
    const self = try buf.allocator.create(Fragment);
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

  fn unref(self: *Fragment, buf: *Buffer) void {
    self.refc -= 1;
    if(self.refc > 0) return;
    switch(self.owner) {
      .Allocator => {
        buf.allocator.free(self.data);
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
    buf.allocator.destroy(self);
  }
};

const Node = struct {
  refc: i32 = 0,
  frag: struct {
    ptr: *Fragment,
    start: usize,
    end: usize,
  },

  priority: u32,
  left: ?*Node = null,
  right: ?*Node = null,
  is_frozen: bool = false,
  width: usize,

  fn create(buf: *Buffer, frag: *Fragment, start: usize, end: usize) !*Node {
    const self = try buf.allocator.create(Node);
    self.* = .{
      .frag = .{
        .ptr = frag.ref(),
        .start = start,
        .end = end,
      },
      .priority = buf.rng.random().int(@TypeOf(self.priority)),
      .width = undefined,
    };
    self.update_stats();
    return self;
  }

  fn ref(self: *Node) *Node {
    self.refc += 1;
    return self;
  }

  fn unref(self: *Node, buf: *Buffer) void {
    self.refc -= 1;
    if(self.refc > 0) return;
    if(self.left) |x| {
      x.unref(buf);
    }
    if(self.right) |x| {
      x.unref(buf);
    }
    self.frag.unref(buf);
    buf.allocator.destroy(self);
  }

  fn melt(self: *Node, buf: *Buffer) !*Node {
    if(!is_frozen) {
      return self;
    }
    self.left.is_frozen = true;
    self.right.is_frozen = true;
    const copy = try buf.allocator.create(Node);
    copy.* = .{
      .frag = .{
        .ptr = self.frag.ptr.ref(),
        .start = self.frag.start,
        .end = self.frag.end,
      },
      .priority = self.priority,
      .width = self.width,
    };
    copy.set_left(self.left);
    copy.set_right(self.right);
    return copy;
  }

  fn set_left(self: *Node, buf: *Buffer, value: ?*Node) void {
    assert(!self.is_frozen);
    if(self.left == value) return;
    if(self.left) |x| {
      x.unref(buf);
    }
    self.left = if(value) |x| x.ref() else null;
    self.update_stats();
  }

  fn set_right(self: *Node, buf: *Buffer, value: ?*Node) void {
    assert(!self.is_frozen);
    if(self.right == value) return;
    if(self.right) |x| {
      x.unref(buf);
    }
    self.right = if(value) |x| x.ref() else null;
    self.update_stats();
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
};

pub const Buffer = struct {
  allocator: std.mem.Allocator,
  rng: std.rand.DefaultPrng,

  edit_mutex: std.Thread.Mutex = .{},
  is_editing: bool = false,
  working_state: ?*Node = null,
  history: std.ArrayList(*Node),
  present_idx: usize = 0,
  commit_delay_ms: u64 = 5_000,
  last_edit: i64 = std.math.minInt(i64),

  path: ?[:0]u8 = null,
  is_uri: ?bool = null,
  max_load_size: usize = 10_000_000,

  pub fn init(allocator: std.mem.Allocator) Buffer {
    return .{
      .allocator = allocator,
      .rng = std.rand.DefaultPrng.init(@bitCast(@as(i64, @truncate(std.time.nanoTimestamp())))),
      .history = std.ArrayList(*Node).init(allocator),
    };
  }

  pub fn deinit(self: *Buffer) void {
    for(self.history.items) |x| {
      x.unref(self);
    }
    self.history.deinit();
    self.set_path(null) catch unreachable;
  }

  pub fn set_path(self: *Buffer, path: ?[]const u8) !void {
    if(self.path) |x| {
      self.allocator.free(x);
    }
    if(path) |x| {
      self.path = try self.allocator.dupeZ(u8, x);
      self.is_uri = c.g_uri_is_valid(self.path.?, c.G_URI_FLAGS_NONE, null) != 0;
    } else {
      self.path = null;
      self.is_uri = null;
    }
  }

  pub fn begin(self: *Buffer) void {
    self.edit_mutex.lock();
    self.is_editing = true;
  }

  pub fn end(self: *Buffer) void {
    self.is_editing = false;
    self.edit_mutex.unlock();
  }

  pub fn load(self: *Buffer) !void {
    if(self.path == null or self.is_uri == null) {
      return error.PathUnspecified;
    }

    var owner: Owner = undefined;
    var data: []u8 = undefined;

    if(self.is_uri.?) {
      const file = c.g_file_new_for_uri(self.path.?); // TODO: Mount admin:// locations
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
      const fd = c.open(self.path.?, c.O_RDONLY);
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

    self.push_edit(try Node.create(self, try Fragment.create(self, owner, data)));
  }

//  pub fn save(self: *Buffer) void {
//
//  }
//
//  pub fn read(self: *Buffer, offset: usize, dest: []u8) !void {
//    if(dest.len <= 0) return;
//  }
//

  pub fn undo(self: *Buffer, count: usize) usize {
    const change = @min(count, self.present_idx);
    self.present_idx -= change;
    return change;
  }

  pub fn redo(self: *Buffer: count: usize) usize {
    const change = @min(count, @max(1, self.history.items.len) - 1 - self.present_idx);
    self.present_idx += change;
    return change;
  }

  fn present(self: *Buffer) ?*Node {
    return if(self.present_idx < self.history.items.len) self.history.items[self.present_idx] else null;
  }

  fn push_edit(self: *Buffer, node: *Node) !void {
    if(self.present_idx + 1 < self.history.items.len) {
      for(self.history.items[self.present_idx + 1 ..]) |x| {
        x.unref(self);
      }
      try self.history.resize(self.present_idx + 1);
      self.last_edit = std.math.minInt(@TypeOf(self.last_edit));
    }

    const now = self.time.milliTimestamp();
    if(now - self.last_edit < self.commit_delay_ms) {
      self.history.getLast().unref(self);
      try self.history.resize(self.history.items.len - 1);
    }
    try self.history.append(node.ref());
    self.present_idx = self.history.items.len - 1;
    self.last_edit = now;
  }

  pub fn insert(self: *Buffer, offset: usize, data: []u8) !void {
    return self.insert_node(offset, try Node.create(self, try Fragment.create(self, .Allocator, try self.allocator.dupe(u8, data)), 0, data.len));
  }

  fn insert_node(self: *Buffer, offset: usize, node: *Node) !void {
    const present = self.present() orelse {
      if(offset > 0) {
        return error.OutOfBounds;
      }
      try self.push_edit(node);
      return;
    };
    const a, const b = self.split(present, offset);
    try self.push_edit(self.merge(self.merge(a, node), b));
  }

  pub fn delete(self: *Buffer, start: usize, end: usize) !void {
    if(start >= end) return;
    const present = self.present() orelse return error.OutOfBounds;
    const ab, const c = self.split(present, end);
    const a, const b = self.split(ab, start);
    b.unref(self); // TODO: ??????
    try self.push_edit(self.merge(a, c));
  }

  fn merge(self: *Buffer, maybe_a: ?*Node, maybe_b: ?*Node) ?*Node {
    var a = maybe_a orelse return maybe_b;
    var b = maybe_b orelse return maybe_a;
    if(a.priority >= b.priority) {
      const result = try a.melt(self);
      result.set_right(self, self.merge(a.right, b));
      return result;
    } else {
      const result = try b.melt(self);
      result.set_left(self, self.merge(a, b.left));
      return result;
    }
  }

  fn split(self: *Buffer, node: *Node, offset: usize) !struct {?*Node, ?*Node} {
    if(offset == 0) {
      return .{null, node};
    }

    if(node.left) |left| {
      if(offset <= left.width) {
        const b = try node.melt(self);
        const sub = self.split(left, offset);
        b.set_left(sub[1]);
        return .{sub[0], b};
      }
      offset -= left.width;
    }

    if(offset < node.frag.end - node.frag.start) {
      const b = try Node.create(self, node.frag.ptr, offset, node.frag.end);
      b.set_right(node.right);
      const a = try node.melt(self);
      a.frag.end = offset;
      a.set_right(null);
      return .{a, b};
    }
    offset -= node.frag.end - node.frag.start;

    if(node.right) |right| {
      if(offset < right.width) {
        const a = try node.melt(self);
        const sub = self.split(right, offset);
        a.set_right(sub[0]);
        return .{a, sub[1]};
      }
      offset -= right.width;
    }

    return if(offset == 0) .{node, null} else error.OutOfBounds;
  }
};
