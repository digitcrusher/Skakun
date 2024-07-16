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
  foreground = nil,
  background = nil,
}

function DocView.new(doc)
  return setmetatable({
    doc = doc,
    cursor = 0,
  }, { __index = DocView })
end

function DocView:draw(x1, y1, x2, y2)
  tty.set_foreground(utils.unpack_color(self.foreground))
  tty.set_background(utils.unpack_color(self.background))

  local iter = self.doc.buffer:iter(0)
  for y = y1, y2 do
    local x = x1
    tty.move_to(x, y)

    while x <= x2 do
      local ok, char = pcall(iter.next_grapheme, iter)
      if not ok then
        char = {0xfffd}
      elseif not char then break end
      char = utf8.char(table.unpack(char))
      if char == '\n' then break end

      local width = tty.width_of(char)
      if x + width - 1 > x2 then
        iter:rewind(iter:last_advance())
        break
      end

      tty.write(char)
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
