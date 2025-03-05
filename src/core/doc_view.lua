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

local here = ...
local Navigator = require('core.doc.navigator')
local stderr = require('core.stderr')
local tty = require('core.tty')
local utils = require('core.utils')

local DocView = {
  should_soft_wrap = false,
  foreground = nil,
  background = nil,
}

function DocView.new(doc)
  return setmetatable({
    doc = doc,
    line = 1,
    col = 1,
  }, { __index = DocView })
end

function DocView:draw(x1, y1, x2, y2)
  if self.should_soft_wrap then
    self:draw_soft_wrap(x1, y1, x2, y2)
  else
    self:draw_cut_off(x1, y1, x2, y2)
  end
end

local ctrl_pics = {
  ['\127'] = '␡',
}
for i, ctrl_pic in ipairs({
  '␀', '␁', '␂', '␃', '␄', '␅', '␆', '␇', '␈', '␉', '␊', '␋', '␌', '␍', '␎', '␏',
  '␐', '␑', '␒', '␓', '␔', '␕', '␖', '␗', '␘', '␙', '␚', '␛', '␜', '␝', '␞', '␟',
}) do
  ctrl_pics[string.char(i - 1)] = ctrl_pic
end

function DocView:draw_soft_wrap(x1, y1, x2, y2)
  tty.set_foreground(utils.unpack_color(self.foreground))
  tty.set_background(utils.unpack_color(self.background))

  self.doc.buffer:freeze()
  local nav = Navigator.of(self.doc.buffer)
  local loc = nav:locate_line_col(self.line, self.col)
  local iter = self.doc.buffer:iter(loc.byte)

  for y = y1, y2 do
    local x = x1
    tty.move_to(x, y)

    while true do
      local grapheme = self:next_grapheme(iter, loc, nav)
      if not grapheme then
        loc.line = loc.line + 1
        loc.col = 1
        break
      end

      local width = tty.width_of(grapheme)
      if x + width - 1 > x2 then
        iter:rewind(iter:last_advance())
        break
      end

      tty.write(grapheme)
      x = x + width
      loc.col = loc.col + width
    end

    tty.write((' '):rep(x2 - x + 1))
  end
end

function DocView:draw_cut_off(x1, y1, x2, y2)
  tty.set_foreground(utils.unpack_color(self.foreground))
  tty.set_background(utils.unpack_color(self.background))

  self.doc.buffer:freeze()
  local nav = Navigator.of(self.doc.buffer)
  nav:reset_profiling_data()

  for y = y1, y2 do
    local x = x1
    tty.move_to(x, y)

    local loc = nav:locate_line_col(self.line + y - y1, self.col)
    local iter = self.doc.buffer:iter(loc.byte)

    if loc.col < self.col then
      local grapheme = self:next_grapheme(iter, loc, nav)
      if not grapheme then
        iter:rewind(iter:last_advance())
      else
        loc.col = loc.col + tty.width_of(grapheme)
        local width = loc.col - self.col
        if x + width - 1 > x2 then break end

        tty.write((' '):rep(width))
        x = x + width
      end
    end

    while true do
      local grapheme = self:next_grapheme(iter, loc, nav)
      if not grapheme then break end

      local width = tty.width_of(grapheme)
      if x + width - 1 > x2 then break end

      tty.write(grapheme)
      x = x + width
      loc.col = loc.col + width
    end

    tty.write((' '):rep(x2 - x + 1))
  end

  stderr.info(
    here,
    self.line, ':', self.col, '\t ',
    'descents ', nav.local_cache.descents + nav.global_cache.descents, '\t',
    'min_updates ', nav.local_cache.min_updates + nav.global_cache.min_updates, '\t',
    'rotations ', nav.local_cache.rotations + nav.global_cache.rotations, '\t',
    'time ', math.floor(1e6 * nav.time), 'µs\t ',
    'descents ', nav.local_cache2.descents + nav.global_cache2.descents, '\t',
    'min_updates ', nav.local_cache2.min_updates + nav.global_cache2.min_updates, '\t',
    'splits ', nav.local_cache2.splits + nav.global_cache2.splits, '\t',
    'time ', math.floor(1e6 * nav.time2), 'µs\t '
  )
end

function DocView:next_grapheme(iter, loc, nav)
  local ok, grapheme = pcall(iter.next_grapheme, iter)
  if not ok then
    return '�'
  elseif not grapheme or grapheme == '\n' then
    return nil
  elseif grapheme == '\t' then
    return (' '):rep(nav.tab_width - (loc.col - 1) % nav.tab_width)
  else
    return ctrl_pics[grapheme] or grapheme
  end
end

return DocView

-- Every grapheme, once added, must have a constant width over its entire lifetime. In particular, it can't depend on its position in the text. The only hard-coded exception to this rule are tabs.
