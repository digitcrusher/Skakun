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

-- This is an emulation of Linux's kbd input handler.
local Kbd = {
  -- All of the 104 keys of a standard US layout Windows keyboard. The keycodes
  -- were taken from <linux/input-event-codes.h>; FreeBSD's codes are the same.
  keycodes = {
    [  1] = 'escape',
    [ 59] = 'f1',
    [ 60] = 'f2',
    [ 61] = 'f3',
    [ 62] = 'f4',
    [ 63] = 'f5',
    [ 64] = 'f6',
    [ 65] = 'f7',
    [ 66] = 'f8',
    [ 67] = 'f9',
    [ 68] = 'f10',
    [ 87] = 'f11',
    [ 88] = 'f12',
    [ 99] = 'print_screen',
    [ 70] = 'scroll_lock',
    [119] = 'pause',

    [ 41] = 'backtick',
    [  2] = '1',
    [  3] = '2',
    [  4] = '3',
    [  5] = '4',
    [  6] = '5',
    [  7] = '6',
    [  8] = '7',
    [  9] = '8',
    [ 10] = '9',
    [ 11] = '0',
    [ 12] = 'minus',
    [ 13] = 'equal',
    [ 14] = 'backspace',

    [ 15] = 'tab',
    [ 16] = 'q',
    [ 17] = 'w',
    [ 18] = 'e',
    [ 19] = 'r',
    [ 20] = 't',
    [ 21] = 'y',
    [ 22] = 'u',
    [ 23] = 'i',
    [ 24] = 'o',
    [ 25] = 'p',
    [ 26] = 'left_bracket',
    [ 27] = 'right_bracket',
    [ 43] = 'backslash',

    [ 58] = 'caps_lock',
    [ 30] = 'a',
    [ 31] = 's',
    [ 32] = 'd',
    [ 33] = 'f',
    [ 34] = 'g',
    [ 35] = 'h',
    [ 36] = 'j',
    [ 37] = 'k',
    [ 38] = 'l',
    [ 39] = 'semicolon',
    [ 40] = 'apostrophe',
    [ 28] = 'enter',

    [ 42] = 'left_shift',
    [ 44] = 'z',
    [ 45] = 'x',
    [ 46] = 'c',
    [ 47] = 'v',
    [ 48] = 'b',
    [ 49] = 'n',
    [ 50] = 'm',
    [ 51] = 'comma',
    [ 52] = 'dot',
    [ 53] = 'slash',
    [ 54] = 'right_shift',

    [ 29] = 'left_ctrl',
    [125] = 'left_super',
    [ 56] = 'left_alt',
    [ 57] = 'space',
    [100] = 'right_alt',
    [126] = 'right_super',
    [127] = 'menu',
    [ 97] = 'right_ctrl',

    [110] = 'insert',
    [111] = 'delete',
    [102] = 'home',
    [107] = 'end',
    [104] = 'page_up',
    [109] = 'page_down',

    [103] = 'up',
    [105] = 'left',
    [108] = 'down',
    [106] = 'right',

    [ 69] = 'num_lock',
    [ 98] = 'kp_divide',
    [ 55] = 'kp_multiply',
    [ 74] = 'kp_subtract',
    [ 78] = 'kp_add',
    [ 96] = 'kp_enter',
    [ 79] = 'kp_1',
    [ 80] = 'kp_2',
    [ 81] = 'kp_3',
    [ 75] = 'kp_4',
    [ 76] = 'kp_5',
    [ 77] = 'kp_6',
    [ 71] = 'kp_7',
    [ 72] = 'kp_8',
    [ 73] = 'kp_9',
    [ 82] = 'kp_0',
    [ 83] = 'kp_decimal',
  },
}

return Kbd
