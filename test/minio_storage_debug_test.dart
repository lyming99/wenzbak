import 'dart:convert';
import 'dart:typed_data';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/storage/storage.dart';

/// MinIO 存储客户端调试测试
/// 专门用于调试签名问题
void main() async {
  print('=== MinIO 存储客户端调试测试 ===\n');

  var minioConfig = {
    'endpoint': 'http://localhost:9000',
    'accessKey': 'minioadmin',
    'secretKey': 'minioadmin',
    'bucket': 'wenzbak',
    'region': 'us-east-1',
  };

  var config = WenzbakConfig(
    deviceId: 'test-device-001',
    localRootPath: './test_local',
    remoteRootPath: '/',
    storageType: 's3',
    storageConfig: jsonEncode(minioConfig),
  );

  var storage = WenzbakStorageClientService.getInstance(config);
  if (storage == null) {
    print('❌ 存储客户端创建失败');
    return;
  }

  print('✅ 存储客户端创建成功\n');

  // 测试写入文件（这是失败的操作）
  print('--- 测试写入文件（调试模式） ---');
  try {
    var testData = utf8.encode('Hello, MinIO!');
    print('准备写入数据: ${testData.length} 字节');
    print('数据内容: ${utf8.decode(testData)}');
    
    await storage.writeFile('debug-test.txt', Uint8List.fromList(testData));
    print('✅ 文件写入成功');
    
    // 验证写入
    var readData = await storage.readFile('debug-test.txt');
    if (readData != null) {
      print('✅ 文件读取验证成功');
      print('   读取内容: ${utf8.decode(readData)}');
    }
    
    // 清理
    await storage.deleteFile('debug-test.txt');
    print('✅ 测试文件已清理');
  } catch (e, stackTrace) {
    print('❌ 写入失败: $e');
    print('\n详细错误信息:');
    _analyzeSignatureError(e.toString());
  }
}

void _analyzeSignatureError(String error) {
  if (error.contains('SignatureDoesNotMatch')) {
    print('检测到签名不匹配错误');
    print('\n可能的问题:');
    print('1. URI 路径编码不正确');
    print('2. Host 头格式不正确（需要包含端口号）');
    print('3. Content-Type 头处理不正确');
    print('4. 规范化请求格式不正确');
    print('5. 查询字符串处理不正确');
    print('6. 时间戳格式不正确');
    print('\n建议检查:');
    print('- 确保 URI 路径正确编码（/ 不编码，其他字符按需编码）');
    print('- 确保 Host 头包含端口号（如 localhost:9000）');
    print('- 确保 Content-Type 头在签名和请求中都存在且一致');
    print('- 确保规范化请求的格式完全符合 AWS S3 规范');
  }
}
