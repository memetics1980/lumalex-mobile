/// Watches raw pointer positions without claiming Flutter's gesture arena.
///
/// A reader WebView must keep receiving touch events so it can scroll and
/// select text. Only a single, clearly horizontal touch may switch dictionaries.
class ReaderPageSwipeTracker {
  final Set<int> _downPointers = {};
  int? _primaryPointer;
  double _startX = 0;
  double _startY = 0;
  bool _eligible = false;

  void pointerDown({
    required int pointer,
    required double x,
    required double y,
    required double width,
  }) {
    _downPointers.add(pointer);
    if (_downPointers.length != 1) {
      _eligible = false;
      return;
    }
    _primaryPointer = pointer;
    _startX = x;
    _startY = y;
    _eligible = x >= 32 && x <= width - 32;
  }

  void pointerMove({
    required int pointer,
    required double x,
    required double y,
  }) {
    if (!_eligible || pointer != _primaryPointer) return;
    final dx = (x - _startX).abs();
    final dy = (y - _startY).abs();
    // Lock out a clearly vertical start, but allow the mild downward arc of
    // a thumb swipe. Once locked out, later sideways drift cannot switch.
    if (dy >= 32 && dy > dx * 1.5) _eligible = false;
  }

  /// Returns the requested direction, or null when no switch should occur.
  /// True moves forward; false moves backward.
  bool? pointerUp({
    required int pointer,
    required double x,
    required double y,
  }) {
    bool? forward;
    if (pointer == _primaryPointer && _downPointers.length == 1 && _eligible) {
      pointerMove(pointer: pointer, x: x, y: y);
      final dx = x - _startX;
      final dy = y - _startY;
      if (_eligible && dx.abs() >= 72 && dx.abs() >= dy.abs() * 1.25) {
        forward = dx < 0;
      }
    }
    _release(pointer);
    return forward;
  }

  void pointerCancel(int pointer) => _release(pointer);

  void _release(int pointer) {
    _downPointers.remove(pointer);
    if (pointer == _primaryPointer) {
      _primaryPointer = null;
      _eligible = false;
    }
  }
}
