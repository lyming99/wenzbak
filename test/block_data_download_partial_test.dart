import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/backup/impl/backup_impl.dart';
import 'package:wenzbak/src/service/data/impl/block_data_impl.dart';
import 'package:wenzbak/src/utils/gzip_util.dart';
import 'package:wenzbak/wenzbak.dart';

const _indexPath = 'remote/public/indexes/data/device-a';
const _goodPath = 'remote/public/data/good.gz';
const _failedPath = 'remote/public/data/failed.gz';

void main() {
  late _IndexStorage storage;
  late WenzbakConfig config;
  late _ControlledBlockDataService service;

  setUp(() {
    storage = _IndexStorage();
    config = WenzbakConfig(
      deviceId: 'partial-download-device',
      localRootPath: 'local',
      remoteRootPath: 'remote',
      storage: storage,
    );
    service = _ControlledBlockDataService(config);
  });

  test('continues the round and reports every failed block', () async {
    SyncPartialException? partialException;

    try {
      await service.downloadAllData(<WenzbakDataReceiver>{});
    } on SyncPartialException catch (error) {
      partialException = error;
    }

    expect(partialException, isNotNull);
    expect(partialException!.total, 2);
    expect(partialException.failed, 1);
    expect(partialException.succeeded, 1);
    expect(partialException.failures.single.path, _failedPath);
    expect(partialException.failures.single.sha256, 'failed-sha');
    expect(service.attempts, <String>[_goodPath, _failedPath]);

    service.failFailedPath = false;
    service.attempts.clear();

    await service.downloadAllData(<WenzbakDataReceiver>{});

    expect(
      service.attempts,
      <String>[_failedPath, _goodPath],
      reason: 'the block that failed in the previous round is retried first',
    );
  });

  test('client wrapper preserves partial download failures', () async {
    final client = WenzbakClientServiceImpl(config)..dataService = service;

    await expectLater(
      client.downloadAllData(),
      throwsA(
        isA<SyncPartialException>()
            .having((error) => error.failed, 'failed', 1)
            .having((error) => error.total, 'total', 2),
      ),
    );

    service.failFailedPath = false;
    await expectLater(client.downloadAllData(), completes);
  });
}

class _ControlledBlockDataService extends WenzbakBlockDataServiceImpl {
  _ControlledBlockDataService(super.config);

  bool failFailedPath = true;
  final List<String> attempts = <String>[];

  @override
  Future<void> downloadData(
    String remotePath,
    String? sha256,
    Set<WenzbakDataReceiver> dataReceivers, {
    bool reload = false,
  }) async {
    attempts.add(remotePath);
    if (remotePath == _failedPath && failFailedPath) {
      throw StateError('injected block download failure');
    }
  }
}

class _IndexStorage extends WenzbakStorageClientService {
  _IndexStorage()
    : _indexBytes = GZipUtil.compressBytes(
        Uint8List.fromList(
          utf8.encode('good-sha $_goodPath\nfailed-sha $_failedPath\n'),
        ),
      );

  final Uint8List _indexBytes;

  Never _unsupported() => throw UnsupportedError('not used by this test');

  @override
  bool get isRangeSupport => false;

  @override
  Future<List<WenzbakStorageFile>> listFiles(String path) async =>
      <WenzbakStorageFile>[WenzbakStorageFile(path: _indexPath, isDir: false)];

  @override
  Future<Uint8List?> readFile(String path) async =>
      path == _indexPath ? _indexBytes : null;

  @override
  Future<void> createFolder(String path) async => _unsupported();

  @override
  Future<void> deleteFile(String path) async => _unsupported();

  @override
  Future<void> deleteFolder(String path) async => _unsupported();

  @override
  Future<void> downloadFile(String path, String localFilepath) async =>
      _unsupported();

  @override
  Future<Uint8List> readRange(String path, int start, int length) async =>
      _unsupported();

  @override
  Future<int> readFileSize(String path) async => _unsupported();

  @override
  Future<void> uploadFile(String path, String localFilepath) async =>
      _unsupported();

  @override
  Future<void> writeFile(String path, Uint8List data) async => _unsupported();

  @override
  Future<void> writeRange(String path, int start, Uint8List data) async =>
      _unsupported();
}
