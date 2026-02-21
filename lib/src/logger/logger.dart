/// 日志级别枚举
enum LogLevel {
  /// 调试信息
  debug,

  /// 一般信息
  info,

  /// 警告信息
  warn,

  /// 错误信息
  error,
}

/// 日志抽象接口 - 由调用者实现
///
/// 调用者可以根据需求实现不同的日志输出方式：
/// - 控制台输出（开发调试）
/// - 文件输出（本地记录）
/// - 远程上报（生产环境）
/// - 数据库存储（持久化）
abstract class Logger {
  /// 当前日志级别
  LogLevel get level;

  /// 设置日志级别
  void setLevel(LogLevel level);

  /// 记录调试信息
  void debug(String message, {String? tag});

  /// 记录一般信息
  void info(String message, {String? tag});

  /// 记录警告信息
  void warn(String message, {String? tag});

  /// 记录错误信息
  void error(String message,
      {dynamic error, StackTrace? stackTrace, String? tag});
}

/// 空实现（默认，不记录日志）
///
/// 不记录任何日志，零性能开销
class NoOpLogger implements Logger {
  const NoOpLogger();

  @override
  final LogLevel level = LogLevel.info;

  @override
  void setLevel(LogLevel level) {
  }

  @override
  void debug(String message, {String? tag}) {}

  @override
  void info(String message, {String? tag}) {}

  @override
  void warn(String message, {String? tag}) {}

  @override
  void error(String message,
      {dynamic error, StackTrace? stackTrace, String? tag}) {}
}
