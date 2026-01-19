/// 上传任务状态枚举
enum WenzbakUploadTaskStatus {
  /// 等待上传
  waiting,

  /// 上传中
  uploading,

  /// 上传成功
  success,

  /// 上传失败
  failed,
}

class WenzbakUploadTaskInfo {
  String? serverId;
  String? localPath;
  String? serverPath;

  WenzbakUploadTaskInfo({this.serverId, this.localPath, this.serverPath});

  factory WenzbakUploadTaskInfo.fromJson(Map<String, dynamic> json) {
    return WenzbakUploadTaskInfo(
      serverId: json['serverId'] as String?,
      localPath: json['localPath'] as String?,
      serverPath: json['serverPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverId': serverId,
      'localPath': localPath,
      'serverPath': serverPath,
    };
  }
}

/// 上传任务模型
/// 用于管理文件或数据块的上传任务
class WenzbakUploadTask {
  /// 任务ID（数据库主键）
  int? id;

  /// 任务UUID（唯一标识符）
  String? uuid;

  /// 任务类型（如：block、file等）
  String? type;

  /// 任务信息（JSON字符串，包含文件路径、服务器ID等）
  String? info;

  /// 任务状态
  WenzbakUploadTaskStatus? status;

  /// 创建时间
  DateTime? createTime;

  /// 更新时间
  DateTime? updateTime;

  /// 构造函数
  WenzbakUploadTask({
    this.id,
    this.uuid,
    this.type,
    this.info,
    this.status,
    this.createTime,
    this.updateTime,
  });

  /// 从JSON创建对象
  factory WenzbakUploadTask.fromJson(Map<String, dynamic> json) {
    return WenzbakUploadTask(
      id: json['id'] as int?,
      uuid: json['uuid'] as String?,
      type: json['type'] as String?,
      info: json['info'] as String?,
      status: json['status'] == null
          ? null
          : _statusFromString(json['status'] as String),
      createTime: json['createTime'] == null
          ? null
          : DateTime.parse(json['createTime'] as String),
      updateTime: json['updateTime'] == null
          ? null
          : DateTime.parse(json['updateTime'] as String),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'type': type,
      'info': info,
      'status': status == null ? null : _statusToString(status!),
      'createTime': createTime?.toIso8601String(),
      'updateTime': updateTime?.toIso8601String(),
    };
  }

  /// 将状态枚举转换为字符串
  static String _statusToString(WenzbakUploadTaskStatus status) {
    switch (status) {
      case WenzbakUploadTaskStatus.waiting:
        return 'waiting';
      case WenzbakUploadTaskStatus.uploading:
        return 'uploading';
      case WenzbakUploadTaskStatus.success:
        return 'success';
      case WenzbakUploadTaskStatus.failed:
        return 'failed';
    }
  }

  /// 从字符串创建状态枚举
  static WenzbakUploadTaskStatus _statusFromString(String status) {
    switch (status.toLowerCase()) {
      case 'waiting':
        return WenzbakUploadTaskStatus.waiting;
      case 'uploading':
        return WenzbakUploadTaskStatus.uploading;
      case 'success':
        return WenzbakUploadTaskStatus.success;
      case 'failed':
        return WenzbakUploadTaskStatus.failed;
      default:
        throw ArgumentError('Unknown status: $status');
    }
  }

  /// 检查任务是否已完成（成功或失败）
  bool get isCompleted {
    return status == WenzbakUploadTaskStatus.success ||
        status == WenzbakUploadTaskStatus.failed;
  }

  /// 检查任务是否正在处理中
  bool get isProcessing {
    return status == WenzbakUploadTaskStatus.uploading;
  }

  /// 检查任务是否等待处理
  bool get isWaiting {
    return status == WenzbakUploadTaskStatus.waiting;
  }

  /// 检查任务是否成功
  bool get isSuccess {
    return status == WenzbakUploadTaskStatus.success;
  }

  /// 检查任务是否失败
  bool get isFailed {
    return status == WenzbakUploadTaskStatus.failed;
  }

  /// 更新任务状态
  void updateStatus(WenzbakUploadTaskStatus newStatus) {
    status = newStatus;
    updateTime = DateTime.now();
  }

  /// 标记任务为成功
  void markSuccess() {
    updateStatus(WenzbakUploadTaskStatus.success);
  }

  /// 标记任务为失败
  void markFailed() {
    updateStatus(WenzbakUploadTaskStatus.failed);
  }

  /// 标记任务为上传中
  void markUploading() {
    updateStatus(WenzbakUploadTaskStatus.uploading);
  }

  @override
  String toString() {
    return 'WenzbakUploadTask{id: $id, uuid: $uuid, type: $type, '
        'status: $status, createTime: $createTime, updateTime: $updateTime}';
  }
}
