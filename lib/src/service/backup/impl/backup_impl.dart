import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/line.dart';
import 'package:wenzbak/src/service/data/block_data.dart';
import 'package:wenzbak/src/service/data/impl/block_data_impl.dart';
import 'package:wenzbak/src/service/file/file.dart';
import 'package:wenzbak/src/service/message/message.dart';
import 'package:wenzbak/wenzbak.dart';

import '../../../models/index.dart';
import '../../device/device.dart';
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

  WenzbakClientServiceImpl(this.config) {
    dataService = WenzbakBlockDataServiceImpl(config);
    fileService = WenzbakFileServiceImpl(config);
    messageService = WenzbakMessageServiceImpl(config);
    deviceService = WenzbakDeviceServiceImpl(config);
  }

  @override
  void addMessageReceiver(MessageReceiver receiver) {
    messageService.addMessageReceiver(receiver);
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
  Future<void> addBackupData(WenzbakDataLine line) async {
    await dataService.addBackupData(line);
  }

  @override
  Future<String?> uploadAssets(String localPath) async {
    return await fileService.uploadFile(localPath);
  }

  @override
  Future<String?> uploadTempAssets(String localPath) async {
    return await fileService.uploadTempFile(localPath);
  }

  @override
  void addDataReceiver(WenzbakDataReceiver receiver) {
    dataReceivers.add(receiver);
  }

  @override
  Future<void> downloadAllData() async {
    await dataService.downloadAllData(dataReceivers);
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
    await dataService.uploadBlockData(oneHoursAgo);
  }

  @override
  Future<void> mergeHistoryData() async {
    await dataService.mergeBlockData();
  }

  @override
  Future<void> uploadDeviceInfo([WenzbakDeviceInfo? deviceInfo]) async{
    await deviceService.uploadDeviceInfo();
  }
}
