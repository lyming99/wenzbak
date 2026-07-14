import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/data/impl/block_data_impl.dart';
import 'package:wenzbak/wenzbak.dart';

import '../../device/impl/device_impl.dart';
import '../../file/impl/file_impl.dart';
import '../../message/impl/message_impl.dart';

class WenzbakClientServiceImpl extends WenzbakClientService {
  Set<WenzbakDataReceiver> dataReceivers = {};
  WenzbakConfig config;
  late WenzbakBlockDataService dataService;
  late WenzbakFileService fileService;
  late WenzbakMessageService messageService;
  late WenzbakDeviceService deviceService;

  bool _isUploading = false;
  bool _isDownloading = false;
  bool _isMerging = false;

  WenzbakClientServiceImpl(this.config) {
    dataService = WenzbakBlockDataServiceImpl(config);
    fileService = WenzbakFileServiceImpl(config);
    messageService = WenzbakMessageServiceImpl(config);
    deviceService = WenzbakDeviceServiceImpl(config);
  }

  @override
  bool get isSecretClient =>
      config.secretKey != null && config.secretKey!.isNotEmpty;

  @override
  void addMessageReceiver(MessageReceiver receiver) {
    messageService.addMessageReceiver(receiver);
  }

  @override
  void removeMessageReceiver(MessageReceiver receiver) {
    messageService.removeMessageReceiver(receiver);
  }

  @override
  Future<void> sendMessage(WenzbakMessage message) async {
    await messageService.sendMessage(message);
  }

  @override
  Future<void> readMessage() async {
    await messageService.readMessage();
  }

  @override
  void startMessageTimer() {
    messageService.startTimer();
  }

  @override
  void stopMessageTimer() {
    messageService.stopTimer();
  }

  @override
  void setMessageTimerInterval(int interval) {
    config = config.copyWith(messageInterval: interval);
    messageService.startTimer();
  }

  @override
  Future<void> addBackupData(WenzbakDataLine line) async {
    await dataService.addBackupData(line);
  }

  @override
  Future<void> addBackupDataList(List<WenzbakDataLine> lines) async {
    await dataService.addBackupDataList(lines);
  }

  @override
  Future<String?> uploadAssets(String localPath) async {
    return await fileService.uploadFile(localPath);
  }

  @override
  String? getRemoteAssetsPath(String localPath) {
    return fileService.getAssetsPath(localPath);
  }

  @override
  Future<String?> uploadTempAssets(String localPath) async {
    return await fileService.uploadTempFile(localPath);
  }

  @override
  String? getRemoteTempAssetsPath(String localPath) {
    return fileService.getTempAssetsPath(localPath);
  }

  @override
  void addDataReceiver(WenzbakDataReceiver receiver) {
    dataReceivers.add(receiver);
  }

  @override
  Future<void> downloadAllData() async {
    if (_isDownloading) {
      config.logger.debug('数据下载正在进行中，跳过本次执行', tag: 'BackupService');
      return;
    }
    _isDownloading = true;
    try {
      await dataService.downloadAllData(dataReceivers);
    } catch (e, stackTrace) {
      config.logger.error(
        '数据下载失败: $e',
        error: e,
        stackTrace: stackTrace,
        tag: 'BackupService',
      );
      rethrow;
    } finally {
      _isDownloading = false;
    }
  }

  @override
  Future<void> reloadAllData() async {
    if (_isDownloading) {
      config.logger.debug('数据下载正在进行中，跳过本次执行', tag: 'BackupService');
      return;
    }
    _isDownloading = true;
    try {
      await dataService.reloadAllData(dataReceivers);
    } catch (e, stackTrace) {
      config.logger.error(
        '数据重新加载失败: $e',
        error: e,
        stackTrace: stackTrace,
        tag: 'BackupService',
      );
      rethrow;
    } finally {
      _isDownloading = false;
    }
  }

  @override
  Future<void> downloadData(String remotePath) async {
    await dataService.downloadData(remotePath, null, dataReceivers);
  }

  @override
  Future<String?> downloadFile(String remotePath) async {
    return fileService.downloadFile(remotePath);
  }

  @override
  void removeDataReceiver(WenzbakDataReceiver receiver) {
    dataReceivers.remove(receiver);
  }

  @override
  Future uploadAllData(bool oneHoursAgo) async {
    if (_isUploading) {
      config.logger.debug('数据上传正在进行中，跳过本次执行', tag: 'BackupService');
      return;
    }
    _isUploading = true;
    try {
      await dataService.uploadBlockData(oneHoursAgo);
    } catch (e) {
      config.logger.error('数据上传失败: $e', tag: 'BackupService');
    } finally {
      _isUploading = false;
    }
  }

  @override
  Future<void> mergeHistoryData() async {
    if (_isMerging) {
      config.logger.debug('数据合并正在进行中，跳过本次执行', tag: 'BackupService');
      return;
    }
    _isMerging = true;
    try {
      await dataService.mergeBlockData();
    } catch (e) {
      config.logger.error('数据合并失败: $e', tag: 'BackupService');
    } finally {
      _isMerging = false;
    }
  }

  @override
  Future<void> uploadDeviceInfo([WenzbakDeviceInfo? deviceInfo]) async {
    await deviceService.uploadDeviceInfo();
  }
}
