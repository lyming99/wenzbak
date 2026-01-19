import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;

/// SHA256哈希工具类
/// 提供字符串和文件的SHA256哈希计算功能
class Sha256Util {
  Sha256Util._();

  /// 计算字符串的SHA256哈希值
  /// [input] 要计算哈希的字符串
  /// 返回十六进制格式的SHA256哈希值（64个字符）
  static String sha256(String input) {
    final bytes = utf8.encode(input);
    final digest = crypto.sha256.convert(bytes);
    return digest.toString();
  }

  static String sha256Bytes(List<int> input) {
    final digest = crypto.sha256.convert(input);
    return digest.toString();
  }

  /// 大文件可能比较消耗性能，注意使用线程处理
  static Future<crypto.Digest> sha256FileDigest(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', path);
    }
    var innerSink = DigestSink();
    var outerSink = crypto.sha256.startChunkedConversion(innerSink);

    try {
      // 使用文件流分块读取并计算哈希
      // 每次读取的数据块会被立即处理，不会全部保存在内存中
      await for (final chunk in file.openRead()) {
        outerSink.add(chunk);
      }
    } finally {
      // 关闭流，这会触发最终的哈希计算
      outerSink.close();
    }
    // 从接收器中获取最终的哈希值
    return innerSink.value;
  }

  /// 计算文件的SHA256哈希值
  /// [path] 文件路径
  /// 返回十六进制格式的SHA256哈希值（64个字符）
  /// 如果文件不存在，将抛出异常
  /// 使用文件流处理，不会一次性将整个文件加载到内存中，适合处理大文件
  static Future<String> sha256File(String path) async {
    var digest = await sha256FileDigest(path);
    return digest.toString();
  }
}

/// A sink used to get a digest value out of `Hash.startChunkedConversion`.
class DigestSink implements Sink<crypto.Digest> {
  /// The value added to the sink.
  ///
  /// A value must have been added using [add] before reading the `value`.
  crypto.Digest get value => _value!;

  crypto.Digest? _value;

  /// Adds [value] to the sink.
  ///
  /// Unlike most sinks, this may only be called once.
  @override
  void add(crypto.Digest value) {
    if (_value != null) throw StateError('add may only be called once.');
    _value = value;
  }

  @override
  void close() {
    if (_value == null) throw StateError('add must be called once.');
  }
}
