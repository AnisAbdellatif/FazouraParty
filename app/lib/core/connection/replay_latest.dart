import 'dart:async';

/// A multi-listener stream source that replays its latest value to every new
/// listener (the state/status streams must not lose the snapshot pushed right
/// after join, even if the UI subscribes later).
class ReplayLatest<T> {
  ReplayLatest([T? initial]) : _latest = initial, _hasLatest = initial != null;

  final StreamController<T> _controller = StreamController<T>.broadcast();
  T? _latest;
  bool _hasLatest;

  bool get isClosed => _controller.isClosed;

  Stream<T> get stream => Stream<T>.multi((multi) {
    if (_hasLatest) {
      multi.add(_latest as T);
    }
    if (_controller.isClosed) {
      multi.close();
      return;
    }
    final subscription = _controller.stream.listen(
      multi.add,
      onError: multi.addError,
      onDone: multi.close,
    );
    multi.onCancel = subscription.cancel;
  });

  void add(T value) {
    if (_controller.isClosed) return;
    _latest = value;
    _hasLatest = true;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();
}
