import 'dart:convert';
import 'dart:io';

import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/device.dart';
import 'package:wenzbak/src/service/device/device.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/file_utils.dart';

/// 设备服务实现类
/// 负责设备信息的上传和查询功能
class WenzbakDeviceServiceImpl extends WenzbakDeviceService {
  final WenzbakConfig config;
  final Map<String, WenzbakDeviceInfo> _deviceInfoCache = {};

  WenzbakDeviceServiceImpl(this.config) {
    _loadDeviceInfoCache();
  }

  @override
  Future<bool> uploadDeviceInfo([WenzbakDeviceInfo? deviceInfo]) async {
    try {
      var storage = WenzbakStorageClientService.getInstance(config);
      if (storage == null) {
        throw "未配置存储服务";
      }

      // 1. 获取设备信息（如果未提供则获取当前设备信息）
      if (deviceInfo == null) {
        deviceInfo = await getDeviceSystemInfo();
      } else {
        // 确保设备ID匹配，并更新时间戳
        deviceInfo = WenzbakDeviceInfo(
          deviceId: config.deviceId,
          platform: deviceInfo.platform,
          model: deviceInfo.model,
          osVersion: deviceInfo.osVersion,
          deviceName: deviceInfo.deviceName,
          updateTimestamp: DateTime.now().millisecondsSinceEpoch,
        );
      }

      // 2. 序列化为 JSON
      var jsonStr = jsonEncode(deviceInfo.toJson());

      // 3. 写入本地临时文件
      var localDeviceRootPath = config.getLocalDeviceRootPath();
      var localTempFile = [
        localDeviceRootPath,
        'temp_device_info.json',
      ].join('/');
      await FileUtils.createParentDir(localTempFile);
      await File(localTempFile).writeAsString(jsonStr);

      // 4. 上传到远程（一个设备一个文件）
      var remoteDeviceInfoPath = config.getRemoteDeviceInfoPath(
        config.deviceId,
      );
      await storage.uploadFile(remoteDeviceInfoPath, localTempFile);

      // 5. 删除临时文件
      if (await File(localTempFile).exists()) {
        await File(localTempFile).delete();
      }

      // 6. 更新本地缓存
      _deviceInfoCache[config.deviceId] = deviceInfo;
      await _saveDeviceInfoCache();

      return true;
    } catch (e) {
      print('上传设备信息失败: $e');
      return false;
    }
  }

  @override
  Future<List<WenzbakDeviceInfo>> queryDeviceInfo([String? deviceId]) async {
    try {
      var storage = WenzbakStorageClientService.getInstance(config);
      if (storage == null) {
        throw "未配置存储服务";
      }

      var remoteDeviceRootPath = config.getRemoteDeviceRootPath();
      var files = await storage.listFiles(remoteDeviceRootPath);
      Set<String> deviceIds = {};

      // 1. 获取所有设备ID
      for (var file in files) {
        var filePath = file.path;
        if (filePath != null) {
          var index = filePath.lastIndexOf("devices/");
          if (index != -1) {
            var endIndex = filePath.indexOf("/", index + 8);
            if (endIndex == -1) {
              continue;
            }
            deviceIds.add(filePath.substring(index + 8, endIndex));
          }
        }
      }

      // 2. 如果指定了 deviceId，只查询该设备
      if (deviceId != null) {
        deviceIds = {deviceId};
      }

      // 3. 查询每个设备的设备信息
      List<WenzbakDeviceInfo> deviceInfoList = [];
      for (var id in deviceIds) {
        try {
          var remoteDeviceInfoPath = config.getRemoteDeviceInfoPath(id);
          var deviceInfoBytes = await storage.readFile(remoteDeviceInfoPath);

          if (deviceInfoBytes != null) {
            var jsonStr = utf8.decode(deviceInfoBytes);
            var json = jsonDecode(jsonStr) as Map<String, dynamic>;
            var deviceInfo = WenzbakDeviceInfo.fromJson(json);
            deviceInfoList.add(deviceInfo);

            // 更新缓存
            _deviceInfoCache[id] = deviceInfo;
          }
        } catch (e) {
          print('查询设备信息失败: $id, 错误: $e');
        }
      }

      // 4. 保存缓存到本地
      await _saveDeviceInfoCache();

      return deviceInfoList;
    } catch (e) {
      print('查询设备信息失败: $e');
      return [];
    }
  }

  @override
  Future<WenzbakDeviceInfo> getDeviceSystemInfo() async {
    // 获取平台信息
    String? platform;
    String? osVersion;
    String? model;
    String? deviceName;

    try {
      // 使用 Platform 类获取平台信息
      if (Platform.isAndroid) {
        platform = 'android';
      } else if (Platform.isIOS) {
        platform = 'ios';
      } else if (Platform.isWindows) {
        platform = 'windows';
      } else if (Platform.isLinux) {
        platform = 'linux';
      } else if (Platform.isMacOS) {
        platform = 'macos';
      } else {
        platform = 'unknown';
      }

      // 获取操作系统版本
      osVersion = Platform.operatingSystemVersion;

      // 获取设备名称（使用环境变量或默认值）
      try {
        var env = Platform.environment;
        if (Platform.isWindows) {
          deviceName =
              env['COMPUTERNAME'] ?? env['USERNAME'] ?? 'Windows Device';
        } else if (Platform.isLinux || Platform.isMacOS) {
          deviceName = env['HOSTNAME'] ?? env['USER'] ?? 'Unix Device';
        } else {
          deviceName = 'Device';
        }
      } catch (e) {
        deviceName = 'Device';
      }

      // 对于移动平台，model 信息需要通过其他方式获取
      // 这里先使用 platform 作为 model
      model = platform;
    } catch (e) {
      print('获取设备信息失败: $e');
      platform = 'unknown';
      osVersion = 'unknown';
      model = 'unknown';
      deviceName = 'Device';
    }

    return WenzbakDeviceInfo(
      deviceId: config.deviceId,
      platform: platform,
      model: model,
      osVersion: osVersion,
      deviceName: deviceName,
      updateTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 加载设备信息缓存
  void _loadDeviceInfoCache() {
    var localDeviceInfoCacheFile = config.getLocalDeviceInfoCacheFile();
    if (File(localDeviceInfoCacheFile).existsSync()) {
      try {
        var content = File(localDeviceInfoCacheFile).readAsStringSync();
        var map = jsonDecode(content) as Map;
        for (var entry in map.entries) {
          var deviceId = entry.key as String;
          var deviceInfoJson = entry.value as Map<String, dynamic>;
          _deviceInfoCache[deviceId] = WenzbakDeviceInfo.fromJson(
            deviceInfoJson,
          );
        }
      } catch (e) {
        print('加载设备信息缓存失败: $e');
      }
    }
  }

  /// 保存设备信息缓存
  Future<void> _saveDeviceInfoCache() async {
    var localDeviceInfoCacheFile = config.getLocalDeviceInfoCacheFile();
    try {
      await FileUtils.createParentDir(localDeviceInfoCacheFile);
      var map = <String, Map<String, dynamic>>{};
      for (var entry in _deviceInfoCache.entries) {
        map[entry.key] = entry.value.toJson();
      }
      await File(localDeviceInfoCacheFile).writeAsString(jsonEncode(map));
    } catch (e) {
      print('保存设备信息缓存失败: $e');
    }
  }

  @override
  Future<List<String>> queryDeviceIdList() async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "未配置存储服务";
    }

    var remoteDeviceRootPath = config.getRemoteDeviceRootPath();
    var files = await storage.listFiles(remoteDeviceRootPath);
    Set<String> deviceIds = {};
    for (var file in files) {
      var filePath = file.path;
      if (filePath != null) {
        var index = filePath.lastIndexOf("devices/");
        if (index != -1) {
          var endIndex = filePath.indexOf("/", index + 8);
          if (endIndex == -1) {
            deviceIds.add(filePath.substring(index + 8));
            continue;
          }
          deviceIds.add(filePath.substring(index + 8, endIndex));
        }
      }
    }
    return deviceIds.toList();
  }
}
