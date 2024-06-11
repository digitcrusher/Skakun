// Skakun - A robust and hackable hex and text editor
// Copyright (C) 2024 Karol "digitcrusher" Łacina
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const target = @import("builtin").target;
const lua = @import("ziglua");
const c = @cImport({
  @cInclude("errno.h");
  @cInclude("dev/evdev/input-event-codes.h");
  @cInclude("string.h");
  @cInclude("sys/consio.h");
  @cInclude("sys/kbio.h");
});
const tty = @import("../system.zig");

// Ioctl reference:
// - https://cgit.freebsd.org/src/tree/sys/sys/kbio.h
// - https://cgit.freebsd.org/src/tree/sys/sys/consio.h
//
// Ioctl parameter type reference: https://cgit.freebsd.org/src/tree/sys/dev/vt/vt_core.c
//
// Here is a more or less reasonable explanation of the terminology surrounding
// "virtual consoles" and "virtual terminals": https://unix.stackexchange.com/a/228052

var original_kbmode: ?c_int = null;

fn enable_raw_kbd(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(original_kbmode != null) return 0;
  var kbmode: c_int = undefined;
  if(std.c.ioctl(tty.file.handle, c.KDGKBMODE, &kbmode) < 0) return 0;
  const freebsd_is_wack: c_int = c.K_CODE;
  if(std.c.ioctl(tty.file.handle, c.KDSKBMODE, &freebsd_is_wack) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
  original_kbmode = kbmode;
  vm.pushBoolean(true);
  return 1;
}

fn disable_raw_kbd(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(original_kbmode) |x| {
    if(std.c.ioctl(tty.file.handle, c.KDSKBMODE, &x) == 0) {
      original_kbmode = null;
    }
  }
  return 0;
}

fn get_keymap(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});

  var keymap: c.keymap = undefined;
  if(std.c.ioctl(tty.file.handle, c.GIO_KEYMAP, &keymap) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});

  vm.createTable(c.NUM_STATES, 0);
  for(0 .. c.NUM_STATES) |modifiers| {
    vm.createTable(keymap.n_keys, 0);
    for(0 .. keymap.n_keys) |keycode| {
      if(keymap.key[keycode].map[modifiers] == c.NOP) continue;
      vm.pushInteger(keymap.key[keycode].map[modifiers]);
      vm.setIndex(-2, keycode);
    }
    vm.setIndex(-2, modifiers);
  }
  return 1;
}

fn get_accentmap(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  return 0;
}

fn set_kbd_leds(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  var state: c_ulong = 0;
  if(vm.toBoolean(1)) state |= c.LED_CAP;
  if(vm.toBoolean(2)) state |= c.LED_NUM;
  if(vm.toBoolean(3)) state |= c.LED_SCR;
  if(std.c.ioctl(tty.file.handle, c.KDSETLED, state) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
  return 0;
}

fn get_kbd_leds(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  var state: c_int = undefined;
  if(std.c.ioctl(tty.file.handle, c.KDGETLED, &state) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
  vm.pushBoolean(state & c.LED_CAP != 0);
  vm.pushBoolean(state & c.LED_NUM != 0);
  vm.pushBoolean(state & c.LED_SCR != 0);
  return 3;
}

fn set_active_vc(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(std.c.ioctl(tty.file.handle, c.VT_ACTIVATE, vm.checkInteger(1)) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
  return 0;
}

// When switching to the next or previous VC, FreeBSD doesn't just choose
// active_vc ± 1, but rather selects the nearest "opened" VC. Unfortunately, we
// ourselves cannot query whether a given VC fits the label. Anyways, VCs are
// *usually* allocated sequentially, so who cares?
fn get_active_vc(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  var result: c_int = undefined;
  // VT_GETINDEX returns the console of the file descriptor and not the active console.
  if(std.c.ioctl(tty.file.handle, c.VT_GETACTIVE, &result) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
  vm.pushInteger(result);
  return 1;
}

const funcs = [_]lua.FnReg{
  .{ .name = "enable_raw_kbd", .func = lua.wrap(enable_raw_kbd) },
  .{ .name = "disable_raw_kbd", .func = lua.wrap(disable_raw_kbd) },
  .{ .name = "get_keymap", .func = lua.wrap(get_keymap) },
  .{ .name = "get_accentmap", .func = lua.wrap(get_accentmap) },
  .{ .name = "set_kbd_leds", .func = lua.wrap(set_kbd_leds) },
  .{ .name = "get_kbd_leds", .func = lua.wrap(get_kbd_leds) },
  .{ .name = "set_active_vc", .func = lua.wrap(set_active_vc) },
  .{ .name = "get_active_vc", .func = lua.wrap(get_active_vc) },
};

pub fn luaopen(vm: *lua.Lua) i32 {
  vm.newLib(&funcs);

  // All of the 104 keys of a standard US layout Windows keyboard. The FreeBSD
  // peculiarities were picked out with the help of misc/kbdscan. Unfortunately,
  // FreeBSD didn't care enough to put their keycodes in a header file.
  const entries = [_]struct {comptime_int, []const u8}{
    .{c.KEY_ESC, "escape"},
    .{c.KEY_F1, "f1"},
    .{c.KEY_F2, "f2"},
    .{c.KEY_F3, "f3"},
    .{c.KEY_F4, "f4"},
    .{c.KEY_F5, "f5"},
    .{c.KEY_F6, "f6"},
    .{c.KEY_F7, "f7"},
    .{c.KEY_F8, "f8"},
    .{c.KEY_F9, "f9"},
    .{c.KEY_F10, "f10"},
    .{c.KEY_F11, "f11"},
    .{c.KEY_F12, "f12"},
    .{92, "print_screen"},
    .{c.KEY_SCROLLLOCK, "scroll_lock"},
    .{104, "pause"},

    .{c.KEY_GRAVE, "backtick"},
    .{c.KEY_1, "1"},
    .{c.KEY_2, "2"},
    .{c.KEY_3, "3"},
    .{c.KEY_4, "4"},
    .{c.KEY_5, "5"},
    .{c.KEY_6, "6"},
    .{c.KEY_7, "7"},
    .{c.KEY_8, "8"},
    .{c.KEY_9, "9"},
    .{c.KEY_0, "0"},
    .{c.KEY_MINUS, "minus"},
    .{c.KEY_EQUAL, "equal"},
    .{c.KEY_BACKSPACE, "backspace"},

    .{c.KEY_TAB, "tab"},
    .{c.KEY_Q, "q"},
    .{c.KEY_W, "w"},
    .{c.KEY_E, "e"},
    .{c.KEY_R, "r"},
    .{c.KEY_T, "t"},
    .{c.KEY_Y, "y"},
    .{c.KEY_U, "u"},
    .{c.KEY_I, "i"},
    .{c.KEY_O, "o"},
    .{c.KEY_P, "p"},
    .{c.KEY_LEFTBRACE, "left_bracket"},
    .{c.KEY_RIGHTBRACE, "right_bracket"},
    .{c.KEY_BACKSLASH, "backslash"},

    .{c.KEY_CAPSLOCK, "caps_lock"},
    .{c.KEY_A, "a"},
    .{c.KEY_S, "s"},
    .{c.KEY_D, "d"},
    .{c.KEY_F, "f"},
    .{c.KEY_G, "g"},
    .{c.KEY_H, "h"},
    .{c.KEY_J, "j"},
    .{c.KEY_K, "k"},
    .{c.KEY_L, "l"},
    .{c.KEY_SEMICOLON, "semicolon"},
    .{c.KEY_APOSTROPHE, "apostrophe"},
    .{c.KEY_ENTER, "enter"},

    .{c.KEY_LEFTSHIFT, "left_shift"},
    .{c.KEY_Z, "z"},
    .{c.KEY_X, "x"},
    .{c.KEY_C, "c"},
    .{c.KEY_V, "v"},
    .{c.KEY_B, "b"},
    .{c.KEY_N, "n"},
    .{c.KEY_M, "m"},
    .{c.KEY_COMMA, "comma"},
    .{c.KEY_DOT, "dot"},
    .{c.KEY_SLASH, "slash"},
    .{c.KEY_RIGHTSHIFT, "right_shift"},

    .{c.KEY_LEFTCTRL, "left_ctrl"},
    .{105, "left_super"},
    .{c.KEY_LEFTALT, "left_alt"},
    .{c.KEY_SPACE, "space"},
    .{93, "right_alt"},
    .{106, "right_super"},
    .{107, "menu"},
    .{90, "right_ctrl"},

    .{102, "insert"},
    .{103, "delete"},
    .{94, "home"},
    .{99, "end"},
    .{96, "page_up"},
    .{101, "page_down"},

    .{95, "up"},
    .{97, "left"},
    .{100, "down"},
    .{98, "right"},

    .{c.KEY_NUMLOCK, "num_lock"},
    .{91, "kp_divide"},
    .{c.KEY_KPASTERISK, "kp_multiply"},
    .{c.KEY_KPMINUS, "kp_subtract"},
    .{c.KEY_KPPLUS, "kp_add"},
    .{89, "kp_enter"},
    .{c.KEY_KP1, "kp_1"},
    .{c.KEY_KP2, "kp_2"},
    .{c.KEY_KP3, "kp_3"},
    .{c.KEY_KP4, "kp_4"},
    .{c.KEY_KP5, "kp_5"},
    .{c.KEY_KP6, "kp_6"},
    .{c.KEY_KP7, "kp_7"},
    .{c.KEY_KP8, "kp_8"},
    .{c.KEY_KP9, "kp_9"},
    .{c.KEY_KP0, "kp_0"},
    .{c.KEY_KPDOT, "kp_decimal"},
  };
  vm.createTable(entries.len, 0);
  inline for(entries) |entry| {
    _ = vm.pushString(entry[1]);
    vm.setIndex(-2, entry[0]);
  }
  vm.setField(-2, "keycodes");

  return 1;
}
