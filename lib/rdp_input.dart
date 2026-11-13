import 'dart:math' as math;
import 'dart:ui';

const int vkExtKey = 0x100;

/// US-layout shifted character for a key label, shown while Shift is armed
/// (step 24). Letter keys already display uppercase, so they map to
/// themselves; named keys (Esc, Tab, ...) are not in the map either.
const Map<String, String> shiftKeyLabels = {
  '`': '~',
  '1': '!',
  '2': '@',
  '3': '#',
  '4': r'$',
  '5': '%',
  '6': '^',
  '7': '&',
  '8': '*',
  '9': '(',
  '0': ')',
  '-': '_',
  '=': '+',
  '[': '{',
  ']': '}',
  '\\': '|',
  ';': ':',
  "'": '"',
  ',': '<',
  '.': '>',
  '/': '?',
};

/// The label a key shows while Shift is armed; unchanged for keys with no
/// shifted character (letters, named keys).
String shiftedLabel(String label) => shiftKeyLabels[label] ?? label;

/// Windows VK values from FreeRDP KeyboardMapper.java, not Android keycodes.
int? rdpVirtualKey(String key) {
  if (key.length == 1) {
    final raw = key.codeUnitAt(0);
    final code = raw >= 0x61 && raw <= 0x7a ? raw - 0x20 : raw;
    if ((code >= 0x41 && code <= 0x5a) || (code >= 0x30 && code <= 0x39)) {
      return code;
    }
  }
  final function = RegExp(r'^F([1-9]|1[0-2])$').firstMatch(key);
  if (function != null) return 0x6f + int.parse(function.group(1)!);
  return const <String, int>{
    'Esc': 0x1b,
    'Backspace': 0x08,
    'Tab': 0x09,
    'Enter': 0x0d,
    'Space': 0x20,
    'Shift': 0xa0,
    'Caps': 0x14,
    'Ctrl': 0xa2,
    'Alt': 0xa4,
    'Win': 0x15b,
    'Delete': 0x12e,
    'Left': 0x125,
    'Up': 0x126,
    'Right': 0x127,
    'Down': 0x128,
    // Step 24, item 6: navigation column (PgUp/PgDn/Home/End).
    'PgUp': 0x21,
    'PgDn': 0x22,
    'End': 0x23,
    'Home': 0x24,
    '-': 0xbd,
    '=': 0xbb,
    '[': 0xdb,
    ']': 0xdd,
    '\\': 0xdc,
    ';': 0xba,
    "'": 0xde,
    '`': 0xc0,
    ',': 0xbc,
    '.': 0xbe,
    '/': 0xbf,
  }[key];
}

Offset? mapTouchToFramebuffer(
    {required Offset touch, required Size viewSize, required Size bitmapSize}) {
  if (viewSize.isEmpty ||
      bitmapSize.isEmpty ||
      !viewSize.width.isFinite ||
      !viewSize.height.isFinite ||
      !bitmapSize.width.isFinite ||
      !bitmapSize.height.isFinite ||
      !touch.dx.isFinite ||
      !touch.dy.isFinite) {
    return null;
  }
  final scale = math.min(
      viewSize.width / bitmapSize.width, viewSize.height / bitmapSize.height);
  final offset = Offset((viewSize.width - bitmapSize.width * scale) / 2,
      (viewSize.height - bitmapSize.height * scale) / 2);
  final point = (touch - offset) / scale;
  return (Offset.zero & bitmapSize).contains(point) ? point : null;
}
