/// Runs asynchronous tasks one after another.
///
/// Each task starts only after the previous one has finished (whether it
/// succeeded or failed), so overlapping writes cannot overwrite one another.
/// A failure is still reported to the caller of [run].
class SerialTasks {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
