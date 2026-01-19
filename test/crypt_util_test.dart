import 'package:test/test.dart';
import 'package:wenzbak/src/utils/crypt_util.dart';
import 'dart:typed_data';
import 'dart:convert';

void main() {
  group('WenzbakCryptUtil 加密工具测试', () {
    const String testSecretKey = 'my_test_secret_key';
    const String testSecret = 'my_test_secret_key_12345678901234567890';
    late WenzbakCryptUtil cryptUtil;

    setUp(() {
      cryptUtil = WenzbakCryptUtil(testSecretKey,testSecret);
    });

    test('基本加密解密测试', () {
      final originalData = utf8.encode('Hello, World! 你好，世界！');
      final data = Uint8List.fromList(originalData);

      // 加密
      final encrypted = cryptUtil.encrypt(data);

      // 验证加密后的数据不为空且长度大于原始数据（因为包含IV）
      expect(encrypted, isNotEmpty);
      expect(encrypted.length, greaterThan(data.length));

      // 解密
      final decrypted = cryptUtil.decrypt(encrypted);

      // 验证解密后的数据与原始数据相同
      expect(decrypted, equals(data));
      expect(utf8.decode(decrypted), equals('Hello, World! 你好，世界！'));
    });

    test('空数据加密解密测试', () {
      final emptyData = Uint8List(0);

      // 加密空数据应该返回空数据
      final encrypted = cryptUtil.encrypt(emptyData);
      expect(encrypted, isEmpty);

      // 解密空数据应该返回空数据
      final decrypted = cryptUtil.decrypt(emptyData);
      expect(decrypted, isEmpty);
    });

    test('大数据加密解密测试', () {
      // 创建一个较大的数据块（1KB）
      final largeData = Uint8List(1024);
      for (int i = 0; i < largeData.length; i++) {
        largeData[i] = i % 256;
      }

      // 加密
      final encrypted = cryptUtil.encrypt(largeData);
      expect(encrypted.length, greaterThan(largeData.length));

      // 解密
      final decrypted = cryptUtil.decrypt(encrypted);
      expect(decrypted, equals(largeData));
    });

    test('相同数据多次加密结果不同（IV随机性）', () {
      final data = utf8.encode('Test data for IV randomness');
      final dataBytes = Uint8List.fromList(data);

      // 多次加密相同数据
      final encrypted1 = cryptUtil.encrypt(dataBytes);
      final encrypted2 = cryptUtil.encrypt(dataBytes);
      final encrypted3 = cryptUtil.encrypt(dataBytes);

      // 验证每次加密的结果都不同（因为IV不同）
      expect(encrypted1, isNot(equals(encrypted2)));
      expect(encrypted2, isNot(equals(encrypted3)));
      expect(encrypted1, isNot(equals(encrypted3)));

      // 但解密后应该都得到相同的结果
      expect(cryptUtil.decrypt(encrypted1), equals(dataBytes));
      expect(cryptUtil.decrypt(encrypted2), equals(dataBytes));
      expect(cryptUtil.decrypt(encrypted3), equals(dataBytes));
    });

    test('验证加密数据格式（IV在前16字节）', () {
      final data = utf8.encode('Test data format');
      final dataBytes = Uint8List.fromList(data);

      final encrypted = cryptUtil.encrypt(dataBytes);

      // 验证加密数据长度至少为16字节（IV长度）
      expect(encrypted.length, greaterThanOrEqualTo(16));

      // 提取IV和加密数据
      final iv = encrypted.sublist(0, 16);
      final encryptedData = encrypted.sublist(16);

      // 验证IV不为空
      expect(iv.length, equals(16));
      expect(encryptedData, isNotEmpty);

      // 使用提取的IV解密（通过重新加密来验证格式）
      final decrypted = cryptUtil.decrypt(encrypted);
      expect(decrypted, equals(dataBytes));
    });

    test('不同密钥加密的数据不能互相解密', () {
      final data = utf8.encode('Secret message');
      final dataBytes = Uint8List.fromList(data);

      // 使用第一个密钥加密
      final cryptUtil1 = WenzbakCryptUtil(testSecretKey,'secret_key_1');
      final encrypted1 = cryptUtil1.encrypt(dataBytes);

      // 使用第二个密钥尝试解密
      final cryptUtil2 = WenzbakCryptUtil(testSecretKey,'secret_key_2');

      // 应该抛出异常，因为密钥不匹配
      expect(
        () => cryptUtil2.decrypt(encrypted1),
        throwsA(isA<Exception>()),
      );
    });

    test('空密钥应该抛出异常', () {
      expect(
        () => WenzbakCryptUtil(testSecretKey,''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('错误格式的加密数据应该抛出异常', () {
      // 创建一个长度小于16字节的数据（不足以包含IV）
      final invalidData = Uint8List(10);

      expect(
        () => cryptUtil.decrypt(invalidData),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('二进制数据加密解密测试', () {
      // 创建包含各种字节值的数据
      final binaryData = Uint8List(256);
      for (int i = 0; i < 256; i++) {
        binaryData[i] = i;
      }

      final encrypted = cryptUtil.encrypt(binaryData);
      final decrypted = cryptUtil.decrypt(encrypted);

      expect(decrypted, equals(binaryData));
    });

    test('Unicode字符加密解密测试', () {
      final unicodeText = '测试数据 🚀 特殊字符: !@#\$%^&*()_+-=[]{}|;:,.<>?';
      final data = utf8.encode(unicodeText);
      final dataBytes = Uint8List.fromList(data);

      final encrypted = cryptUtil.encrypt(dataBytes);
      final decrypted = cryptUtil.decrypt(encrypted);

      expect(utf8.decode(decrypted), equals(unicodeText));
    });

    test('多次加密解密循环测试', () {
      final originalData = utf8.encode('Round trip test');
      var data = Uint8List.fromList(originalData);

      // 进行多次加密解密循环
      for (int i = 0; i < 10; i++) {
        data = cryptUtil.encrypt(data);
        data = cryptUtil.decrypt(data);
      }

      expect(utf8.decode(data), equals('Round trip test'));
    });

    test('不同长度的密钥测试', () {
      final data = utf8.encode('Test with different key lengths');
      final dataBytes = Uint8List.fromList(data);

      // 测试短密钥
      final shortKeyUtil = WenzbakCryptUtil(testSecretKey,'short');
      final encrypted1 = shortKeyUtil.encrypt(dataBytes);
      expect(shortKeyUtil.decrypt(encrypted1), equals(dataBytes));

      // 测试长密钥
      final longKey = 'a' * 100;
      final longKeyUtil = WenzbakCryptUtil(testSecretKey,longKey);
      final encrypted2 = longKeyUtil.encrypt(dataBytes);
      expect(longKeyUtil.decrypt(encrypted2), equals(dataBytes));

      // 验证不同密钥加密的结果不同
      expect(encrypted1, isNot(equals(encrypted2)));
    });
  });
}

