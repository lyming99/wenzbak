import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'dart:convert';
import 'dart:math';
import 'dart:io';

/// 数据加密工具类
/// 通过密钥字符串对二进制数据加解密
/// 使用AES-256-CBC加密算法，提供更高的安全性
class WenzbakCryptUtil {
  final String _secretKey;
  final String _secret;
  late final enc.Key _key;
  static const int _keyLength = 32; // AES-256需要32字节密钥
  static const int _ivLength = 16; // AES块大小
  static const int _chunkSize = 1024 * 1024; // 1MB块大小
  static const int _lengthBytes = 4; // length字段占4字节（大端序）

  WenzbakCryptUtil(this._secretKey, this._secret) {
    if (_secretKey.isEmpty) {
      throw ArgumentError('密钥不能为空');
    }
    if (_secret.isEmpty) {
      throw ArgumentError('密钥不能为空');
    }

    // 使用PBKDF2派生密钥，比直接使用SHA256更安全
    _key = _deriveKey(_secret);
  }

  /// 加密二进制数据
  /// [data] 要加密的二进制数据
  /// 返回加密后的二进制数据
  /// 格式：IV(16字节) + 加密数据
  Uint8List encrypt(Uint8List data) {
    if (data.isEmpty) {
      return data;
    }

    try {
      // 生成随机IV（初始化向量）
      final iv = enc.IV(_generateRandomBytes(_ivLength));

      // 创建加密器，使用AES-256-CBC模式
      final encrypter = enc.Encrypter(enc.AES(_key));

      // 加密数据
      final encrypted = encrypter.encryptBytes(data, iv: iv);

      // 将IV和加密数据组合：IV(16字节) + 加密数据
      final result = Uint8List(_ivLength + encrypted.bytes.length);
      result.setRange(0, _ivLength, iv.bytes);
      result.setRange(_ivLength, result.length, encrypted.bytes);

      return result;
    } catch (e) {
      throw Exception('加密失败: $e');
    }
  }

  /// 解密二进制数据
  /// [data] 要解密的二进制数据
  /// 格式：IV(16字节) + 加密数据
  /// 返回解密后的二进制数据
  Uint8List decrypt(Uint8List data) {
    if (data.isEmpty) {
      return data;
    }

    if (data.length < _ivLength) {
      throw ArgumentError('加密数据格式错误：数据长度不足');
    }

    try {
      // 提取IV和加密数据
      final ivBytes = data.sublist(0, _ivLength);
      final encryptedData = data.sublist(_ivLength);

      final iv = enc.IV(ivBytes);

      // 创建解密器，使用AES-256-CBC模式
      final encrypter = enc.Encrypter(enc.AES(_key));

      // 解密数据
      final encrypted = enc.Encrypted(encryptedData);
      final decrypted = encrypter.decryptBytes(encrypted, iv: iv);

      return Uint8List.fromList(decrypted);
    } catch (e) {
      throw Exception('解密失败: $e');
    }
  }

  /// 从密钥字符串派生加密密钥
  /// 使用PBKDF2算法，比直接使用SHA256更安全
  enc.Key _deriveKey(String secret) {
    // 使用PBKDF2派生密钥
    final salt = utf8.encode(_secretKey);
    final iterations = 10000; // PBKDF2迭代次数

    // 使用PBKDF2派生密钥
    final keyBytes = _pbkdf2(utf8.encode(secret), salt, iterations, _keyLength);

    return enc.Key(keyBytes);
  }

  /// PBKDF2密钥派生函数实现
  /// [password] 密码字节
  /// [salt] 盐值字节
  /// [iterations] 迭代次数
  /// [keyLength] 派生密钥长度
  Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, password);
    final key = Uint8List(keyLength);
    var offset = 0;

    // 计算需要的块数（每个SHA256哈希输出32字节）
    final hashLength = 32;
    final blockCount = (keyLength / hashLength).ceil().toInt();

    for (var i = 1; i <= blockCount; i++) {
      // 构建 salt || i (i是4字节大端序整数)
      final u1Input = Uint8List(salt.length + 4);
      u1Input.setRange(0, salt.length, salt);
      u1Input[salt.length] = (i >> 24) & 0xFF;
      u1Input[salt.length + 1] = (i >> 16) & 0xFF;
      u1Input[salt.length + 2] = (i >> 8) & 0xFF;
      u1Input[salt.length + 3] = i & 0xFF;

      // U1 = HMAC(password, salt || i)
      var u = hmac.convert(u1Input).bytes;
      final t = Uint8List.fromList(u);

      // 迭代计算 U2, U3, ..., U_iterations
      // T = U1 XOR U2 XOR U3 XOR ... XOR U_iterations
      for (var j = 1; j < iterations; j++) {
        // U_j = HMAC(password, U_{j-1})
        u = hmac.convert(u).bytes;
        // T = T XOR U_j
        for (var k = 0; k < u.length; k++) {
          t[k] ^= u[k];
        }
      }

      // 将结果复制到key中
      final copyLength = min(t.length, keyLength - offset);
      if (copyLength == t.length) {
        key.setRange(offset, offset + copyLength, t);
      } else {
        key.setRange(offset, offset + copyLength, t.sublist(0, copyLength));
      }
      offset += copyLength;
    }

    return key;
  }

  /// 生成随机字节
  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// 加密文件
  /// [inputPath] 输入文件路径
  /// [outputPath] 输出文件路径
  /// 通过文件流的形式加密，每1MB数据作为一个块
  /// 序列化方式：每一段一个length(4字节大端序) + encrypted_bytes
  Future<void> encryptFile(String inputPath, String outputPath) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FileSystemException('输入文件不存在: $inputPath');
    }

    final outputFile = File(outputPath);
    // 确保输出目录存在
    await outputFile.parent.create(recursive: true);

    final inputRaf = await inputFile.open(mode: FileMode.read);
    final outputRaf = await outputFile.open(mode: FileMode.write);

    try {
      final fileSize = await inputFile.length();
      var position = 0;

      while (position < fileSize) {
        // 计算本次读取的大小（最多1MB）
        final remaining = fileSize - position;
        final readSize = remaining > _chunkSize ? _chunkSize : remaining;

        // 读取1MB块
        final chunk = await inputRaf.read(readSize);
        if (chunk.isEmpty) {
          break;
        }

        // 加密当前块
        final encryptedChunk = encrypt(chunk);

        // 写入length（4字节大端序）
        final lengthBytes = Uint8List(_lengthBytes);
        lengthBytes[0] = (encryptedChunk.length >> 24) & 0xFF;
        lengthBytes[1] = (encryptedChunk.length >> 16) & 0xFF;
        lengthBytes[2] = (encryptedChunk.length >> 8) & 0xFF;
        lengthBytes[3] = encryptedChunk.length & 0xFF;
        await outputRaf.writeFrom(lengthBytes);

        // 写入加密后的数据
        await outputRaf.writeFrom(encryptedChunk);

        position += readSize;
      }

      await inputRaf.close();
      await outputRaf.close();
    } catch (e) {
      await inputRaf.close();
      await outputRaf.close();
      await outputFile.delete();
      throw Exception('文件加密失败: $e');
    }
  }

  /// 解密文件
  /// [inputPath] 输入文件路径（加密文件）
  /// [outputPath] 输出文件路径（解密文件）
  /// 通过文件流的形式解密，读取格式：length(4字节大端序) + encrypted_bytes
  Future<void> decryptFile(String inputPath, String outputPath) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw FileSystemException('输入文件不存在: $inputPath');
    }

    final outputFile = File(outputPath);
    // 确保输出目录存在
    await outputFile.parent.create(recursive: true);

    final inputRaf = await inputFile.open(mode: FileMode.read);
    final outputRaf = await outputFile.open(mode: FileMode.write);

    try {
      final fileSize = await inputFile.length();
      var position = 0;

      while (position < fileSize) {
        // 读取length（4字节大端序）
        if (position + _lengthBytes > fileSize) {
          throw ArgumentError('文件格式错误：数据不完整');
        }

        final lengthBytes = await inputRaf.read(_lengthBytes);
        if (lengthBytes.length != _lengthBytes) {
          throw ArgumentError('文件格式错误：无法读取长度字段');
        }

        final chunkLength = (lengthBytes[0] << 24) |
            (lengthBytes[1] << 16) |
            (lengthBytes[2] << 8) |
            lengthBytes[3];

        position += _lengthBytes;

        // 验证length的合理性
        if (chunkLength < 0 || chunkLength > fileSize) {
          throw ArgumentError('无效的块长度: $chunkLength');
        }

        // 读取加密数据块
        if (position + chunkLength > fileSize) {
          throw ArgumentError('文件格式错误：数据不完整');
        }

        final encryptedChunk = await inputRaf.read(chunkLength);
        if (encryptedChunk.length != chunkLength) {
          throw ArgumentError('文件格式错误：无法读取完整的数据块');
        }

        position += chunkLength;

        // 解密当前块
        final decryptedChunk = decrypt(encryptedChunk);

        // 写入解密后的数据
        await outputRaf.writeFrom(decryptedChunk);
      }

      await inputRaf.close();
      await outputRaf.close();
    } catch (e) {
      await inputRaf.close();
      await outputRaf.close();
      await outputFile.delete();
      if (e is ArgumentError || e is FileSystemException) {
        rethrow;
      }
      throw Exception('文件解密失败: $e');
    }
  }
}
