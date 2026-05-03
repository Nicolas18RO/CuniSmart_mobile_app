/// Reusable async resource states for MVVM (list/detail screens).
///
/// - [AsyncInitial] — before first load.
/// - [AsyncLoading] — in flight; optional [cachedData] for refresh UX.
/// - [AsyncSuccess] — loaded; [data] may be empty (e.g. empty list → empty UI).
/// - [AsyncError] — failed; optional [cachedData] to keep last good data on refresh failure.
sealed class AsyncViewState<T> {
  const AsyncViewState();
}

final class AsyncInitial<T> extends AsyncViewState<T> {
  const AsyncInitial();
}

final class AsyncLoading<T> extends AsyncViewState<T> {
  const AsyncLoading({this.cachedData});

  /// Previous successful value while reloading (e.g. pull-to-refresh).
  final T? cachedData;
}

final class AsyncSuccess<T> extends AsyncViewState<T> {
  const AsyncSuccess(this.data);

  final T data;
}

final class AsyncError<T> extends AsyncViewState<T> {
  const AsyncError(this.message, {this.cachedData});

  final String message;

  /// Last successful data when refresh fails (non-destructive error).
  final T? cachedData;
}
