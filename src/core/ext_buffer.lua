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

local Buffer = require('core.buffer')

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

function ExtBuffer:read(start, end_)
  return self.buffer:read(start, end_)
end

function ExtBuffer:insert(offset, string)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.buffer:insert(offset, string)
end

function ExtBuffer:delete(start, end_)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.buffer:delete(start, end_)
end

function ExtBuffer:copy(offset, src, start, end_)
  if self.is_frozen then
    error('buffer is frozen')
  end
  self.buffer:copy(offset, src, start, end_)
end

function ExtBuffer:iter(offset)
  return self.buffer:iter(offset)
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
    copy:insert(0, self, 0, #self)
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
