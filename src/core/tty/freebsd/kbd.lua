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

local system = require('core.tty.freebsd.system')
local c = system

-- Reference:
-- - https://cgit.freebsd.org/src/tree/sys/dev/vt/vt_core.c (vt_kbdevent)
-- - https://cgit.freebsd.org/src/tree/sys/dev/atkbdc/atkbd.c (atkbd_read_char)
-- - https://cgit.freebsd.org/src/tree/sys/dev/kbd/kbd.c (genkbd_keyaction)
-- - https://cgit.freebsd.org/src/tree/sys/sys/kbio.h

local Kbd = {
  keycodes = system.keycodes,
  feed_buf = '',
  active_accent = nil,
}

function Kbd.new()
  return setmetatable({
    keycodes = setmetatable({}, { __index = Kbd.keycodes }),
    keymap = system.get_keymap(),
    accentmap = system.get_accentmap(),
    is_pressed = {},
    state = system.get_kbd_locks(),
    last_action = {},
  }, { __index = Kbd })
end

function Kbd:feed(string)
  self.feed_buf = self.feed_buf .. string

  local result = {}

  local i = 1
  while i <= #self.feed_buf do
    local keycode, is_release
    keycode, is_release, i = self:read_keycode(self.feed_buf, i)
    if not keycode then break end

    local type = is_release and 'release' or (self.is_pressed[keycode] and 'repeat' or 'press')
    self.is_pressed[keycode] = not is_release
    local _, text = pcall(self.handle_keycode, self, keycode, is_release)

    result[#result + 1] = {
      type = type,
      keycode = self.keycodes[keycode],
      text = text,
    }
  end
  self.feed_buf = self.feed_buf:sub(i)

  return result
end

function Kbd:read_keycode(buf, offset)
  local a = buf:byte(offset)
  if a then
    return a & 0x7f, a >= 0x80, offset + 1
  else
    return nil, nil, offset
  end
end

function Kbd:handle_keycode(keycode, is_release)
  local altgr_state = self.state & (c.AGRS | c.ALKED)
  local shifted_keycode = keycode
  if altgr_state == c.AGRS1 or altgr_state == c.AGRS2 or altgr_state == c.ALKED then
    shifted_keycode = shifted_keycode + c.ALTGR_OFFSET
  end
  local key = self.keymap[shifted_keycode]

  local locks = {
    [c.NLK] = { LKDOWN = c.NLKDOWN, LKED = c.NLKED },
    [c.CLK] = { LKDOWN = c.CLKDOWN, LKED = c.CLKED },
    [c.SLK] = { LKDOWN = c.SLKDOWN, LKED = c.SLKED },
    [c.ALK] = { LKDOWN = c.ALKDOWN, LKED = c.ALKED },
  }
  local altgr_lock_shifts = {
    [c.LSHA] = c.LSH,
    [c.RSHA] = c.RSH,
    [c.LCTRA] = c.LCTR,
    [c.RCTRA] = c.RCTR,
    [c.LALTA] = c.LALT,
    [c.RALTA] = c.RALT,
  }
  local shifts = {
    [c.LSH] = c.SHIFTS1,
    [c.RSH] = c.SHIFTS2,
    [c.LCTR] = c.CTLS1,
    [c.RCTR] = c.CTLS2,
    [c.LALT] = c.ALTS1,
    [c.RALT] = c.ALTS2,
    [c.ASH] = c.AGRS1,
    [c.META] = c.METAS1,
  }

  if is_release then
    local action = self.last_action[keycode]
    self.last_action[keycode] = nil

    if altgr_lock_shifts[action] then
      if self.state & c.SHIFTAON ~= 0 then
        if self.state & c.ALKDOWN == 0 then
          self.state = self.state ~ c.ALKED | c.ALKDOWN
          system.set_kbd_locks(self.state & c.LOCK_MASK)
        end
        self.state = self.state & ~c.ALKDOWN
      end
      action = altgr_lock_shifts[action]
    end

    if shifts[action] or locks[action] then
      self.state = self.state & ~(shifts[action] or locks[action].LKDOWN)
    end

    self.state = self.state & ~c.SHIFTAON
    return
  end

  local shift = (self.state & c.SHIFTS ~= 0 and 1 or 0) |
                (self.state & c.CTLS ~= 0 and 2 or 0) |
                (self.state & c.ALTS ~= 0 and 4 or 0)
  if (key.flags & c.FLAG_LOCK_C ~= 0 and self.state & c.CLKED ~= 0) or
     (key.flags & c.FLAG_LOCK_N ~= 0 and self.state & c.NLKED ~= 0) then
    shift = shift ~ 1
  end
  local action = key[shift]

  self.state = self.state & ~c.SHIFTAON

  if not action then
    self.last_action[keycode] = nil

  elseif action & c.SPCLKEY ~= 0 then
    if not self.last_action[keycode] then
      self.last_action[keycode] = action
    elseif self.last_action[keycode] ~= action then return end

    if locks[action] and self.state & locks[action].LKDOWN == 0 then
      self.state = self.state ~ locks[action].LKED | locks[action].LKDOWN
      system.set_kbd_locks(self.state & c.LOCK_MASK)
      return
    end

    if altgr_lock_shifts[action] then
      self.state = self.state | c.SHIFTAON
      action = altgr_lock_shifts[action]
    end

    if shifts[action] then
      self.state = self.state | shifts[action]
      return
    end

    if c.F_ACC <= action and action <= c.L_ACC then
      local accent = action - c.F_ACC
      if self.active_accent == accent then
        self.active_accent = nil
        local result = self.accentmap[accent]
        if result then
          result = result[' ']
        end
        if result then
          return utf8.char(result)
        end
      else
        self.active_accent = accent
      end
      return
    end

    self.active_accent = nil

    if c.F_SCR <= action and action <= c.L_SCR then
      system.set_active_vc(action - c.F_SCR + 1)
    elseif action == c.NEXT then
      system.set_active_vc(system.get_active_vc() + 1)
    elseif action == c.PREV then
      system.set_active_vc(system.get_active_vc() - 1)
    end

  else
    self.last_action[keycode] = nil

    if self.active_accent then
      action = self.accentmap[self.active_accent]
      if action then
        action = action[action]
      end
      self.active_accent = nil
    end

    if action then
      return utf8.char(action)
    end
  end
end

return Kbd
