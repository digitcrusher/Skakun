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
  @cInclude("string.h");
  if(target.isBSD()) {
    @cInclude("dev/evdev/input-event-codes.h");
    @cInclude("sys/consio.h");
    @cInclude("sys/kbio.h");
  } else if(target.os.tag == .linux) {
    @cInclude("linux/input-event-codes.h");
    @cInclude("linux/kd.h");
    @cInclude("linux/keyboard.h");
    @cInclude("linux/tiocl.h");
    @cInclude("linux/vt.h");
  }
});
const tty = @import("../system.zig");

// Linux Reference:
// - man 2 ioctl_console (outdated)
// - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/keyboard.h
// - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/kd.h
// - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/vt.h
// - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/tiocl.h
// - man 5 keymaps
// - https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/tty/vt/keyboard.c
// - https://git.kernel.org/pub/scm/linux/kernel/git/legion/kbd.git/tree/src/libkeymap/kernel.c
//
// FreeBSD reference:
// - https://cgit.freebsd.org/src/tree/sys/sys/consio.h
// - https://cgit.freebsd.org/src/tree/sys/sys/kbio.h
// - man 5 keymap
//
// Here is a more or less reasonable explanation of the terminology surrounding
// "virtual consoles" and "virtual terminals": https://unix.stackexchange.com/a/228052

// The Linux manpage incorrectly says this should be a long, but does nicely
// inform us that we should rely on the kernel source code instead of it.
var original_kbmode: ?c_int = null;

fn enable_raw_kbd(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(original_kbmode != null) return 0;
  var kbmode: c_int = undefined;
  if(std.c.ioctl(tty.file.handle, c.KDGKBMODE, &kbmode) < 0) return 0;
  const freebsd_is_wack: c_int = if(target.isBSD()) c.K_CODE else undefined;
  if(std.c.ioctl(tty.file.handle, c.KDSKBMODE, if(target.isBSD()) &freebsd_is_wack else c.K_MEDIUMRAW) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
  original_kbmode = kbmode;
  vm.pushBoolean(true);
  return 1;
}

fn disable_raw_kbd(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  if(original_kbmode) |x| {
    if(std.c.ioctl(tty.file.handle, c.KDSKBMODE, x) == 0) {
      original_kbmode = null;
    }
  }
  return 0;
}

fn get_keymap(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});

  vm.createTable(c.MAX_NR_KEYMAPS, 0);
  for(0 .. c.MAX_NR_KEYMAPS) |modifiers| {
    var intercom: c.kbentry = .{
      .kb_table = @intCast(modifiers),
      .kb_index = 0, // This has to be zero, otherwise Linux will return K_HOLE instead of K_NOSUCHMAP.
      .kb_value = undefined,
    };
    if(std.c.ioctl(tty.file.handle, c.KDGKBENT, &intercom) < 0) vm.raiseErrorStr("%s at table %d, index %d", .{c.strerror(std.c._errno().*), intercom.kb_table, intercom.kb_index});
    if(intercom.kb_value == c.K_NOSUCHMAP) continue;

    vm.createTable(c.NR_KEYS, 0);
    for(0 .. c.NR_KEYS) |keycode| {
      intercom.kb_index = @intCast(keycode);
      if(std.c.ioctl(tty.file.handle, c.KDGKBENT, &intercom) < 0) vm.raiseErrorStr("%s at table %d, index %d", .{c.strerror(std.c._errno().*), intercom.kb_table, intercom.kb_index});
      if(intercom.kb_value == c.K_HOLE) continue;
      vm.pushInteger(intercom.kb_value);
      vm.setIndex(-2, intercom.kb_index);
    }
    vm.setIndex(-2, intercom.kb_table);
  }
  return 1;
}

// fn get_accentmap(vm: *lua.Lua) i32 {
//   if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});

//   lua.lua_createtable(vm, );
//   std.c.ioctl(tty.file.handle, c.)
// }

fn set_kbd_leds(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  var state: c_ulong = 0;
  if(vm.toBoolean(1)) state |= c.LED_CAP;
  if(vm.toBoolean(2)) state |= c.LED_NUM;
  if(vm.toBoolean(3)) state |= c.LED_SCR;
  // KDSKBLED has more semantic meaning than KDSETLED on Linux.
  if(std.c.ioctl(tty.file.handle, if(target.isBSD()) c.KDSETLED else c.KDSKBLED, state) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
  return 0;
}

fn get_kbd_leds(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  var state: if(target.isBSD()) c_int else c_char = undefined;
  // KDGKBLED has more semantic meaning than KDGETLED on Linux.
  if(std.c.ioctl(tty.file.handle, if(target.isBSD()) c.KDGETLED else c.KDGKBLED, &state) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
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

// When switching to the next or previous VC, both Linux and FreeBSD don't just
// choose active_vc ± 1, but rather select the nearest "allocated/opened" VC.
// Unfortunately, we ourselves cannot query whether a given VC fits the label.
// Linux does have VT_GETSTATE but it only works for the first 16 VCs, which is
// kind of rubbish. Anyways, VCs are *usually* allocated sequentially, so who
// cares?
fn get_active_vc(vm: *lua.Lua) i32 {
  if(!tty.is_open) vm.raiseErrorStr("tty is closed", .{});
  var result: c_int = undefined;
  if(target.isBSD()) {
    // VT_GETINDEX returns the console of the file descriptor and not the active console.
    if(std.c.ioctl(tty.file.handle, c.VT_GETACTIVE, &result) < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
  } else {
    result = std.c.ioctl(tty.file.handle, std.os.linux.T.IOCLINUX, c.TIOCL_GETFGCONSOLE);
    if(result < 0) vm.raiseErrorStr("%s", .{c.strerror(std.c._errno().*)});
  }
  vm.pushInteger(result);
  return 1;
}

const funcs = [_]lua.FnReg{
  .{ .name = "enable_raw_kbd", .func = lua.wrap(enable_raw_kbd) },
  .{ .name = "disable_raw_kbd", .func = lua.wrap(disable_raw_kbd) },
  .{ .name = "get_keymap", .func = lua.wrap(get_keymap) },
  .{ .name = "set_kbd_leds", .func = lua.wrap(set_kbd_leds) },
  .{ .name = "get_kbd_leds", .func = lua.wrap(get_kbd_leds) },
  .{ .name = "set_active_vc", .func = lua.wrap(set_active_vc) },
  .{ .name = "get_active_vc", .func = lua.wrap(get_active_vc) },
};

pub fn luaopen(vm: *lua.Lua) i32 {
  vm.newLib(&funcs);

  // All of the 104 keys of a standard US layout Windows keyboard
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
    .{c.KEY_SYSRQ, "print_screen"},
    .{c.KEY_SCROLLLOCK, "scroll_lock"},
    .{c.KEY_PAUSE, "pause"},

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
    .{c.KEY_LEFTMETA, "left_super"},
    .{c.KEY_LEFTALT, "left_alt"},
    .{c.KEY_SPACE, "space"},
    .{c.KEY_RIGHTALT, "right_alt"},
    .{c.KEY_RIGHTMETA, "right_super"},
    .{c.KEY_COMPOSE, "menu"},
    .{c.KEY_RIGHTCTRL, "right_ctrl"},

    .{c.KEY_INSERT, "insert"},
    .{c.KEY_DELETE, "delete"},
    .{c.KEY_HOME, "home"},
    .{c.KEY_END, "end"},
    .{c.KEY_PAGEUP, "page_up"},
    .{c.KEY_PAGEDOWN, "page_down"},

    .{c.KEY_UP, "up"},
    .{c.KEY_LEFT, "left"},
    .{c.KEY_DOWN, "down"},
    .{c.KEY_RIGHT, "right"},

    .{c.KEY_NUMLOCK, "num_lock"},
    .{c.KEY_KPSLASH, "kp_divide"},
    .{c.KEY_KPASTERISK, "kp_multiply"},
    .{c.KEY_KPMINUS, "kp_subtract"},
    .{c.KEY_KPPLUS, "kp_add"},
    .{c.KEY_KPENTER, "kp_enter"},
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
