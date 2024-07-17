-- Skakun - A robust and hackable hex and text editor
-- Copyright (C) 2024 Karol "digitcrusher" Łacina
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
local stderr = require('core.stderr')
local tty = require('core.tty')
local utils = require('core.utils')

local DocView = {
  tab_width = 8,
  should_soft_wrap = false,
  foreground = nil,
  background = nil,
}

function DocView.new(doc)
  return setmetatable({
    doc = doc,
    cursor = 1,
  }, { __index = DocView })
end

function DocView:draw(x1, y1, x2, y2)
  if self.should_soft_wrap then
    self:draw_soft_wrap(x1, y1, x2, y2)
  else
    self:draw_cut_off(x1, y1, x2, y2)
  end
end

function DocView:draw_soft_wrap(x1, y1, x2, y2)
  tty.set_foreground(utils.unpack_color(self.foreground))
  tty.set_background(utils.unpack_color(self.background))

  local iter = self.doc.buffer:iter(self.cursor)

  for y = y1, y2 do
    local x = x1
    tty.move_to(x, y)

    while x <= x2 do
      local ok, grapheme = pcall(iter.next_grapheme, iter)
      if not ok then
        grapheme = '�'
      elseif not grapheme or grapheme == '\n' then break end

      local width = tty.width_of(grapheme)
      if x + width - 1 > x2 then
        iter:rewind(iter:last_advance())
        break
      end

      tty.write(grapheme)
      x = x + width
    end

    while x <= x2 do
      tty.write(' ')
      x = x + 1
    end
  end
end

function DocView:draw_cut_off(x1, y1, x2, y2)
  tty.set_foreground(utils.unpack_color(self.foreground))
  tty.set_background(utils.unpack_color(self.background))

  local start_loc = self.doc.buffer:locate_byte(self.cursor)

  for y = y1, y2 do
    local x = x1
    tty.move_to(x, y)

    local line = start_loc.line + y - y1
    local col = start_loc.col
    local loc = self.doc.buffer:locate_line_col(line, col)
    local iter = self.doc.buffer:iter(loc.byte)
    if loc.col ~= col then
      for i = loc.col + 1, col do
        if x > x2 then break end
        tty.write(' ')
        x = x + 1
      end
      local _, grapheme = pcall(iter.next_grapheme, iter)
      if grapheme == '\n' then
        iter:rewind(iter:last_advance())
      end
    end

    while x <= x2 do
      local ok, grapheme = pcall(iter.next_grapheme, iter)
      if not ok then
        grapheme = '�'
      elseif not grapheme or grapheme == '\n' then break end

      local width = tty.width_of(grapheme)
      if x + width - 1 > x2 then break end

      tty.write(grapheme)
      x = x + width
    end

    while x <= x2 do
      tty.write(' ')
      x = x + 1
    end
  end
end

return DocView

-- Every grapheme, once added, must have a constant width over its entire lifetime. In particular, it can't depend on its position in the text, which for example means that tabs can't work as you'd expect them to.
