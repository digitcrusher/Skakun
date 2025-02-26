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

local Buffer = require('core.buffer')
local tty = require('core.tty')

local ExtBuffer = {}

function ExtBuffer.new()
  return setmetatable({
    buffer = Buffer.new(),
    is_frozen = false,
    freeze_time = nil,
  }, {
    __index = ExtBuffer,
    __len = ExtBuffer.__len,
  })
end

function ExtBuffer.open(path)
  return setmetatable({
    buffer = Buffer.open(path),
    is_frozen = false,
    freeze_time = nil,
  }, {
    __index = ExtBuffer,
    __len = ExtBuffer.__len,
  })
end

function ExtBuffer:save(path)
  self.buffer:save(path)
end

function ExtBuffer:__len()
  return #self.buffer
end

function ExtBuffer:read(from, to)
  return self.buffer:read(from, to)
end

function ExtBuffer:iter(from)
  return self.buffer:iter(from)
end

function ExtBuffer:locate_byte(byte)
  return self:_locate(byte, nil, nil)
end

function ExtBuffer:locate_line_col(line, col)
  return self:_locate(nil, line, col)
end

-- Highly (un)optimized code, watch out!
function ExtBuffer:_locate(byte, line, col)
  local before = { byte = 1, line = 1, col = 1 }

  local iter = self:iter()
  local after = {}
  while true do
    local ok, grapheme = pcall(iter.next_grapheme, iter)
    if not ok then break end

    after.byte = before.byte + iter:last_advance()
    if grapheme == '\n' then
      after.line = before.line + 1
      after.col = 1
    else
      after.line = before.line
      after.col = before.col + tty.width_of(grapheme)
    end

    if byte and after.byte > byte then break end
    if after.line == line and after.col > col or line and after.line > line then break end
    local temp = before
    before = after
    after = temp
  end

  return before
end

function ExtBuffer:insert(idx, string)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.buffer:insert(idx, string)
end

function ExtBuffer:delete(from, to)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.buffer:delete(from, to)
end

function ExtBuffer:copy(idx, src, from, to)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.buffer:copy(idx, src, from, to)
end

function ExtBuffer:freeze()
  if not self.is_frozen then
    self.is_frozen = true
    self.freeze_time = os.clock()
  end
end

function ExtBuffer:thaw()
  if self.is_frozen then
    local copy = ExtBuffer.new()
    copy:insert(1, self, 1, #self)
    return copy
  else
    return self
  end
end

function ExtBuffer:load()
  self.buffer:load()
end

function ExtBuffer:has_healthy_mmap()
  return self.buffer:has_healthy_mmap()
end

function ExtBuffer:has_corrupt_mmap()
  return self.buffer:has_corrupt_mmap()
end

function ExtBuffer.validate_mmaps()
  return Buffer.validate_mmaps()
end

return ExtBuffer
