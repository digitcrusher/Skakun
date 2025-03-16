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

local Widget = {}
Widget.__index = Widget

function Widget.new()
  return setmetatable({
    parent = nil,
    left = nil,
    top = nil,
    right = nil,
    bottom = nil,
  }, Widget)
end

function Widget:compute_layout() end
function Widget:draw() end
function Widget:handle_event() end

function Widget:width()
  return self.right - self.left + 1
end

function Widget:height()
  return self.bottom - self.top + 1
end

return Widget
