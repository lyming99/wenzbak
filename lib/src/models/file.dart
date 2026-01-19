class WenzbakFile {
  int? id;
  int? userId;
  String? uuid;
  String? serverId;
  int? length;
  String? localPath;
  String? remotePath;
  bool? isUploaded;
  bool? needUpload;
  int? uploadStatus;
  DateTime? uploadTime;
  DateTime? createTime;
  DateTime? updateTime;
}

class WenzbakStorageFile {
  String? path;
  bool? isDir;

  WenzbakStorageFile({this.path, this.isDir});

  factory WenzbakStorageFile.fromJson(Map<String, dynamic> json) {
    return WenzbakStorageFile(path: json['path'], isDir: json['isDir']);
  }

  Map<String, dynamic> toJson() {
    return {'path': path, 'isDir': isDir};
  }

  WenzbakStorageBlockFile? toStorageBlockFile() {
    var path = this.path;
    if (path == null) {
      return null;
    }
    path = path.replaceAll("\\", "/");
    if (path.endsWith('.sha256')) {
      var name = path.split("/").last;
      var index = name.indexOf(".");
      if (index > 0) {
        var uuid = name.substring(0, index);
        return WenzbakStorageBlockFile(
          uuid: uuid,
          gzipPath: path.replaceAll(".sha256", ""),
          sha256Path: path,
        );
      }
    }
    return null;
  }
}

class WenzbakStorageBlockFile {
  String uuid;
  String gzipPath;
  String sha256Path;

  WenzbakStorageBlockFile({required this.uuid,required  this.gzipPath,required  this.sha256Path});
}
