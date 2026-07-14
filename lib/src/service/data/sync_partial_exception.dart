/// 单个同步资源的失败明细。
class SyncDownloadFailure {
  const SyncDownloadFailure({
    required this.path,
    required this.sha256,
    required this.error,
    required this.stackTrace,
  });

  /// 下载失败的远端路径。
  final String path;

  /// 索引中记录的预期 SHA256。
  final String? sha256;

  /// 底层抛出的原始错误。
  final Object error;

  /// 底层错误堆栈。
  final StackTrace stackTrace;

  @override
  String toString() => '$path: $error';
}

/// 一轮同步部分成功时抛出的异常。
///
/// 成功的数据块已经正常交付给接收器；[failures] 中的数据块没有写入本地
/// SHA256，下轮同步仍会重试。
class SyncPartialException implements Exception {
  SyncPartialException({
    required this.total,
    required Iterable<SyncDownloadFailure> failures,
  }) : failures = List<SyncDownloadFailure>.unmodifiable(failures);

  /// 本轮尝试下载的数据块总数。
  final int total;

  /// 下载失败的数据块明细。
  final List<SyncDownloadFailure> failures;

  int get failed => failures.length;

  int get succeeded => total - failed;

  @override
  String toString() {
    final failedPaths = failures.map((failure) => failure.path).join(', ');
    return 'SyncPartialException('
        'succeeded: $succeeded, failed: $failed, total: $total, '
        'paths: [$failedPaths])';
  }
}
