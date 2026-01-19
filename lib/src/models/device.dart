/// 设备信息模型
class WenzbakDeviceInfo {
  /// 设备ID
  String deviceId;

  /// 平台（如：android, ios, windows, linux, macos, web）
  String? platform;

  /// 设备型号
  String? model;

  /// 操作系统版本
  String? osVersion;

  /// 设备名称
  String? deviceName;

  /// 更新时间戳
  int? updateTimestamp;

  WenzbakDeviceInfo({
    required this.deviceId,
    this.platform,
    this.model,
    this.osVersion,
    this.deviceName,
    this.updateTimestamp,
  });

  factory WenzbakDeviceInfo.fromJson(Map<String, dynamic> json) {
    return WenzbakDeviceInfo(
      deviceId: json['deviceId'] as String,
      platform: json['platform'] as String?,
      model: json['model'] as String?,
      osVersion: json['osVersion'] as String?,
      deviceName: json['deviceName'] as String?,
      updateTimestamp: json['updateTimestamp'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'platform': platform,
      'model': model,
      'osVersion': osVersion,
      'deviceName': deviceName,
      'updateTimestamp': updateTimestamp,
    };
  }
}
