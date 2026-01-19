class WenzbakDataBlock {
  int? id;
  String? serverId;
  String? uuid;
  bool? isCurrent;
  DateTime? createTime;
  DateTime? updateTime;
  String? filepath;
  int? size;
  String? md5;
  bool? isUploaded;
  bool? needUpload;
  int? uploadStatus;
  DateTime? uploadTime;

  WenzbakDataBlock({
    this.id,
    this.serverId,
    this.uuid,
    this.isCurrent,
    this.createTime,
    this.updateTime,
    this.filepath,
    this.size,
    this.md5,
    this.isUploaded,
    this.needUpload,
    this.uploadStatus,
    this.uploadTime,
  });

  factory WenzbakDataBlock.fromJson(Map<String, dynamic> json) {
    return WenzbakDataBlock(
      id: json['id'],
      serverId: json['serverId'],
      uuid: json['uuid'],
      isCurrent: json['isCurrent'],
      createTime: json['createTime'] == null
          ? null
          : DateTime.parse(json['createTime']),
      updateTime: json['updateTime'] == null
          ? null
          : DateTime.parse(json['updateTime']),
      filepath: json['filepath'],
      size: json['size'],
      md5: json['md5'],
      isUploaded: json['isUploaded'],
      needUpload: json['needUpload'],
      uploadStatus: json['uploadStatus'],
      uploadTime: json['uploadTime'] == null
          ? null
          : DateTime.parse(json['uploadTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serverId': serverId,
      'uuid': uuid,
      'isCurrent': isCurrent,
      'createTime': createTime?.toIso8601String(),
      'updateTime': updateTime?.toIso8601String(),
      'filepath': filepath,
      'size': size,
      'md5': md5,
      'isUploaded': isUploaded,
      'needUpload': needUpload,
      'uploadStatus': uploadStatus,
      'uploadTime': uploadTime?.toIso8601String(),
    };
  }
}
