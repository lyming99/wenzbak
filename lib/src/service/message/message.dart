import 'package:wenzbak/src/models/index.dart';

typedef MessageReceiver = Future Function(WenzbakMessage message);

abstract class WenzbakMessageService {
  Future<void> sendMessage(WenzbakMessage message);

  Future<void> readMessage();

  void addMessageReceiver(MessageReceiver receiver);

  void removeMessageReceiver(MessageReceiver receiver);

  void startTimer();

  void stopTimer();
}
