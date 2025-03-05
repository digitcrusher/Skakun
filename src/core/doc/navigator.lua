-- Skakun - A robust and hackable hex and text editor
-- Copyright (C) 2024-2025 Karol "digitcrusher" Łacina
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

local tty = require('core.tty')
local utils = require('core.utils')

local Navigator = {
  tab_width = 8,
  global_cache_skip = 1e4,
  max_local_cache_size = 1e3,
}

function Navigator.of(buffer)
  if not buffer._navigator then
    buffer._navigator = Navigator.new(buffer)
  end
  return buffer._navigator
end

function Navigator.new(buffer)
  if not buffer.is_frozen then
    error('buffer is not frozen')
  end
  local self = setmetatable({
    buffer = buffer,
    local_cache = Navigator.Cache.new(),
    global_cache = Navigator.Cache.new(),
    local_cache2 = Navigator.Cache2.new(),
    global_cache2 = Navigator.Cache2.new(),
    time = 0,
    time2 = 0,
  }, { __index = Navigator })
  self.global_cache:insert({ byte = 1, line = 1, col = 1, last_tab = nil })
  self.global_cache2:insert({ byte = 1, line = 1, col = 1, last_tab = nil })
  return self
end

function Navigator:locate_byte(byte)
  return self:locate(function(loc) return loc.byte > byte end)
end

function Navigator:locate_line_col(line, col)
  return self:locate(function(loc) return loc.line == line and loc.col > col or loc.line > line end)
end

function Navigator:locate_nearest_tab(byte)
  return self:locate(function(loc) return loc.last_tab and loc.last_tab >= byte end)
end

function Navigator:measure(func)
  local a = os.clock()
  func()
  local b = os.clock()
  self.time = self.time + b - a
end
function Navigator:measure2(func)
  local a = os.clock()
  func()
  local b = os.clock()
  self.time2 = self.time2 + b - a
end
function Navigator:reset_profiling_data()
  self.time = 0
  self.local_cache.descents = 0
  self.local_cache.min_updates = 0
  self.local_cache.rotations = 0
  self.global_cache.descents = 0
  self.global_cache.min_updates = 0
  self.global_cache.rotations = 0
  self.time2 = 0
  self.local_cache2.descents = 0
  self.local_cache2.min_updates = 0
  self.local_cache2.splits = 0
  self.global_cache2.descents = 0
  self.global_cache2.min_updates = 0
  self.global_cache2.splits = 0
end

function Navigator:locate(is_too_far)
  local a, b, x, y
  self:measure(function()
    a = self.local_cache:search(is_too_far)
    b = self.global_cache:search(is_too_far)
  end)
  self:measure2(function()
    x = self.local_cache2:search(is_too_far)
    y = self.global_cache2:search(is_too_far)
  end)
  assert(((not a and not x) or a.byte == x.byte) and ((not b and not y) or b.byte == y.byte))

  local before = utils.copy(a and a.byte > b.byte and a or b)
  local iter = self.buffer:iter(before.byte)
  local after = utils.copy(before)
  local last_global_insert = b.byte

  while true do
    local ok, grapheme = pcall(iter.next_grapheme, iter)
    if not ok then
      grapheme = '�'
    elseif not grapheme then
      break
    end

    after.byte = before.byte + iter:last_advance()
    if grapheme == '\n' then
      after.line = before.line + 1
      after.col = 1
      after.last_tab = before.last_tab
    elseif grapheme == '\t' then
      after.line = before.line
      after.col = before.col + self.tab_width - (before.col - 1) % self.tab_width
      after.last_tab = before.byte
    else
      after.line = before.line
      after.col = before.col + tty.width_of(grapheme)
      after.last_tab = before.last_tab
    end

    if after.byte - last_global_insert >= self.global_cache_skip then
      self:measure(function()
        self.global_cache:insert(after)
      end)
      self:measure2(function()
        self.global_cache2:insert(after)
      end)
      last_global_insert = after.byte
    end

    if is_too_far(after) then
      break
    end
    local temp = before
    before = after
    after = temp
  end

  self:measure(function()
    self.local_cache:insert(before)
  end)
  self:measure2(function()
    self.local_cache2:insert(before)
  end)
  -- while self.local_cache.size > self.max_local_cache_size do
  --   self.local_cache:delete_random_leaf() -- TODO: delete_deepest_leaf
  -- end
  return before
end

Navigator.Cache = {}

function Navigator.Cache.new()
  return setmetatable({
    root = nil,
    size = 0,
    descents = 0,
    min_updates = 0,
    rotations = 0,
    time = 0,
  }, { __index = Navigator.Cache })
end

function Navigator.Cache:insert(loc)
  local new_node = {
    value = utils.copy(loc),
    -- is_frozen = false,
    left = nil,
    right = nil,
    min = utils.copy(loc),
  }
  if not self.root then
    self.root = new_node
    self.size = self.size + 1
    return true
  end

  local path = {}
  local node = self.root
  while node do
    self.descents = self.descents + 1
    -- self:hello(node)
    path[#path + 1] = node
    if loc.byte < node.value.byte then
      node = node.left
    elseif node.value.byte < loc.byte then
      node = node.right
    else
      return false
    end
  end

  -- self:thaw_path(path)
  if loc.byte < path[#path].value.byte then
    path[#path].left = new_node
  else
    path[#path].right = new_node
  end
  path[#path + 1] = new_node
  for i = #path - 1, 1, -1 do
    if path[i].min.byte < path[i + 1].min.byte then break end
    path[i].min = utils.copy(path[i + 1].min)
    self.min_updates = self.min_updates + 1
  end
  self:splay(path)

  self.size = self.size + 1
  return true
end

function Navigator.Cache:search(is_too_far)
  local path = {}
  local node = self.root
  while node do
    self.descents = self.descents + 1
    -- self:hello(node)
    path[#path + 1] = node
    if is_too_far(node.value) then
      node = node.left
    elseif node.right and not is_too_far(node.right.min) then
      node = node.right
    else
      self:splay(path)
      return node.value
    end
  end
  return nil
end

function Navigator.Cache:prune(probability)
end

-- function Navigator.Cache:delete_random_leaf()
--   local path = {}
--   local node = self.root
--   while node do
--     self:hello(node)
--     path[#path + 1] = node
--     if not node.left then
--       node = node.right
--     elseif not node.right then
--       node = node.left
--     else
--       node = math.random(2) == 1 and node.left or node.right
--     end
--   end
--   node = path[#path]

--   path[#path] = nil
--   self:thaw_path(path)
--   local parent = path[#path]
--   if node == parent.left then
--     parent.left = nil
--     parent.min = utils.copy(parent.value)
--     for i = #path - 1, 1, -1 do
--       if path[i + 1] ~= path[i].left then break end
--       path[i].min = utils.copy(path[i + 1].min)
--     end
--   else
--     parent.right = nil
--   end

--   self.size = self.size - 1
-- end

-- function Navigator.Cache:hello(node)
--   if node.is_frozen then
--     if node.left then
--       node.left.is_frozen = true
--     end
--     if node.right then
--       node.right.is_frozen = true
--     end
--   end
-- end

-- function Navigator.Cache:thaw_path(path)
--   if not path[#path].is_frozen then return end
--   assert(false)
--   path[#path] = self:copy_node(path[#path])
--   for i = #path - 1, 1, -1 do
--     local old = path[i]
--     if old.is_frozen then
--       path[i] = self:copy_node(old)
--     end
--     if path[i + 1].value.byte < path[i].value.byte then
--       path[i].left = path[i + 1]
--     else
--       path[i].right = path[i + 1]
--     end
--     if not old.is_frozen then return end
--   end
--   self.root = path[1]
-- end

-- function Navigator.Cache:copy_node(node)
--   return {
--     value = utils.copy(node.value),
--     is_frozen = false,
--     left = node.left,
--     right = node.right,
--     min = utils.copy(node.min),
--   }
-- end

function Navigator.Cache:splay(path)
  if math.random(32) ~= 1 then return end -- TWEAK AND SEE!
  -- self:thaw_path(path)
  for i = #path - 2, 1, -2 do
    self.rotations = self.rotations + 2
    local grandparent, parent, node = path[i], path[i + 1], path[i + 2]
    if parent == grandparent.left then
      if node.value.byte < parent.value.byte then
        self:rotate_left(grandparent, parent)
        self:rotate_left(parent, node)
      else
        self:rotate_right(parent, node)
        self:rotate_left(grandparent, node)
      end
    else
      if node.value.byte < parent.value.byte then
        self:rotate_left(parent, node)
        self:rotate_right(grandparent, node)
      else
        self:rotate_right(grandparent, parent)
        self:rotate_right(parent, node)
      end
    end
    path[i] = node
  end
  if #path % 2 == 0 then
    self.rotations = self.rotations + 1
    local parent, node = path[1], path[2]
    if node.value.byte < parent.value.byte then
      self:rotate_left(parent, node)
    else
      self:rotate_right(parent, node)
    end
    path[1] = node
  end
  self.root = path[1]
end

function Navigator.Cache:rotate_left(node, child)
  node.left = child.right
  node.min = utils.copy(node.left and node.left.min or node.value)
  child.right = node
end

function Navigator.Cache:rotate_right(node, child)
  node.right = child.left
  child.left = node
  child.min = utils.copy(child.left.min)
end

Navigator.Cache2 = {}

function Navigator.Cache2.new()
  return setmetatable({
    root = nil,
    size = 0,
    descents = 0,
    min_updates = 0,
    splits = 0,
  }, { __index = Navigator.Cache2 })
end

function Navigator.Cache2:insert(loc)
  local path = {}
  local node = self.root
  while node do
    self.descents = self.descents + 1
    path[#path + 1] = node
    if loc.byte < node.value.byte then
      node = node.left
    elseif node.value.byte < loc.byte then
      node = node.right
    else
      return false
    end
  end

  local node = {
    value = utils.copy(loc),
    priority = math.random(0),
    left = nil,
    right = nil,
    min = utils.copy(loc),
  }

  while #path > 0 and path[#path].priority <= node.priority do
    self.splits = self.splits + 1
    local child = path[#path]
    path[#path] = nil
    if child.value.byte < node.value.byte then
      child.right = node.left
      node.left = child
    else
      child.left = node.right
      child.min = utils.copy(child.left and child.left.min or child.value)
      node.right = child
    end
  end

  local parent = path[#path]
  if not parent then
    self.root = node
  elseif node.value.byte < parent.value.byte then
    parent.left = node
  else
    parent.right = node
  end

  if node.left then
    node.min = utils.copy(node.left.min)
  else
    path[#path + 1] = node
    for i = #path - 1, 1, -1 do
      if path[i].min.byte < path[i + 1].min.byte then break end
      path[i].min = utils.copy(path[i + 1].min)
      self.min_updates = self.min_updates + 1
    end
  end

  self.size = self.size + 1
  return true
end

function Navigator.Cache2:search(is_too_far)
  local node = self.root
  while node do
    self.descents = self.descents + 1
    if is_too_far(node.value) then
      node = node.left
    elseif node.right and not is_too_far(node.right.min) then
      node = node.right
    else
      return node.value
    end
  end
  return nil
end

return Navigator
