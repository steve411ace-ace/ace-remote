import 'dart:ui';
import 'package:ace_remote/rdp_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VK codes match FreeRDP KeyboardMapper including extended keys', () {
    const samples = {
      'A': 0x41,
      'Z': 0x5a,
      'q': 0x51,
      '0': 0x30,
      '9': 0x39,
      'Enter': 0x0d,
      'Esc': 0x1b,
      'Backspace': 0x08,
      'Tab': 0x09,
      'Space': 0x20,
      'F1': 0x70,
      'F12': 0x7b,
      'Left': 0x125,
      'Up': 0x126,
      'Right': 0x127,
      'Down': 0x128,
      'Delete': 0x12e,
      'Win': 0x15b,
      // Step 25, item 2: navigation keys carry the FreeRDP extended flag
      // (0x100) — the plain VKs are not in FreeRDP's normal table, so the
      // JNI lookup returned scancode 0 and the server ignored the key.
      'PgUp': 0x121,
      'PgDn': 0x122,
      'End': 0x123,
      'Home': 0x124,
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
      'Shift': 0xa0,
      'Caps': 0x14,
      'Ctrl': 0xa2,
      'Alt': 0xa4,
    };
    for (final entry in samples.entries) {
      expect(rdpVirtualKey(entry.key), entry.value, reason: entry.key);
    }
    for (var i = 0; i < 26; i++) {
      expect(rdpVirtualKey(String.fromCharCode(0x61 + i)), 0x41 + i);
    }
    expect(rdpVirtualKey('á'), isNull);
    expect(rdpVirtualKey('ß'), isNull);
    expect(rdpVirtualKey('F13'), isNull);
    expect(rdpVirtualKey('unknown'), isNull);
  });
  test('touch reverses centered aspect fit and ignores black bars', () {
    Offset? map(Offset point, Size view, Size bitmap) =>
        mapTouchToFramebuffer(touch: point, viewSize: view, bitmapSize: bitmap);
    expect(
        map(const Offset(250, 200), const Size(500, 400),
            const Size(1000, 400)),
        const Offset(500, 200));
    expect(
        map(const Offset(100, 99), const Size(500, 400), const Size(1000, 400)),
        isNull);
    expect(
        map(const Offset(100, 300), const Size(500, 400),
            const Size(1000, 400)),
        isNull);
    expect(
        map(const Offset(50, 100), const Size(400, 400), const Size(100, 200)),
        isNull);
    expect(
        map(const Offset(200, 100), const Size(400, 400), const Size(100, 200)),
        const Offset(50, 50));
    expect(
        map(const Offset(100, 0), const Size(400, 400), const Size(100, 200)),
        Offset.zero);
    expect(map(Offset.zero, Size.zero, const Size(100, 200)), isNull);
  });

  test('shifted labels follow the US-layout Shift characters', () {
    const samples = {
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
    for (final entry in samples.entries) {
      expect(shiftedLabel(entry.key), entry.value);
    }
    // Letters already display uppercase and named keys have no shifted
    // character, so their labels stay unchanged.
    expect(shiftedLabel('Q'), 'Q');
    expect(shiftedLabel('a'), 'a');
    expect(shiftedLabel('Esc'), 'Esc');
    expect(shiftedLabel('Space'), 'Space');
    expect(shiftedLabel('Shift'), 'Shift');
    // Step 24, item 2; step 25, item 1: the 'Left'/'Right' mouse keys are
    // not character keys, so Shift never changes their labels.
    expect(shiftedLabel('Left'), 'Left');
    expect(shiftedLabel('Right'), 'Right');
  });
}
