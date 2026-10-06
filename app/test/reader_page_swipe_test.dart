import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictionary/models/reader_page_swipe.dart';

void main() {
  test('vertical page scroll never switches, even after sideways drift', () {
    final swipe = ReaderPageSwipeTracker();
    swipe.pointerDown(pointer: 1, x: 200, y: 200, width: 400);
    swipe.pointerMove(pointer: 1, x: 204, y: 240);
    swipe.pointerMove(pointer: 1, x: 320, y: 205);
    expect(swipe.pointerUp(pointer: 1, x: 320, y: 205), isNull);
  });

  test('intentional horizontal swipes switch in either direction', () {
    final swipe = ReaderPageSwipeTracker();
    swipe.pointerDown(pointer: 1, x: 200, y: 200, width: 400);
    swipe.pointerMove(pointer: 1, x: 120, y: 205);
    expect(swipe.pointerUp(pointer: 1, x: 100, y: 210), isTrue);

    swipe.pointerDown(pointer: 2, x: 100, y: 200, width: 400);
    swipe.pointerMove(pointer: 2, x: 180, y: 205);
    expect(swipe.pointerUp(pointer: 2, x: 200, y: 210), isFalse);
  });

  test('a natural downward thumb arc still switches', () {
    final swipe = ReaderPageSwipeTracker();
    swipe.pointerDown(pointer: 1, x: 250, y: 180, width: 400);
    swipe.pointerMove(pointer: 1, x: 220, y: 205);
    swipe.pointerMove(pointer: 1, x: 170, y: 225);
    expect(swipe.pointerUp(pointer: 1, x: 130, y: 250), isTrue);

    swipe.pointerDown(pointer: 2, x: 100, y: 180, width: 400);
    swipe.pointerMove(pointer: 2, x: 132, y: 205);
    expect(swipe.pointerUp(pointer: 2, x: 220, y: 250), isFalse);
  });

  test('a vertical start cannot switch after turning sideways', () {
    final swipe = ReaderPageSwipeTracker();
    swipe.pointerDown(pointer: 1, x: 200, y: 100, width: 400);
    swipe.pointerMove(pointer: 1, x: 225, y: 145);
    expect(swipe.pointerUp(pointer: 1, x: 300, y: 170), isNull);
  });

  test('a diagonal with more vertical than horizontal movement does not switch',
      () {
    final swipe = ReaderPageSwipeTracker();
    swipe.pointerDown(pointer: 1, x: 200, y: 100, width: 400);
    swipe.pointerMove(pointer: 1, x: 240, y: 150);
    expect(swipe.pointerUp(pointer: 1, x: 270, y: 180), isNull);
  });

  test('edge-originating and multitouch gestures do not switch', () {
    final swipe = ReaderPageSwipeTracker();
    swipe.pointerDown(pointer: 1, x: 12, y: 200, width: 400);
    expect(swipe.pointerUp(pointer: 1, x: 120, y: 200), isNull);

    swipe.pointerDown(pointer: 2, x: 200, y: 200, width: 400);
    swipe.pointerDown(pointer: 3, x: 220, y: 200, width: 400);
    expect(swipe.pointerUp(pointer: 2, x: 100, y: 200), isNull);
    expect(swipe.pointerUp(pointer: 3, x: 120, y: 200), isNull);
  });
}
