import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/file.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/file_utils.dart';
import 'package:xml/xml.dart' as xml;

/// S3 存储客户端
class S3StorageClient extends WenzbakStorageClientService {
  final WenzbakConfig config;
  final String endpoint;
  final String accessKey;
  final String secretKey;
  final String bucket;
  final String? region;
  final Uuid _uuid = const Uuid();
  final http.Client _client = http.Client();

  S3StorageClient(
    this.config,
    this.endpoint,
    this.accessKey,
    this.secretKey,
    this.bucket,
    this.region,
  ) {
    clientId = _uuid.v4();
  }

  @override
  bool get isRangeSupport => true;

  String _normalizePath(String path) {
    path = path.replaceAll('\\', '/');
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    return path;
  }

  String _getObjectKey(String remotePath) {
    return _normalizePath(remotePath);
  }

  String _getUrl(String objectKey) {
    var base = endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;
    if (base.contains('://')) {
      // 如果 endpoint 包含协议，直接使用
      return '$base/$bucket/$objectKey';
    } else {
      // 否则使用 https
      return 'https://$base/$bucket/$objectKey';
    }
  }

  /// 获取当前时间戳（用于签名）
  Map<String, String> _getTimestamp() {
    var now = DateTime.now().toUtc();
    var dateStamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    var amzDate = '${dateStamp}T${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}Z';
    return {'dateStamp': dateStamp, 'amzDate': amzDate};
  }

  /// URL 编码路径（AWS S3 规范）
  String _encodeUri(String path) {
    // S3 需要特殊编码：除了 / 之外的所有字符都需要编码
    var encoded = StringBuffer();
    for (var i = 0; i < path.length; i++) {
      var char = path[i];
      if (char == '/') {
        encoded.write('/');
      } else {
        var code = char.codeUnitAt(0);
        if ((code >= 0x30 && code <= 0x39) || // 0-9
            (code >= 0x41 && code <= 0x5A) || // A-Z
            (code >= 0x61 && code <= 0x7A) || // a-z
            char == '_' || char == '-' || char == '.' || char == '~') {
          encoded.write(char);
        } else {
          // URL 编码
          encoded.write('%${code.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      }
    }
    return encoded.toString();
  }

  /// 规范化查询字符串（AWS S3 规范）
  String _normalizeQueryString(String queryString) {
    if (queryString.isEmpty) {
      return '';
    }
    
    // 解析查询参数
    var params = <MapEntry<String, String>>[];
    var pairs = queryString.split('&');
    for (var pair in pairs) {
      var parts = pair.split('=');
      if (parts.length == 2) {
        var key = Uri.decodeComponent(parts[0]);
        var value = Uri.decodeComponent(parts[1]);
        params.add(MapEntry(key, value));
      } else if (parts.length == 1) {
        params.add(MapEntry(Uri.decodeComponent(parts[0]), ''));
      }
    }
    
    // 按 key 排序
    params.sort((a, b) {
      var keyCompare = a.key.compareTo(b.key);
      if (keyCompare != 0) return keyCompare;
      return a.value.compareTo(b.value);
    });
    
    // 构建规范化查询字符串
    var normalized = params.map((e) {
      var encodedKey = Uri.encodeComponent(e.key);
      var encodedValue = Uri.encodeComponent(e.value);
      return '$encodedKey=$encodedValue';
    }).join('&');
    
    return normalized;
  }

  /// AWS Signature Version 4 签名
  String _signRequest(
    String method,
    String uri,
    Map<String, String> headers,
    Uint8List? payload,
    String dateStamp,
    String amzDate, {
    String? queryString,
  }) {
    var reg = region ?? 'us-east-1';
    var service = 's3';

    // 规范化请求
    var canonicalHeaders = <String, String>{};
    var signedHeaders = <String>[];
    
    // 处理现有 headers（转换为小写并去除多余空格）
    // 注意：所有在请求中发送的头都必须在这里签名
    headers.forEach((key, value) {
      var lowerKey = key.toLowerCase();
      // 跳过 x-amz-date（稍后会添加）和 authorization（签名结果）
      // 但包含所有其他头，包括 Content-Type、x-amz-content-sha256 等
      if (lowerKey != 'x-amz-date' && lowerKey != 'authorization') {
        // 规范化 header 值：去除前后空格，将多个连续空格替换为单个空格
        var normalizedValue = value.trim().replaceAll(RegExp(r'\s+'), ' ');
        canonicalHeaders[lowerKey] = normalizedValue;
        if (!signedHeaders.contains(lowerKey)) {
          signedHeaders.add(lowerKey);
        }
      }
    });
    
    // 添加 host 头（必须包含端口号，除非是标准端口）
    var url = Uri.parse(_getUrl(''));
    var host = url.host;
    // 对于非标准端口，必须包含端口号
    if (url.hasPort) {
      if (url.scheme == 'https' && url.port != 443) {
        host = '${url.host}:${url.port}';
      } else if (url.scheme == 'http' && url.port != 80) {
        host = '${url.host}:${url.port}';
      }
    }
    canonicalHeaders['host'] = host;
    if (!signedHeaders.contains('host')) {
      signedHeaders.add('host');
    }
    
    // 添加 x-amz-date
    canonicalHeaders['x-amz-date'] = amzDate;
    if (!signedHeaders.contains('x-amz-date')) {
      signedHeaders.add('x-amz-date');
    }
    
    // 计算 payload hash（在添加 x-amz-content-sha256 之前）
    var payloadHash = sha256.convert(payload ?? Uint8List(0)).toString();
    
    // 对于有 payload 的请求，添加 x-amz-content-sha256 头
    // 注意：这个头必须在签名计算之前添加，并且必须在 headers 参数中传入
    // 如果 headers 中已经包含了 x-amz-content-sha256，使用传入的值
    // 否则，如果有 payload，自动添加
    if (payload != null && payload.isNotEmpty) {
      var lowerKey = 'x-amz-content-sha256';
      if (!canonicalHeaders.containsKey(lowerKey)) {
        canonicalHeaders[lowerKey] = payloadHash;
        if (!signedHeaders.contains(lowerKey)) {
          signedHeaders.add(lowerKey);
        }
      }
    }
    
    signedHeaders.sort();
    
    // 构建规范化 headers 字符串
    // 格式：每行一个 header，格式为 "header-name:header-value"，最后有一个空行
    var canonicalHeadersList = <String>[];
    for (var header in signedHeaders) {
      var value = canonicalHeaders[header] ?? '';
      canonicalHeadersList.add('$header:$value');
    }
    var canonicalHeadersStr = '${canonicalHeadersList.join('\n')}\n';
    
    var signedHeadersStr = signedHeaders.join(';');
    
    // 规范化 URI（需要 URL 编码，但路径中的 / 不编码）
    // 分离 URI 路径和查询字符串
    var uriParts = uri.split('?');
    var uriPath = uriParts[0];
    var uriQuery = uriParts.length > 1 ? uriParts[1] : (queryString ?? '');
    
    // URI 路径应该以 / 开头
    var canonicalUri = uriPath.startsWith('/') ? uriPath : '/$uriPath';
    canonicalUri = _encodeUri(canonicalUri);
    
    // 规范化查询字符串
    var canonicalQueryString = _normalizeQueryString(uriQuery);
    
    // 构建规范化请求
    // 格式：HTTP方法\nURI\n查询字符串\n规范化headers\n签名headers列表\npayload哈希
    var canonicalRequest = [
      method,
      canonicalUri,
      canonicalQueryString,
      canonicalHeadersStr, // 已经是字符串，包含最后的换行符
      signedHeadersStr,
      payloadHash,
    ].join('\n');
    
    // 创建待签名字符串
    var algorithm = 'AWS4-HMAC-SHA256';
    var credentialScope = '$dateStamp/$reg/$service/aws4_request';
    var stringToSign = [
      algorithm,
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    
    // 计算签名
    var kSecret = utf8.encode('AWS4$secretKey');
    var kDate = Hmac(sha256, kSecret).convert(utf8.encode(dateStamp)).bytes;
    var kRegion = Hmac(sha256, kDate).convert(utf8.encode(reg)).bytes;
    var kService = Hmac(sha256, kRegion).convert(utf8.encode(service)).bytes;
    var kSigning = Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
    var signature = Hmac(sha256, kSigning).convert(utf8.encode(stringToSign)).toString();
    
    // 创建授权头
    var authorization = '$algorithm Credential=$accessKey/$credentialScope, SignedHeaders=$signedHeadersStr, Signature=$signature';
    
    return authorization;
  }

  Map<String, String> _getHeaders(String method, String objectKey, {Map<String, String>? additional}) {
    // x-amz-date 会在签名时自动添加，这里不添加
    var headers = <String, String>{};
    if (additional != null) {
      headers.addAll(additional);
    }
    return headers;
  }

  @override
  Future<void> uploadFile(String path, String localFilepath) async {
    var objectKey = _getObjectKey(path);
    var url = _getUrl(objectKey);
    var file = File(localFilepath);
    var bytes = await file.readAsBytes();
    
    var timestamp = _getTimestamp();
    // 计算 payload hash
    var payloadHash = sha256.convert(bytes).toString();
    
    // x-amz-content-sha256 必须在签名中包含
    var headers = _getHeaders('PUT', objectKey, additional: {
      'Content-Type': 'application/octet-stream',
      'x-amz-content-sha256': payloadHash,
    });
    var authorization = _signRequest('PUT', '/$bucket/$objectKey', headers, bytes, timestamp['dateStamp']!, timestamp['amzDate']!);
    
    // 构建最终请求头（必须与签名时完全一致）
    var finalHeaders = <String, String>{
      'Authorization': authorization,
      'x-amz-date': timestamp['amzDate']!,
      'Content-Type': 'application/octet-stream',
      'x-amz-content-sha256': payloadHash,
    };
    // 添加其他在签名中的头
    headers.forEach((key, value) {
      var lowerKey = key.toLowerCase();
      if (lowerKey != 'authorization' && 
          lowerKey != 'x-amz-date' &&
          lowerKey != 'content-type' &&
          lowerKey != 'x-amz-content-sha256') {
        finalHeaders[key] = value;
      }
    });

    // 使用 Request 对象以完全控制请求头
    var request = http.Request('PUT', Uri.parse(url));
    request.headers.clear();
    request.headers.addAll(finalHeaders);
    request.bodyBytes = bytes;

    var response = await _client.send(request).then(http.Response.fromStream);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('上传文件失败: ${response.statusCode} - ${response.body}');
    }
  }

  @override
  Future<void> downloadFile(String path, String localFilepath) async {
    var objectKey = _getObjectKey(path);
    var url = _getUrl(objectKey);
    
    var timestamp = _getTimestamp();
    var headers = _getHeaders('GET', objectKey);
    var authorization = _signRequest('GET', '/$bucket/$objectKey', headers, null, timestamp['dateStamp']!, timestamp['amzDate']!);
    headers['Authorization'] = authorization;
    headers['x-amz-date'] = timestamp['amzDate']!;

    var response = await _client.get(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('下载文件失败: ${response.statusCode} - ${response.body}');
    }

    await FileUtils.createParentDir(localFilepath);
    await File(localFilepath).writeAsBytes(response.bodyBytes);
  }

  @override
  Future<void> deleteFile(String path) async {
    var objectKey = _getObjectKey(path);
    var url = _getUrl(objectKey);
    
    var timestamp = _getTimestamp();
    var headers = _getHeaders('DELETE', objectKey);
    var authorization = _signRequest('DELETE', '/$bucket/$objectKey', headers, null, timestamp['dateStamp']!, timestamp['amzDate']!);
    headers['Authorization'] = authorization;
    headers['x-amz-date'] = timestamp['amzDate']!;

    var response = await _client.delete(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode != 200 && response.statusCode != 204 && response.statusCode != 404) {
      throw Exception('删除文件失败: ${response.statusCode} - ${response.body}');
    }
  }

  @override
  Future<void> createFolder(String path) async {
    // S3 没有真正的文件夹概念，但可以创建一个以 / 结尾的空对象来表示文件夹
    var objectKey = _getObjectKey(path);
    if (!objectKey.endsWith('/')) {
      objectKey = '$objectKey/';
    }
    var url = _getUrl(objectKey);
    
    var timestamp = _getTimestamp();
    var headers = _getHeaders('PUT', objectKey);
    var authorization = _signRequest('PUT', '/$bucket/$objectKey', headers, Uint8List(0), timestamp['dateStamp']!, timestamp['amzDate']!);
    headers['Authorization'] = authorization;
    headers['x-amz-date'] = timestamp['amzDate']!;

    var response = await _client.put(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('创建文件夹失败: ${response.statusCode} - ${response.body}');
    }
  }

  @override
  Future<void> deleteFolder(String path) async {
    // 列出文件夹下的所有对象并删除
    var files = await listFiles(path);
    for (var file in files) {
      if (file.path != null) {
        await deleteFile(file.path!);
      }
    }
    // 删除文件夹标记对象
    var objectKey = _getObjectKey(path);
    if (!objectKey.endsWith('/')) {
      objectKey = '$objectKey/';
    }
    await deleteFile(objectKey);
  }

  @override
  Future<List<WenzbakStorageFile>> listFiles(String path) async {
    var prefix = _getObjectKey(path);
    if (!prefix.endsWith('/') && prefix.isNotEmpty) {
      prefix = '$prefix/';
    }
    
    var queryParams = <String, String>{
      'list-type': '2',
      'prefix': prefix,
    };
    var queryString = queryParams.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
    var url = '${_getUrl('')}?$queryString';
    
    var timestamp = _getTimestamp();
    var headers = _getHeaders('GET', '');
    var authorization = _signRequest('GET', '/$bucket/', headers, null, timestamp['dateStamp']!, timestamp['amzDate']!, queryString: queryString);
    headers['Authorization'] = authorization;
    headers['x-amz-date'] = timestamp['amzDate']!;

    var response = await _client.get(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('列出文件失败: ${response.statusCode} - ${response.body}');
    }

    // 解析 XML 响应
    var files = <WenzbakStorageFile>[];
    var xmlDoc = xml.XmlDocument.parse(response.body);
    var contents = xmlDoc.findAllElements('Contents');
    
    for (var content in contents) {
      var key = content.findElements('Key').firstOrNull?.text;
      if (key == null) continue;
      
      // 跳过当前路径本身
      if (key == prefix || key == path) {
        continue;
      }
      
      // 判断是否为目录（以 / 结尾）
      var isDir = key.endsWith('/');
      
      files.add(WenzbakStorageFile(
        path: key,
        isDir: isDir,
      ));
    }

    return files;
  }

  @override
  Future<Uint8List?> readFile(String path) async {
    var objectKey = _getObjectKey(path);
    var url = _getUrl(objectKey);
    
    var timestamp = _getTimestamp();
    var headers = _getHeaders('GET', objectKey);
    var authorization = _signRequest('GET', '/$bucket/$objectKey', headers, null, timestamp['dateStamp']!, timestamp['amzDate']!);
    headers['Authorization'] = authorization;
    headers['x-amz-date'] = timestamp['amzDate']!;

    var response = await _client.get(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('读取文件失败: ${response.statusCode} - ${response.body}');
    }

    return response.bodyBytes;
  }

  @override
  Future<int> readFileSize(String path) async {
    var objectKey = _getObjectKey(path);
    var url = _getUrl(objectKey);
    
    var timestamp = _getTimestamp();
    var headers = _getHeaders('HEAD', objectKey);
    var authorization = _signRequest('HEAD', '/$bucket/$objectKey', headers, null, timestamp['dateStamp']!, timestamp['amzDate']!);
    headers['Authorization'] = authorization;
    headers['x-amz-date'] = timestamp['amzDate']!;

    var response = await _client.head(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode == 404) {
      return 0;
    }
    if (response.statusCode != 200) {
      throw Exception('获取文件大小失败: ${response.statusCode}');
    }

    var contentLength = response.headers['content-length'];
    if (contentLength != null) {
      return int.parse(contentLength);
    }
    return 0;
  }

  @override
  Future<void> writeFile(String path, Uint8List data) async {
    var objectKey = _getObjectKey(path);
    var url = _getUrl(objectKey);
    
    var timestamp = _getTimestamp();
    // 计算 payload hash
    var payloadHash = sha256.convert(data).toString();
    
    // 注意：所有需要在签名中的头都必须在这里定义
    // x-amz-content-sha256 必须在签名中包含
    var headers = _getHeaders('PUT', objectKey, additional: {
      'Content-Type': 'application/octet-stream',
      'x-amz-content-sha256': payloadHash,
    });
    var authorization = _signRequest('PUT', '/$bucket/$objectKey', headers, data, timestamp['dateStamp']!, timestamp['amzDate']!);
    
    // 构建最终请求头（必须与签名时完全一致）
    var finalHeaders = <String, String>{
      'Authorization': authorization,
      'x-amz-date': timestamp['amzDate']!,
      'Content-Type': 'application/octet-stream',
      'x-amz-content-sha256': payloadHash,
    };
    // 添加其他在签名中的头（除了已经添加的）
    headers.forEach((key, value) {
      var lowerKey = key.toLowerCase();
      if (lowerKey != 'authorization' && 
          lowerKey != 'x-amz-date' &&
          lowerKey != 'content-type' &&
          lowerKey != 'x-amz-content-sha256') {
        finalHeaders[key] = value;
      }
    });

    // 使用 Request 对象以完全控制请求头
    var request = http.Request('PUT', Uri.parse(url));
    // 只添加我们明确设置的头，不添加任何其他头
    request.headers.clear();
    request.headers.addAll(finalHeaders);
    request.bodyBytes = data;

    var response = await _client.send(request).then(http.Response.fromStream);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('写入文件失败: ${response.statusCode} - ${response.body}');
    }
  }

  @override
  Future<Uint8List> readRange(String path, int start, int length) async {
    var objectKey = _getObjectKey(path);
    var url = _getUrl(objectKey);
    
    var timestamp = _getTimestamp();
    var headers = _getHeaders('GET', objectKey, additional: {
      'Range': 'bytes=$start-${start + length - 1}',
    });
    var authorization = _signRequest('GET', '/$bucket/$objectKey', headers, null, timestamp['dateStamp']!, timestamp['amzDate']!);
    headers['Authorization'] = authorization;
    headers['x-amz-date'] = timestamp['amzDate']!;

    var response = await _client.get(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode != 206 && response.statusCode != 200) {
      throw Exception('读取文件范围失败: ${response.statusCode} - ${response.body}');
    }

    var bytes = response.bodyBytes;
    if (bytes.length > length) {
      return bytes.sublist(0, length);
    }
    return bytes;
  }

  @override
  Future<void> writeRange(String path, int start, Uint8List data) async {
    // S3 不支持部分写入，需要先读取整个对象，修改后重新写入
    // 或者使用 multipart upload（更复杂）
    var existingData = await readFile(path) ?? Uint8List(0);
    
    // 扩展文件大小如果需要
    if (existingData.length < start) {
      var padding = Uint8List(start - existingData.length);
      existingData = Uint8List.fromList([...existingData, ...padding]);
    }

    // 合并数据
    var newData = Uint8List.fromList([
      ...existingData.sublist(0, start),
      ...data,
      if (start + data.length < existingData.length)
        ...existingData.sublist(start + data.length),
    ]);

    await writeFile(path, newData);
  }

  void dispose() {
    _client.close();
  }
}
