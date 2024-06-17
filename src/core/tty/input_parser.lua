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

local Parser = {
  keymap = {
    [  0] = { button = 'space', ctrl = true },
    [  1] = { button = 'a', ctrl = true },
    [  2] = { button = 'b', ctrl = true },
    [  3] = { button = 'c', ctrl = true },
    [  4] = { button = 'd', ctrl = true },
    [  5] = { button = 'e', ctrl = true },
    [  6] = { button = 'f', ctrl = true },
    [  7] = { button = 'g', ctrl = true },
    [  8] = { button = 'backspace', ctrl = true },
    [  9] = { button = 'tab', text = '\t' },
    [ 10] = { button = 'j', ctrl = true },
    [ 11] = { button = 'k', ctrl = true },
    [ 12] = { button = 'l', ctrl = true },
    [ 13] = { button = 'enter', text = '\n' },
    [ 14] = { button = 'n', ctrl = true },
    [ 15] = { button = 'o', ctrl = true },
    [ 16] = { button = 'p', ctrl = true },
    [ 17] = { button = 'q', ctrl = true },
    [ 18] = { button = 'r', ctrl = true },
    [ 19] = { button = 's', ctrl = true },
    [ 20] = { button = 't', ctrl = true },
    [ 21] = { button = 'u', ctrl = true },
    [ 22] = { button = 'v', ctrl = true },
    [ 23] = { button = 'w', ctrl = true },
    [ 24] = { button = 'x', ctrl = true },
    [ 25] = { button = 'y', ctrl = true },
    [ 26] = { button = 'z', ctrl = true },
    [ 27] = { button = 'escape' },
    [ 28] = { button = 'backslash', ctrl = true },
    [ 29] = { button = 'right_bracket', ctrl = true },
    [ 30] = { button = 'backtick', ctrl = true, shift = true },
    [ 31] = { button = 'slash', ctrl = true },
    [ 32] = { button = 'space', text = ' ' },
    [127] = { button = 'backspace' },
    -- These depend on the system keyboard layout, unlike the ones above:
    [ 33] = { button = '1', shift = true, text = '!' },
    [ 34] = { button = 'apostrophe', shift = true, text = '"' },
    [ 35] = { button = '3', shift = true, text = '#' },
    [ 36] = { button = '4', shift = true, text = '$' },
    [ 37] = { button = '5', shift = true, text = '%' },
    [ 38] = { button = '7', shift = true, text = '&' },
    [ 39] = { button = 'apostrophe', text = "'" },
    [ 40] = { button = '9', shift = true, text = '(' },
    [ 41] = { button = '0', shift = true, text = ')' },
    [ 42] = { button = '8', shift = true, text = '*' },
    [ 43] = { button = 'equal', shift = true, text = '+' },
    [ 44] = { button = 'comma', text = ',' },
    [ 45] = { button = 'minus', text = '-' },
    [ 46] = { button = 'dot', text = '.' },
    [ 47] = { button = 'slash', text = '/' },
    [ 48] = { button = '0', text = '0' },
    [ 49] = { button = '1', text = '1' },
    [ 50] = { button = '2', text = '2' },
    [ 51] = { button = '3', text = '3' },
    [ 52] = { button = '4', text = '4' },
    [ 53] = { button = '5', text = '5' },
    [ 54] = { button = '6', text = '6' },
    [ 55] = { button = '7', text = '7' },
    [ 56] = { button = '8', text = '8' },
    [ 57] = { button = '9', text = '9' },
    [ 58] = { button = 'semicolon', shift = true, text = ':' },
    [ 59] = { button = 'semicolon', text = ';' },
    [ 60] = { button = 'comma', shift = true, text = '<' },
    [ 61] = { button = 'equal', text = '=' },
    [ 62] = { button = 'dot', shift = true, text = '>' },
    [ 63] = { button = 'slash', shift = true, text = '?' },
    [ 64] = { button = '2', shift = true, text = '@' },
    [ 65] = { button = 'a', shift = true, text = 'A' },
    [ 66] = { button = 'b', shift = true, text = 'B' },
    [ 67] = { button = 'c', shift = true, text = 'C' },
    [ 68] = { button = 'd', shift = true, text = 'D' },
    [ 69] = { button = 'e', shift = true, text = 'E' },
    [ 70] = { button = 'f', shift = true, text = 'F' },
    [ 71] = { button = 'g', shift = true, text = 'G' },
    [ 72] = { button = 'h', shift = true, text = 'H' },
    [ 73] = { button = 'i', shift = true, text = 'I' },
    [ 74] = { button = 'j', shift = true, text = 'J' },
    [ 75] = { button = 'k', shift = true, text = 'K' },
    [ 76] = { button = 'l', shift = true, text = 'L' },
    [ 77] = { button = 'm', shift = true, text = 'M' },
    [ 78] = { button = 'n', shift = true, text = 'N' },
    [ 79] = { button = 'o', shift = true, text = 'O' },
    [ 80] = { button = 'p', shift = true, text = 'P' },
    [ 81] = { button = 'q', shift = true, text = 'Q' },
    [ 82] = { button = 'r', shift = true, text = 'R' },
    [ 83] = { button = 's', shift = true, text = 'S' },
    [ 84] = { button = 't', shift = true, text = 'T' },
    [ 85] = { button = 'u', shift = true, text = 'U' },
    [ 86] = { button = 'v', shift = true, text = 'V' },
    [ 87] = { button = 'w', shift = true, text = 'W' },
    [ 88] = { button = 'x', shift = true, text = 'X' },
    [ 89] = { button = 'y', shift = true, text = 'Y' },
    [ 90] = { button = 'z', shift = true, text = 'Z' },
    [ 91] = { button = 'left_bracket', text = '[' },
    [ 92] = { button = 'backslash', text = '\\' },
    [ 93] = { button = 'right_bracket', text = ']' },
    [ 94] = { button = '6', shift = true, text = '^' },
    [ 95] = { button = 'minus', shift = true, text = '_' },
    [ 96] = { button = 'backtick', text = '`' },
    [ 97] = { button = 'a', text = 'a' },
    [ 98] = { button = 'b', text = 'b' },
    [ 99] = { button = 'c', text = 'c' },
    [100] = { button = 'd', text = 'd' },
    [101] = { button = 'e', text = 'e' },
    [102] = { button = 'f', text = 'f' },
    [103] = { button = 'g', text = 'g' },
    [104] = { button = 'h', text = 'h' },
    [105] = { button = 'i', text = 'i' },
    [106] = { button = 'j', text = 'j' },
    [107] = { button = 'k', text = 'k' },
    [108] = { button = 'l', text = 'l' },
    [109] = { button = 'm', text = 'm' },
    [110] = { button = 'n', text = 'n' },
    [111] = { button = 'o', text = 'o' },
    [112] = { button = 'p', text = 'p' },
    [113] = { button = 'q', text = 'q' },
    [114] = { button = 'r', text = 'r' },
    [115] = { button = 's', text = 's' },
    [116] = { button = 't', text = 't' },
    [117] = { button = 'u', text = 'u' },
    [118] = { button = 'v', text = 'v' },
    [119] = { button = 'w', text = 'w' },
    [120] = { button = 'x', text = 'x' },
    [121] = { button = 'y', text = 'y' },
    [122] = { button = 'z', text = 'z' },
    [123] = { button = 'left_bracket', shift = true, text = '{' },
    [124] = { button = 'backslash', shift = true, text = '|' },
    [125] = { button = 'right_bracket', shift = true, text = '}' },
    [126] = { button = 'backtick', shift = true, text = '~' },
  },
  buf = '',
}

function Parser.new()
  return setmetatable({
    keymap = setmetatable({}, { __index = Parser.keymap }),
    is_pressed = {},
  }, { __index = Parser })
end

function Parser:feed(string)
  self.buf = self.buf .. string

  local result = {}

  local i = 1
  while i <= #self.buf do
    local events
    for _, func in ipairs({
      self.read_mouse,
      self.read_functional_key,
      self.read_functional_key_with_mods,
      self.read_shift_tab,
      self.read_key,
      self.read_codepoint,
    }) do
      events, i = func(self, self.buf, i)
      if events then break end
    end
    if not events then break end

    for _, event in ipairs(events) do
      if event.type == 'press' then
        if self.is_pressed[event.button] then
          event.type = 'repeat'
        else
          self.is_pressed[event.button] = true
        end
      elseif event.type == 'release' then
        self.is_pressed[event.button] = false
      end

      result[#result + 1] = event
    end
  end
  self.buf = self.buf:sub(i)

  return result
end

function Parser:read_mouse(buf, offset)
  -- Reference: https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h2-Mouse-Tracking
  local bits, x, y, event = buf:match('^\27%[<(%d+);(%d+);(%d+)([Mm])', offset)
  if not event then
    return nil, offset
  end
  offset = offset + #bits + #x + #y + #event + 5

  x = tonumber(x)
  y = tonumber(y)
  bits = tonumber(bits)
  if bits & 32 ~= 0 then
    return {{ type = 'move', x = x, y = y }}, offset
  end

  local shift = bits & 4 ~= 0
  local alt = bits & 8 ~= 0
  local ctrl = bits & 16 ~= 0
  local button = ({
    [0] = 'mouse_left',
    [1] = 'mouse_middle',
    [2] = 'mouse_right',
    [64] = 'scroll_up',
    [65] = 'scroll_down',
    [66] = 'scroll_left',
    [67] = 'scroll_right',
    [128] = 'mouse_prev',
    [129] = 'mouse_next',
  })[bits & ~28]
  if not button then
    return {}, offset
  end

  if button == 'scroll_up' or button == 'scroll_down' then
    return {
      { type = 'press',   button = button, alt = alt, ctrl = ctrl, shift = shift, x = x, y = y },
      { type = 'release', button = button, alt = alt, ctrl = ctrl, shift = shift, x = x, y = y },
    }, offset
  else
    return {{ type = event == 'M' and 'press' or 'release', button = button, alt = alt, ctrl = ctrl, shift = shift, x = x, y = y }}, offset
  end
end

function Parser:read_functional_key(buf, offset)
  local seq = buf:match('^\27[O%[]%d*.', offset)
  local button = ({
    ['\27OP'] = 'f1',
    ['\27OQ'] = 'f2',
    ['\27OR'] = 'f3',
    ['\27OS'] = 'f4',
    ['\27[15~'] = 'f5',
    ['\27[17~'] = 'f6',
    ['\27[18~'] = 'f7',
    ['\27[19~'] = 'f8',
    ['\27[20~'] = 'f9',
    ['\27[21~'] = 'f10',
    ['\27[23~'] = 'f11',
    ['\27[24~'] = 'f12',
    ['\27[29~'] = 'menu',
    ['\27[2~'] = 'insert',
    ['\27[3~'] = 'delete',
    ['\27[H'] = 'home',
    ['\27[F'] = 'end',
    ['\27[5~'] = 'page_up',
    ['\27[6~'] = 'page_down',
    ['\27[A'] = 'up',
    ['\27[D'] = 'left',
    ['\27[B'] = 'down',
    ['\27[C'] = 'right',
    ['\27Oo'] = 'kp_divide',
    ['\27Oj'] = 'kp_multiply',
    ['\27Om'] = 'kp_subtract',
    ['\27Ok'] = 'kp_add',
    ['\27OM'] = 'kp_enter',
    ['\27[E'] = 'kp_5',
  })[seq]

  if button then
    return {
      { type = 'press',   button = button, alt = false, ctrl = false, shift = false },
      { type = 'release', button = button, alt = false, ctrl = false, shift = false },
    }, offset + #seq
  else
    return nil, offset
  end
end

function Parser:read_functional_key_with_mods(buf, offset)
  local a, b, c = buf:match('^\27(%[%d+;)(%d+)(.)', offset)
  if not c then
    a, b, c = buf:match('^\27(O)(%d+)(.)', offset)
  end
  if not c then
    return nil, offset
  end

  local mods = tonumber(b) - 1
  local shift = mods & 1 ~= 0
  local alt = mods & 2 ~= 0
  local ctrl = mods & 4 ~= 0
  local button = ({
    ['[1; P'] = 'f1',
    ['[1; Q'] = 'f2',
    ['[1; R'] = 'f3',
    ['[1; S'] = 'f4',
    ['[15; ~'] = 'f5',
    ['[17; ~'] = 'f6',
    ['[18; ~'] = 'f7',
    ['[19; ~'] = 'f8',
    ['[20; ~'] = 'f9',
    ['[21; ~'] = 'f10',
    ['[23; ~'] = 'f11',
    ['[24; ~'] = 'f12',
    ['[29; ~'] = 'menu',
    ['[2; ~'] = 'insert',
    ['[3; ~'] = 'delete',
    ['[1; H'] = 'home',
    ['[1; F'] = 'end',
    ['[5; ~'] = 'page_up',
    ['[6; ~'] = 'page_down',
    ['[1; A'] = 'up',
    ['[1; D'] = 'left',
    ['[1; B'] = 'down',
    ['[1; C'] = 'right',
    ['O o'] = 'kp_divide',
    ['O j'] = 'kp_multiply',
    ['O m'] = 'kp_subtract',
    ['O k'] = 'kp_add',
    ['O M'] = 'kp_enter',
    ['[1; E'] = 'kp_5',
    -- On Konsole:
    ['O P'] = 'f1',
    ['O Q'] = 'f2',
    ['O R'] = 'f3',
    ['O S'] = 'f4',
  })[a .. ' ' .. c]

  if button then
    return {
      { type = 'press',   button = button, alt = alt, ctrl = ctrl, shift = shift },
      { type = 'release', button = button, alt = alt, ctrl = ctrl, shift = shift },
    }, offset + 1 + #a + #b + #c
  else
    return nil, offset
  end
end

function Parser:read_shift_tab(buf, offset)
  if buf:match('^\27%[Z', offset) then
    return {
      { type = 'press',   button = 'tab', alt = false, ctrl = false, shift = true },
      { type = 'release', button = 'tab', alt = false, ctrl = false, shift = true },
    }, offset + 3
  else
    return nil, offset
  end
end

function Parser:read_key(buf, offset)
  local alt = buf:byte(offset) == 27 and #buf > 1
  local has_codepoint, new_offset = pcall(utf8.offset, buf, 2, offset + (alt and 1 or 0))
  if not has_codepoint then
    return nil, offset
  end
  local key = self.keymap[utf8.codepoint(buf, offset + (alt and 1 or 0), offset + (alt and 1 or 0), true)]
  if key then
    return {
      { type = 'press',   button = key.button, alt = alt, ctrl = key.ctrl or false, shift = key.shift or false, text = key.text },
      { type = 'release', button = key.button, alt = alt, ctrl = key.ctrl or false, shift = key.shift or false, text = key.text },
    }, new_offset
  else
    return nil, offset
  end
end

function Parser:read_codepoint(buf, offset)
  local has_codepoint, new_offset = pcall(utf8.offset, buf, 2, offset)
  if has_codepoint then
    return {{ type = 'paste', text = buf:sub(offset, new_offset - 1) }}, new_offset
  else
    return nil, offset
  end
end

return Parser
