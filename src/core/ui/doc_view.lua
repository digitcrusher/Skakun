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

local here = ...
local Navigator = require('core.doc.navigator')
local stderr    = require('core.stderr')
local tty       = require('core.tty')
local Widget    = require('core.ui.widget')

local DocView = setmetatable({
  should_soft_wrap = false,
  foreground = nil,
  background = nil,
  error_color = nil,
}, Widget)
DocView.__index = DocView

function DocView.new(doc)
  local self = setmetatable(Widget.new(), DocView)
  self.doc = doc
  self.line = 1
  self.col = 1
  return self
end

function DocView:draw()
  if self.should_soft_wrap then
    self:draw_soft_wrap()
  else
    self:draw_cut_off()
  end
end

local ctrl_pics = {
  ['\127'] = '␡',
  ['\r\n'] = '␍␊',
}
for i, ctrl_pic in ipairs({
  '␀', '␁', '␂', '␃', '␄', '␅', '␆', '␇', '␈', '␉', '␊', '␋', '␌', '␍', '␎', '␏',
  '␐', '␑', '␒', '␓', '␔', '␕', '␖', '␗', '␘', '␙', '␚', '␛', '␜', '␝', '␞', '␟',
}) do
  ctrl_pics[string.char(i - 1)] = ctrl_pic
end
for i = 0x80, 0x9f do
  ctrl_pics[utf8.char(i)] = '�'
end
ctrl_pics['\u{85}'] = '␤'

function DocView:draw_soft_wrap()
  tty.set_foreground(self.foreground)
  tty.set_background(self.background)

  self.doc.buffer:freeze()
  local nav = Navigator.of(self.doc.buffer)
  local loc = nav:locate_line_col(self.line, self.col)
  local iter = self.doc.buffer:iter(loc.byte)

  for y = self.top, self.bottom do
    local x = self.left
    tty.move_to(x, y)

    while true do
      local grapheme, is_error = self:next_grapheme(iter, loc, nav)
      if not grapheme then
        loc.line = loc.line + 1
        loc.col = 1
        break
      end

      local width = tty.width_of(grapheme)
      if x + width - 1 > self.right then
        iter:rewind(iter:last_advance())
        break
      end

      if is_error then
        tty.set_foreground(self.error_color)
      end
      tty.write(grapheme)
      if is_error then
        tty.set_foreground(self.foreground)
      end
      x = x + width
      loc.col = loc.col + width
    end

    tty.write((' '):rep(self.right - x + 1))
  end
end

function DocView:draw_cut_off()
  tty.set_foreground(self.foreground)
  tty.set_background(self.background)

  self.doc.buffer:freeze()
  local nav = Navigator.of(self.doc.buffer)

  for y = self.top, self.bottom do
    local x = self.left
    tty.move_to(x, y)

    local loc = nav:locate_line_col(self.line + y - self.top, self.col)
    local iter = self.doc.buffer:iter(loc.byte)

    if loc.col < self.col then
      local grapheme = self:next_grapheme(iter, loc, nav)
      if not grapheme then
        iter:rewind(iter:last_advance())
      else
        loc.col = loc.col + tty.width_of(grapheme)
        local width = loc.col - self.col
        if x + width - 1 > self.right then break end

        tty.write((' '):rep(width))
        x = x + width
      end
    end

    while true do
      local grapheme, is_error = self:next_grapheme(iter, loc, nav)
      if not grapheme then break end

      local width = tty.width_of(grapheme)
      if x + width - 1 > self.right then break end

      if is_error then
        tty.set_foreground(self.error_color)
      end
      tty.write(grapheme)
      if is_error then
        tty.set_foreground(self.foreground)
      end
      x = x + width
      loc.col = loc.col + width
    end

    tty.write((' '):rep(self.right - x + 1))
  end
end

function DocView:next_grapheme(iter, loc, nav)
  local ok, grapheme = pcall(iter.next_grapheme, iter)
  if not ok then
    return '�', true
  elseif not grapheme or grapheme == '\n' then
    return nil, false
  elseif grapheme == '\t' then
    return (' '):rep(nav.tab_width - (loc.col - 1) % nav.tab_width), false
  elseif ctrl_pics[grapheme] then
    return ctrl_pics[grapheme], true
  else
    return grapheme, false
  end
end

function DocView:handle_event(event)
  if event.type == 'press' or event.type == 'repeat' then
    if event.button == 'up' then
      self.line = math.max(self.line - 1, 1)
    elseif event.button == 'scroll_up' then
      self.line = math.max(self.line - 3, 1)
    elseif event.button == 'page_up' then
      self.line = math.max(self.line - self:height(), 1)
    elseif event.button == 'left' then
      self.col = math.max(self.col - 1, 1)
    elseif event.button == 'down' then
      self.line = self.line + 1
    elseif event.button == 'scroll_down' then
      self.line = self.line + 3
    elseif event.button == 'page_down' then
      self.line = self.line + self:height()
    elseif event.button == 'right' then
      self.col = self.col + 1
    elseif event.button == 'w' then
      self.should_soft_wrap = not self.should_soft_wrap
    end
  end
end

return DocView

-- Every grapheme, once added, must have a constant width over its entire lifetime. In particular, it can't depend on its position in the text. The only hard-coded exception to this rule are tabs.
