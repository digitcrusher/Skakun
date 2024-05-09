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

local utils = {}

function utils.lock_globals()
  setmetatable(_G, {
    __newindex = function(table, key, value)
      error('cannot create new global variable: ' .. key)
    end,
    __index = function(table, key, value)
      error('undefined variable: ' .. key)
    end,
  })
end

function utils.unlock_globals()
  setmetatable(_G, nil)
end

function utils.hex_encode(string)
  local hex = ''
  for i = 1, #string do
    hex = hex .. string.format('%02x', string:byte(i, i))
  end
  return hex
end

function utils.hex_decode(hex)
  local string = ''
  for i = 1, #hex, 2 do
    string = string .. string.char(tonumber(hex:sub(i, i + 1), 16))
  end
  return string
end

return utils
