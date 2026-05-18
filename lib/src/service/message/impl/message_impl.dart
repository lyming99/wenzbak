import 'dart:async';
import 'dart:math';

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
  Timer? _messageTimer;
  bool _isReadingMessage = false;

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
    if (_isReadingMessage) {
      config.logger.debug('消息读取正在进行中，跳过本次执行', tag: 'MessageService');
      return;
    }
    _isReadingMessage = true;
    try {
      await _downloadService.readMessage(_messageReceivers);
    } catch (e) {
      config.logger.error('消息读取失败: $e', tag: 'MessageService');
    } finally {
      _isReadingMessage = false;
    }
  }

  @override
  void startTimer() {
    stopTimer();
    var interval = max(5, config.messageInterval);
    _messageTimer = Timer.periodic(Duration(seconds: interval), (timer) {
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
