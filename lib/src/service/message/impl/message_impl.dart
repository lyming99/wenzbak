import 'dart:async';

import 'package:synchronized/synchronized.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/message.dart';
import 'package:wenzbak/src/service/message/message.dart';
import 'package:wenzbak/src/service/message/upload.dart';
import 'package:wenzbak/src/service/message/impl/upload_impl.dart';
import 'package:wenzbak/src/service/message/download.dart';
import 'package:wenzbak/src/service/message/impl/download_impl.dart';

class WenzbakMessageServiceImpl extends WenzbakMessageService {
  final WenzbakConfig config;
  late WenzbakMessageUploadService _uploadService;
  late WenzbakMessageDownloadService _downloadService;
  final Set<MessageReceiver> _messageReceivers = {};
  final Lock _messageReadLock = Lock();
  Timer? _messageTimer;

  WenzbakMessageServiceImpl(this.config) {
    _uploadService = WenzbakMessageUploadServiceImpl(config);
    _downloadService = WenzbakMessageDownloadServiceImpl(config);
    _uploadService.readCache().then((_) => _uploadService.executeUploadTask());
  }

  @override
  Future<void> sendMessage(WenzbakMessage message) async {
    await _uploadService.addMessage(message);
    await _uploadService.executeUploadTask();
  }

  @override
  Future<void> readMessage() async {
    await _messageReadLock.synchronized(() async {
      await _downloadService.readMessage(_messageReceivers);
    });
  }

  @override
  void startTimer() {
    stopTimer();
    _messageTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      readMessage();
    });
    readMessage();
  }

  @override
  void stopTimer() {
    _messageTimer?.cancel();
    _messageTimer = null;
  }

  @override
  void addMessageReceiver(MessageReceiver receiver) {
    _messageReceivers.add(receiver);
  }

  @override
  void removeMessageReceiver(MessageReceiver receiver) {
    _messageReceivers.remove(receiver);
  }
}
