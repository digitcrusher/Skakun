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

local DocBuffer = require('core.doc.buffer')

local Doc = {}
Doc.__index = Doc

function Doc.new()
  return setmetatable({
    buffer = DocBuffer.new(),
    path = nil,
  }, Doc)
end

function Doc.open(path)
  return setmetatable({
    buffer = DocBuffer.open(path),
    path = path,
  }, Doc)
end

function Doc:save(path)
  if path then
    self.buffer:save(path)
  elseif not self.path then
    error('path not set')
  else
    self.buffer:save(self.path)
  end
end

return Doc
