enum ServerType { s3, ftp, webdav, custom }

class WenzbakServer {
  int? id;
  String? uuid;
  String? serverName;
  ServerType? serverType;
  String? serverInfo;
  String? secretHash;
  String? secret;
  String? rootPath;
  bool? isEncryptData;
  bool? isEncryptFile;
  bool? isPrimaryServer;

  WenzbakServer({
    this.id,
    this.uuid,
    this.serverName,
    this.serverType,
    this.serverInfo,
    this.secretHash,
    this.secret,
    this.rootPath,
    this.isEncryptData,
    this.isEncryptFile,
    this.isPrimaryServer,
  });

  factory WenzbakServer.fromJson(Map<String, dynamic> json) {
    return WenzbakServer(
      id: json['id'],
      uuid: json['uuid'],
      serverName: json['serverName'],
      serverType: ServerType.values.firstWhere(
        (element) => element.toString() == json['serverType'],
      ),
      serverInfo: json['serverInfo'],
      secretHash: json['secretHash'],
      secret: json['secret'],
      rootPath: json['rootPath'],
      isEncryptData: json['isEncryptData'],
      isEncryptFile: json['isEncryptFile'],
      isPrimaryServer: json['isPrimaryServer'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'serverName': serverName,
      'serverType': serverType.toString(),
      'serverInfo': serverInfo,
      'secretHash': secretHash,
      'secret': secret,
      'rootPath': rootPath,
      'isEncryptData': isEncryptData,
      'isEncryptFile': isEncryptFile,
      'isPrimaryServer': isPrimaryServer,
    };
  }
}
