import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

/// Dwell at the outside of the whole spread, never at its inner gutter/footer.
/// One pending turn at a time; a failed turn stays blocked until edge re-entry.
class SelectionPageTurner {
  static const dwell = Duration(milliseconds: 600);
  final Rect? Function() viewport;
  final Future<bool> Function(int direction) onTurn;
  SelectionPageTurner({required this.viewport, required this.onTurn});

  Timer? _timer;
  int _direction = 0, _generation = 0;
  bool _busy = false, _blocked = false;

  void update(Offset point) {
    final rect = viewport();
    var direction = 0;
    if (rect != null && rect.contains(point)) {
      final edge = math.min(24.0, rect.width / 4);
      if (point.dx < rect.left + edge) direction = -1;
      if (point.dx >= rect.right - edge) direction = 1;
    }
    if (direction == _direction) return;
    _timer?.cancel();
    _generation++;
    _direction = direction;
    _blocked = false;
    _arm();
  }

  void _arm() {
    if (_direction == 0 || _busy || _blocked) return;
    final token = _generation, direction = _direction;
    _timer = Timer(dwell, () async {
      _busy = true;
      try {
        final turned = await onTurn(direction);
        if (token == _generation) _blocked = !turned;
      } finally {
        _busy = false;
        if (token == _generation || _direction != 0) _arm();
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    _direction = 0;
    _blocked = false;
  }
}
