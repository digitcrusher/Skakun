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

local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local encode_map, decode_map = {}, {}
for i = 1, #alphabet do
  encode_map[i - 1] = alphabet:sub(i, i)
  decode_map[alphabet:byte(i, i)] = i - 1
end

function utils.base64_encode(string)
  local base64 = ''

  local i = 1
  while i + 2 <= #string do
    local a, b, c = string:byte(i, i + 2)
    base64 = base64 .. encode_map[math.floor(a / 4)] .. encode_map[a % 4 * 16 + math.floor(b / 16)] .. encode_map[b % 16 * 4 + math.floor(c / 64)] .. encode_map[c % 64]
    i = i + 3
  end

  local a, b = string:byte(i, i + 1)
  if b then
    base64 = base64 .. encode_map[math.floor(a / 4)] .. encode_map[a % 4 * 16 + math.floor(b / 16)] .. encode_map[b % 16 * 4] .. '='
  elseif a then
    base64 = base64 .. encode_map[math.floor(a / 4)] .. encode_map[a % 4 * 16] .. '=='
  end

  return base64
end

function utils.base64_decode(base64)
  local string = ''

  local len
  if base64:sub(-2, -2) == '=' then
    len = #base64 - 2
  elseif base64:sub(-1, -1) == '=' then
    len = #base64 - 1
  else
    len = #base64
  end

  local i = 1
  while i + 3 <= len do
    local a, b, c, d = base64:byte(i, i + 3)
    a, b, c, d = decode_map[a], decode_map[b], decode_map[c], decode_map[d]
    string = string .. string.char(a * 4 + b / 16) .. string.char(b % 16 * 16 + c / 4) .. string.char(c % 4 * 64 + d)
    i = i + 4
  end

  local a, b, c = base64:byte(i, i + 2)
  a, b, c = decode_map[a], decode_map[b], decode_map[c]
  if c then
    string = string .. string.char(a * 4 + b / 16) .. string.char(b % 16 * 16 + c / 4)
  elseif b then
    string = string .. string.char(a * 4 + b / 16)
  end

  return string
end

return utils
