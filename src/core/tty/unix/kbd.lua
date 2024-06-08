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

local vt = require('core.tty.unix.vt')

-- This is a partial reimplementation of Linux's kbd input handler's behaviour.
-- Reference:
-- - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/tty/vt/keyboard.c
-- - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/keyboard.h
local Kbd = {
  keycodes = vt.keycodes,
  feed_buf = '',
}

function Kbd.new()
  return setmetatable({
    keycodes = setmetatable({}, { __index = Kbd.keycodes }),
  }, { __index = Kbd })
end

function Kbd:load_maps()
  self.keymap = vt.get_keymap()
  --self.accentmap = vt.get_accentmap()
end

function Kbd:feed(string)
  self.feed_buf = self.feed_buf .. string

  local result = {}

  local i = 1
  while i <= #self.feed_buf do
    local keycode, is_release
    keycode, is_release, i = self:read_keycode(self.feed_buf, i)
    if not keycode then break end

--    local ktyp = math.floor(keycode / 256)
--    local kval = keycode % 256
--    if keycode ==

    result[#result + 1] = {
      keycode = keycode,
      is_release = is_release,
    }
  end

  self.feed_buf = self.feed_buf:sub(i)

  return result
end

function Kbd:read_keycode(buf, offset)
  local a, b, c = buf:byte(offset, offset + 2)
  if not a then
    return nil, nil, offset
  elseif a & 0x7f ~= 0 then
    return a & 0x7f, a >= 0x80, offset + 1
  elseif c then
    return (b & 0x7f) << 7 | c & 0x7f, a >= 0x80, offset + 3
  else
    return nil, nil, offset
  end
end

return Kbd
