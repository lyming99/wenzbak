import 'package:minio/minio.dart';

class StorageClientUtil {
  /// 创建 Minio 客户端，正确解析 endpoint
  ///
  /// 支持的 endpoint 格式:
  /// - http://localhost:9000
  /// - https://play.min.io
  /// - s3.amazonaws.com (默认 https)
  /// - 192.168.1.100:9000
  static Minio createMinioClient(
    String endpoint,
    String accessKey,
    String secretKey,
    String? region,
  ) {
    // 解析协议和端口
    var useSSL = true; // 默认使用 HTTPS
    var port = 0; // 0 表示自动推断

    if (endpoint.startsWith('https://')) {
      useSSL = true;
      endpoint = endpoint.substring(8);
    } else if (endpoint.startsWith('http://')) {
      useSSL = false;
      endpoint = endpoint.substring(7);
    }

    // 提取端口
    var portIndex = endpoint.indexOf(':');
    var slashIndex = endpoint.indexOf('/');
    if (slashIndex == -1) slashIndex = endpoint.length;

    if (portIndex != -1 && portIndex < slashIndex) {
      port = int.parse(endpoint.substring(portIndex + 1, slashIndex));
      endpoint = endpoint.substring(0, portIndex);
    } else {
      // 移除路径部分
      if (slashIndex != endpoint.length) {
        endpoint = endpoint.substring(0, slashIndex);
      }
    }

    return Minio(
      endPoint: endpoint,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      useSSL: useSSL,
      port: port > 0 ? port : null,
    );
  }

  /// todo 实现数据上传
  static Future createUploadBlockTask({
    required String config,
    String? serverId,
    required String blockFile,
  }) async {
    // TODO: 实现数据上传
  }
}
