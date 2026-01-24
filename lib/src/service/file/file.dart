abstract class WenzbakFileService {
  Future<String?> downloadFile(String remotePath);

  Future<String?> uploadFile(String localPath);

  Future<String?> uploadTempFile(String localPath);

  Future<void> deleteTempFile();

  String? getAssetsPath(String localPath);

  String? getTempAssetsPath(String localPath);
}
