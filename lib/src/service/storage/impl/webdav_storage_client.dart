import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/file.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/file_utils.dart';
import 'package:xml/xml.dart' as xml;

/// WebDAV 存储客户端
class WebDAVStorageClient extends WenzbakStorageClientService {
  final WenzbakConfig config;
  final String baseUrl;
  final String? username;
  final String? password;
  final Uuid _uuid = const Uuid();
  final http.Client _client = http.Client();

  WebDAVStorageClient(this.config, this.baseUrl, this.username, this.password) {
    clientId = _uuid.v4();
  }

  @override
  bool get isRangeSupport => true;

  String _normalizePath(String path) {
    // 移除开头的斜杠，确保路径格式正确
    path = path.replaceAll('\\', '/');
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    return path;
  }

  String _getFullUrl(String remotePath) {
    var normalizedPath = _normalizePath(remotePath);
    var base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return '$base$normalizedPath';
  }

  Map<String, String> _getHeaders({Map<String, String>? additional}) {
    var headers = <String, String>{'Content-Type': 'application/octet-stream'};
    if (additional != null) {
      headers.addAll(additional);
    }
    return headers;
  }

  http.BaseRequest _addAuth(http.BaseRequest request) {
    if (username != null && password != null) {
      var credentials = base64Encode(utf8.encode('$username:$password'));
      request.headers['Authorization'] = 'Basic $credentials';
    }
    return request;
  }

  /// 确保父目录存在，如果不存在则递归创建
  Future<void> _ensureParentDirsExist(String path) async {
    var normalizedPath = _normalizePath(path);
    var parts = normalizedPath.split('/');

    // 移除文件名，只保留目录部分
    if (parts.isNotEmpty) {
      parts.removeLast();
    }

    // 递归创建所有父目录
    var currentPath = '';
    for (var part in parts) {
      if (part.isEmpty) continue;
      currentPath = currentPath.isEmpty ? part : '$currentPath/$part';
      try {
        await createFolder(currentPath);
      } catch (e) {
        // 忽略已存在的目录错误（405）
        if (!e.toString().contains('405')) {
          rethrow;
        }
      }
    }
  }

  @override
  Future<void> uploadFile(String path, String localFilepath) async {
    // 确保父目录存在
    await _ensureParentDirsExist(path);

    var url = _getFullUrl(path);
    var file = File(localFilepath);
    var bytes = await file.readAsBytes();

    var request = http.Request('PUT', Uri.parse(url));
    _addAuth(request);
    request.headers.addAll(_getHeaders());
    request.bodyBytes = bytes;

    var response = await _client.send(request);
    if (response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('上传文件失败: ${response.statusCode}');
    }
  }

  @override
  Future<void> downloadFile(String path, String localFilepath) async {
    var url = _getFullUrl(path);
    var request = http.Request('GET', Uri.parse(url));
    _addAuth(request);

    var response = await _client.send(request);
    if (response.statusCode != 200) {
      throw Exception('下载文件失败: ${response.statusCode}');
    }

    await FileUtils.createParentDir(localFilepath);
    var file = File(localFilepath);
    var sink = file.openWrite();
    try {
      await response.stream.forEach((chunk) {
        sink.add(chunk);
      });
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    var url = _getFullUrl(path);
    var request = http.Request('DELETE', Uri.parse(url));
    _addAuth(request);

    var response = await _client.send(request);
    if (response.statusCode != 200 &&
        response.statusCode != 204 &&
        response.statusCode != 404) {
      throw Exception('删除文件失败: ${response.statusCode}');
    }
  }

  @override
  Future<void> createFolder(String path) async {
    var url = _getFullUrl(path);
    if (!url.endsWith('/')) {
      url = '$url/';
    }
    var request = http.Request('MKCOL', Uri.parse(url));
    _addAuth(request);

    var response = await _client.send(request);
    if (response.statusCode != 201 && response.statusCode != 405) {
      // 405 表示目录已存在
      throw Exception('创建文件夹失败: ${response.statusCode}');
    }
  }

  @override
  Future<void> deleteFolder(String path) async {
    await deleteFile(path);
  }

  @override
  Future<List<WenzbakStorageFile>> listFiles(String path) async {
    var url = _getFullUrl(path);
    if (!url.endsWith('/')) {
      url = '$url/';
    }

    var request = http.Request('PROPFIND', Uri.parse(url));
    _addAuth(request);
    request.headers['Depth'] = '1';
    request.headers['Content-Type'] = 'application/xml';

    // 使用标准的 WebDAV PROPFIND XML 格式
    // 只在根元素声明命名空间，子元素会继承
    var body = '''<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <resourcetype/>
    <displayname/>
    <getcontentlength/>
  </prop>
</propfind>''';
    request.body = body;

    var response = await _client.send(request);

    if (response.statusCode != 207) {
      // 读取响应体以获取更详细的错误信息
      var responseBody = await response.stream.bytesToString();
      throw Exception('列出文件失败: ${response.statusCode}, URL: $url, 响应: ${responseBody.length > 200 ? responseBody.substring(0, 200) : responseBody}');
    }

    var responseBody = await response.stream.bytesToString();
    var document = xml.XmlDocument.parse(responseBody);
    var files = <WenzbakStorageFile>[];

    // 解析 WebDAV 响应
    var requestUrl = Uri.parse(url);
    var requestPath = requestUrl.path;

    // 标准化请求路径（移除末尾斜杠，除非是根路径）
    if (requestPath.endsWith('/') && requestPath.length > 1) {
      requestPath = requestPath.substring(0, requestPath.length - 1);
    }
    // 移除开头的斜杠
    if (requestPath.startsWith('/')) {
      requestPath = requestPath.substring(1);
    }
    var davNamespace = "DAV:";
    // 查找所有 response 元素（支持 response 或 response）
    var responses = document.findAllElements(
      'response',
      namespace: davNamespace,
    );
    var seenPaths = <String>{};

    for (var responseElement in responses) {
      // 查找 href 元素（支持 href 或 href）
      var hrefText = responseElement
          .findElements('href', namespace: davNamespace)
          .firstOrNull
          ?.text;
      if (hrefText == null || hrefText.isEmpty) continue;

      // URL 解码
      String href;
      try {
        href = Uri.decodeComponent(hrefText);
      } catch (e) {
        // 解码失败，使用原始值
        href = hrefText;
      }

      // 处理 href，提取路径部分
      String hrefPath;
      try {
        var hrefUri = Uri.parse(href);
        if (hrefUri.hasScheme) {
          hrefPath = hrefUri.path;
        } else {
          hrefPath = href;
        }
      } catch (e) {
        // 不是有效 URI，直接使用
        hrefPath = href;
      }

      // 确保 hrefPath 不为空
      if (hrefPath.isEmpty) {
        continue;
      }

      // 保持绝对路径格式（以 / 开头）
      var absolutePath = hrefPath;
      if (!absolutePath.startsWith('/')) {
        absolutePath = '/$absolutePath';
      }

      // 标准化请求路径（确保以 / 开头）
      var normalizedRequestPath = requestPath;
      if (!normalizedRequestPath.startsWith('/')) {
        normalizedRequestPath = '/$normalizedRequestPath';
      }
      if (!normalizedRequestPath.endsWith('/')) {
        normalizedRequestPath = '$normalizedRequestPath/';
      }

      // 如果 href 路径等于请求路径，跳过（这是当前目录本身）
      if (absolutePath == normalizedRequestPath ||
          absolutePath ==
              normalizedRequestPath.substring(
                0,
                normalizedRequestPath.length - 1,
              )) {
        continue;
      }

      // 如果 href 路径不以请求路径开头，跳过
      if (!absolutePath.startsWith(normalizedRequestPath)) {
        continue;
      }

      // 提取相对于请求路径的部分，用于判断是否为直接子项
      var relativePart = absolutePath.substring(normalizedRequestPath.length);

      // 如果相对部分为空，跳过
      if (relativePart.isEmpty) {
        continue;
      }

      // 只返回直接子项（Depth:1 应该只返回直接子项）
      // 如果相对部分包含斜杠，说明是子目录的子项，跳过
      var parts = relativePart.split('/');
      if (parts.length > 1 && parts.last.isNotEmpty) {
        // 不是直接子项，跳过
        continue;
      }

      // 获取资源类型：需要从状态为 200 的 propstat 中查找
      var isDir = false;
      var propstats = responseElement.findElements(
        'propstat',
        namespace: davNamespace,
      );
      for (var propstat in propstats) {
        // 检查状态是否为 200 OK
        var status =
            propstat
                .findElements('status', namespace: davNamespace)
                .firstOrNull
                ?.text ??
            '';
        if (status.contains('200')) {
          // 查找 resourcetype（支持命名空间前缀）
          var prop = propstat
              .findElements('prop', namespace: davNamespace)
              .firstOrNull;
          if (prop != null) {
            var resourcetype = prop
                .findElements('resourcetype', namespace: davNamespace)
                .firstOrNull;
            if (resourcetype != null) {
              // 检查是否有 collection 子元素（支持 collection 或 collection）
              isDir = resourcetype
                  .findElements('collection', namespace: davNamespace)
                  .isNotEmpty;
              break; // 找到有效的 propstat，退出循环
            }
          }
        }
      }

      // 判断是否为目录：如果 resourcetype 中有 collection，或者路径以 / 结尾
      var isDirectory = isDir || absolutePath.endsWith('/');

      // 移除末尾的斜杠（如果有）用于路径比较
      var pathForComparison = absolutePath;
      if (pathForComparison.endsWith('/') && pathForComparison.length > 1) {
        pathForComparison = pathForComparison.substring(
          0,
          pathForComparison.length - 1,
        );
      }

      // 检查是否已经添加过（避免重复）
      if (seenPaths.contains(pathForComparison)) {
        continue;
      }
      seenPaths.add(pathForComparison);

      // 返回绝对路径（保持以 / 开头的格式，但移除末尾的斜杠）
      var returnPath = absolutePath;
      if (returnPath.endsWith('/') && returnPath.length > 1) {
        returnPath = returnPath.substring(0, returnPath.length - 1);
      }

      files.add(WenzbakStorageFile(path: returnPath, isDir: isDirectory));
    }

    return files;
  }

  @override
  Future<Uint8List?> readFile(String path) async {
    var url = _getFullUrl(path);
    var request = http.Request('GET', Uri.parse(url));
    _addAuth(request);

    var response = await _client.send(request);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('读取文件失败: ${response.statusCode}');
    }

    return await response.stream.toBytes();
  }

  @override
  Future<int> readFileSize(String path) async {
    var url = _getFullUrl(path);
    var request = http.Request('HEAD', Uri.parse(url));
    _addAuth(request);

    var response = await _client.send(request);
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
    // 确保父目录存在
    await _ensureParentDirsExist(path);

    var url = _getFullUrl(path);
    var request = http.Request('PUT', Uri.parse(url));
    _addAuth(request);
    request.headers.addAll(_getHeaders());
    request.bodyBytes = data;

    var response = await _client.send(request);
    if (response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('写入文件失败: ${response.statusCode}');
    }
  }

  @override
  Future<Uint8List> readRange(String path, int start, int length) async {
    var url = _getFullUrl(path);
    var request = http.Request('GET', Uri.parse(url));
    _addAuth(request);
    request.headers['Range'] = 'bytes=$start-${start + length - 1}';

    var response = await _client.send(request);
    if (response.statusCode != 206 && response.statusCode != 200) {
      throw Exception('读取文件范围失败: ${response.statusCode}');
    }

    var bytes = await response.stream.toBytes();
    if (bytes.length > length) {
      return bytes.sublist(0, length);
    }
    return bytes;
  }

  @override
  Future<void> writeRange(String path, int start, Uint8List data) async {
    // WebDAV 不支持部分写入，需要先读取整个文件，修改后重新写入
    // 或者使用 PATCH 方法（如果服务器支持）
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
