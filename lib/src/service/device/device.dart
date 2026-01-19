import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/device.dart';
import 'package:wenzbak/src/service/device/impl/device_impl.dart';

/// 设备服务抽象类
/// 负责设备信息的上传和查询功能
abstract class WenzbakDeviceService {
  static WenzbakDeviceService getInstance(WenzbakConfig config) {
    return WenzbakDeviceServiceImpl(config);
  }

  /// 上传设备信息（只上传自身设备信息）
  /// [deviceInfo] 可选的设备信息，如果为 null 则自动获取当前设备信息
  /// 返回是否上传成功
  Future<bool> uploadDeviceInfo([WenzbakDeviceInfo? deviceInfo]);

  /// 查询设备信息
  /// [deviceId] 设备ID，如果为 null 则查询所有设备
  /// 返回设备信息列表，查询后缓存到本地 device_info.json
  Future<List<WenzbakDeviceInfo>> queryDeviceInfo([String? deviceId]);

  /// 获取当前设备信息
  /// 返回当前设备的设备信息
  Future<WenzbakDeviceInfo> getDeviceSystemInfo();

  Future<List<String>> queryDeviceIdList();
}
