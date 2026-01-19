import 'dart:math';
import 'dart:typed_data';

class WenzbakMessage {
  String? uuid;
  String? content;
  int? timestamp;

  WenzbakMessage({this.uuid, this.content, this.timestamp});

  WenzbakMessage.fromJson(Map<String, dynamic> json) {
    uuid = json['uuid'];
    content = json['content'];
    timestamp = json['timestamp'];
  }

  Map<String, dynamic> toJson() {
    return {'uuid': uuid, 'content': content, 'timestamp': timestamp};
  }
}

class WenzbakMessageLock {
  // 心跳时间（64位）
  int? timestamp;

  // 最后一次收到消息的时间（64位）
  int? msgTimestamp;

  WenzbakMessageLock({this.timestamp, this.msgTimestamp});

  void updateTime(int msgTimestamp) {
    var temp = this.msgTimestamp ?? msgTimestamp;
    this.msgTimestamp = max(temp, msgTimestamp);
    timestamp = DateTime.now().millisecondsSinceEpoch;
  }

  /// 将对象序列化为字节数组
  /// 格式：timestamp(8字节) + msgTimestamp(8字节) + previousMsgFileCount(4字节) + currentMsgFileCount(4字节)
  Uint8List toBytes() {
    final byteData = ByteData(16);
    int offset = 0;

    // 写入 timestamp (64位，8字节)
    if (timestamp != null) {
      byteData.setInt64(offset, timestamp!, Endian.big);
    }
    offset += 8;

    // 写入 msgTimestamp (64位，8字节)
    if (msgTimestamp != null) {
      byteData.setInt64(offset, msgTimestamp!, Endian.big);
    }
    offset += 8;
    return byteData.buffer.asUint8List();
  }

  /// 从字节数组反序列化为对象
  /// 格式：timestamp(8字节) + msgTimestamp(8字节)
  static WenzbakMessageLock fromBytes(Uint8List bytes) {
    if (bytes.length < 16) {
      throw ArgumentError('字节数组长度不足，需要至少24字节，实际为${bytes.length}字节');
    }

    final byteData = ByteData.sublistView(bytes);
    int offset = 0;

    // 读取 timestamp (64位，8字节)
    final timestamp = byteData.getInt64(offset, Endian.big);
    offset += 8;

    // 读取 msgTimestamp (64位，8字节)
    final msgTimestamp = byteData.getInt64(offset, Endian.big);

    return WenzbakMessageLock(timestamp: timestamp, msgTimestamp: msgTimestamp);
  }
}
