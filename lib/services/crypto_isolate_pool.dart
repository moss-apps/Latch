import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

const int _kPoolSize = 2;
const int _kChunkSize = 1024 * 1024;

class CryptoIsolatePool {
  final List<_PoolWorker> _workers = [];
  final Map<int, _ActiveJob> _activeJobs = {};
  final List<_PendingJob> _queue = [];
  int _nextJobId = 0;
  bool _initialized = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    for (int i = 0; i < _kPoolSize; i++) {
      final worker = await _PoolWorker.spawn();
      _attachExitListener(worker);
      _workers.add(worker);
    }
    _initialized = true;
  }

  CryptoJob<PoolEncryptResult> encryptFile({
    required String sourcePath,
    required String destinationPath,
    required Uint8List key,
    bool useGcm = true,
    Function(int bytesProcessed, int totalBytes)? onProgress,
  }) {
    _ensureInitialized();
    final jobId = _nextJobId++;
    final completer = Completer<PoolEncryptResult>();
    final replyPort = ReceivePort();

    final job = _ActiveJob(
      id: jobId,
      replyPort: replyPort,
      completer: completer,
      onProgress: onProgress,
    );
    _activeJobs[jobId] = job;

    final pending = _PendingJob(
      id: jobId,
      type: 'encrypt',
      replyPort: replyPort,
      params: {
        'sourcePath': sourcePath,
        'destinationPath': destinationPath,
        'keyBase64': base64Encode(key),
        'useGcm': useGcm,
      },
    );

    _enqueueOrDispatch(pending);

    return CryptoJob(
      id: jobId,
      future: completer.future,
      cancel: () => cancelJob(jobId),
    );
  }

  CryptoJob<PoolDecryptResult> decryptFile({
    required String encryptedPath,
    required String destinationPath,
    required Uint8List key,
    required String ivBase64,
    Function(int bytesProcessed, int totalBytes)? onProgress,
  }) {
    _ensureInitialized();
    final jobId = _nextJobId++;
    final completer = Completer<PoolDecryptResult>();
    final replyPort = ReceivePort();

    final job = _ActiveJob(
      id: jobId,
      replyPort: replyPort,
      completer: completer,
      onProgress: onProgress,
    );
    _activeJobs[jobId] = job;

    final pending = _PendingJob(
      id: jobId,
      type: 'decrypt',
      replyPort: replyPort,
      params: {
        'encryptedPath': encryptedPath,
        'destinationPath': destinationPath,
        'keyBase64': base64Encode(key),
        'ivBase64': ivBase64,
      },
    );

    _enqueueOrDispatch(pending);

    return CryptoJob(
      id: jobId,
      future: completer.future,
      cancel: () => cancelJob(jobId),
    );
  }

  Future<void> cancelJob(int jobId) async {
    final queuedIdx = _queue.indexWhere((j) => j.id == jobId);
    if (queuedIdx >= 0) {
      final pending = _queue.removeAt(queuedIdx);
      final job = _activeJobs.remove(jobId);
      pending.replyPort.close();
      job?.replyPort.close();
      if (job != null && !job.completer.isCompleted) {
        job.completer.completeError('Cancelled');
      }
      return;
    }

    for (int i = 0; i < _workers.length; i++) {
      final worker = _workers[i];
      if (worker.currentJobId == jobId) {
        final job = _activeJobs.remove(jobId);
        job?.replyPort.close();
        if (job != null && !job.completer.isCompleted) {
          job.completer.completeError('Cancelled');
        }
        worker.isolate.kill(priority: Isolate.immediate);
        worker.initPort.close();
        worker.exitPort?.close();
        final newWorker = await _PoolWorker.spawn();
        _attachExitListener(newWorker);
        _workers[i] = newWorker;
        _dispatchNext();
        return;
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final pending in _queue) {
      pending.replyPort.close();
      final job = _activeJobs.remove(pending.id);
      job?.replyPort.close();
      if (job != null && !job.completer.isCompleted) {
        job.completer.completeError('Pool disposed');
      }
    }
    _queue.clear();

    for (final worker in _workers) {
      worker.isolate.kill(priority: Isolate.immediate);
      worker.initPort.close();
      worker.exitPort?.close();
    }
    _workers.clear();

    for (final job in _activeJobs.values) {
      job.replyPort.close();
      if (!job.completer.isCompleted) {
        job.completer.completeError('Pool disposed');
      }
    }
    _activeJobs.clear();
  }

  void _ensureInitialized() {
    if (_disposed) throw StateError('CryptoIsolatePool is disposed');
    if (!_initialized) throw StateError('CryptoIsolatePool not initialized — call initialize() first');
  }

  void _enqueueOrDispatch(_PendingJob pending) {
    final worker = _findIdleWorker();
    if (worker != null) {
      _dispatch(worker, pending);
    } else {
      _queue.add(pending);
    }
  }

  _PoolWorker? _findIdleWorker() {
    for (final w in _workers) {
      if (!w.busy) return w;
    }
    return null;
  }

  void _dispatch(_PoolWorker worker, _PendingJob pending) {
    worker.busy = true;
    worker.currentJobId = pending.id;

    final job = _activeJobs[pending.id]!;
    pending.replyPort.listen((message) {
      if (message is Map<String, dynamic>) {
        _handleMessage(worker, job, message);
      }
    });

    worker.cmdPort.send({
      ...pending.params,
      'type': pending.type,
      'jobId': pending.id,
      'replyPort': pending.replyPort.sendPort,
    });
  }

  void _handleMessage(_PoolWorker worker, _ActiveJob job, Map<String, dynamic> msg) {
    switch (msg['type'] as String) {
      case 'progress':
        job.onProgress?.call(msg['bytesProcessed'] as int, msg['totalBytes'] as int);
        break;

      case 'encrypt_complete':
        _finishJob(worker, job);
        (job.completer as Completer<PoolEncryptResult>).complete(PoolEncryptResult(
          success: true,
          ivBase64: msg['ivBase64'] as String,
          originalSize: msg['originalSize'] as int,
          encryptedSize: msg['encryptedSize'] as int,
        ));
        _dispatchNext();
        break;

      case 'decrypt_complete':
        _finishJob(worker, job);
        (job.completer as Completer<PoolDecryptResult>).complete(PoolDecryptResult(
          success: true,
          decryptedSize: msg['decryptedSize'] as int,
          needsMigration: msg['needsMigration'] as bool,
        ));
        _dispatchNext();
        break;

      case 'error':
        _finishJob(worker, job);
        job.completer.completeError(msg['error'] as String);
        _dispatchNext();
        break;
    }
  }

  void _finishJob(_PoolWorker worker, _ActiveJob job) {
    job.replyPort.close();
    _activeJobs.remove(job.id);
    worker.busy = false;
    worker.currentJobId = null;
  }

  void _dispatchNext() {
    if (_queue.isEmpty || _disposed) return;
    final worker = _findIdleWorker();
    if (worker == null) return;
    final pending = _queue.removeAt(0);
    _dispatch(worker, pending);
  }

  void _attachExitListener(_PoolWorker worker) {
    worker.exitPort = ReceivePort();
    worker.isolate.addOnExitListener(worker.exitPort!.sendPort);
    worker.exitPort!.listen((_) {
      if (_disposed) return;
      final jobId = worker.currentJobId;
      if (jobId != null) {
        final job = _activeJobs.remove(jobId);
        if (job != null) {
          job.replyPort.close();
          if (!job.completer.isCompleted) {
            job.completer.completeError('Worker isolate crashed');
          }
        }
      }
      worker.busy = false;
      worker.currentJobId = null;
      final idx = _workers.indexOf(worker);
      if (idx >= 0) {
        _PoolWorker.spawn().then((newWorker) {
          _attachExitListener(newWorker);
          _workers[idx] = newWorker;
          _dispatchNext();
        });
      }
    });
  }
}

class CryptoJob<T> {
  final int id;
  final Future<T> future;
  final void Function() cancel;

  const CryptoJob({
    required this.id,
    required this.future,
    required this.cancel,
  });
}

class PoolEncryptResult {
  final bool success;
  final String? ivBase64;
  final int? originalSize;
  final int? encryptedSize;
  final String? error;

  const PoolEncryptResult({
    required this.success,
    this.ivBase64,
    this.originalSize,
    this.encryptedSize,
    this.error,
  });
}

class PoolDecryptResult {
  final bool success;
  final int? decryptedSize;
  final bool needsMigration;
  final String? error;

  const PoolDecryptResult({
    required this.success,
    this.decryptedSize,
    this.needsMigration = false,
    this.error,
  });
}

class _PoolWorker {
  final Isolate isolate;
  final SendPort cmdPort;
  final ReceivePort initPort;
  ReceivePort? exitPort;
  bool busy = false;
  int? currentJobId;

  _PoolWorker({
    required this.isolate,
    required this.cmdPort,
    required this.initPort,
  });

  static Future<_PoolWorker> spawn() async {
    final initPort = ReceivePort();
    final isolate = await Isolate.spawn(_cryptoWorkerEntry, initPort.sendPort);
    final cmdPort = await initPort.first as SendPort;
    return _PoolWorker(
      isolate: isolate,
      cmdPort: cmdPort,
      initPort: initPort,
    );
  }
}

class _ActiveJob {
  final int id;
  final ReceivePort replyPort;
  final Completer completer;
  final Function(int, int)? onProgress;

  _ActiveJob({
    required this.id,
    required this.replyPort,
    required this.completer,
    this.onProgress,
  });
}

class _PendingJob {
  final int id;
  final String type;
  final ReceivePort replyPort;
  final Map<String, dynamic> params;

  _PendingJob({
    required this.id,
    required this.type,
    required this.replyPort,
    required this.params,
  });
}

// ---------------------------------------------------------------------------
// Worker isolate entry point and handlers (top-level functions)
// ---------------------------------------------------------------------------

void _cryptoWorkerEntry(SendPort initPort) {
  final cmdPort = ReceivePort();
  initPort.send(cmdPort.sendPort);

  cmdPort.listen((message) {
    if (message is Map<String, dynamic>) {
      _processWorkerJob(message);
    }
  });
}

void _processWorkerJob(Map<String, dynamic> message) async {
  final type = message['type'] as String;
  final replyPort = message['replyPort'] as SendPort;
  final jobId = message['jobId'] as int;

  try {
    switch (type) {
      case 'encrypt':
        await _workerDoEncrypt(message, replyPort, jobId);
        break;
      case 'decrypt':
        await _workerDoDecrypt(message, replyPort, jobId);
        break;
    }
  } catch (e) {
    replyPort.send({'type': 'error', 'jobId': jobId, 'error': e.toString()});
  }
}

Future<void> _workerDoEncrypt(
    Map<String, dynamic> params, SendPort replyPort, int jobId) async {
  final sourcePath = params['sourcePath'] as String;
  final destPath = params['destinationPath'] as String;
  final key = base64Decode(params['keyBase64'] as String);
  final useGcm = params['useGcm'] as bool;

  final sourceFile = File(sourcePath);
  final totalBytes = sourceFile.lengthSync();

  final random = Random.secure();
  final iv = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)));

  final tempPath = '$destPath.tmp';
  final tempFile = File(tempPath);
  final sink = tempFile.openWrite();

  try {
    if (useGcm) {
      final gcm = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

      final header = Uint8List(9);
      header[0] = 0x4C;
      header[1] = 0x4B;
      header[2] = 0x52;
      header[3] = 0x32;
      header[4] = 0x02;
      header[5] = (totalBytes & 0xFF);
      header[6] = ((totalBytes >> 8) & 0xFF);
      header[7] = ((totalBytes >> 16) & 0xFF);
      header[8] = ((totalBytes >> 24) & 0xFF);
      sink.add(header);

      final outBuf = Uint8List(_kChunkSize + 16);
      int bytesProcessed = 0;

      final raf = sourceFile.openSync();
      try {
        while (true) {
          final chunk = raf.readSync(_kChunkSize);
          if (chunk.isEmpty) break;
          final outLen = gcm.processBytes(chunk, 0, chunk.length, outBuf, 0);
          if (outLen > 0) {
            sink.add(Uint8List.view(outBuf.buffer, 0, outLen));
          }
          bytesProcessed += chunk.length;
          replyPort.send({
            'type': 'progress',
            'jobId': jobId,
            'bytesProcessed': bytesProcessed,
            'totalBytes': totalBytes,
          });
        }
      } finally {
        raf.closeSync();
      }

      final finalBuf = Uint8List(32);
      final finalLen = gcm.doFinal(finalBuf, 0);
      if (finalLen > 0) {
        sink.add(Uint8List.view(finalBuf.buffer, 0, finalLen));
      }
    } else {
      final ctr = CTRStreamCipher(AESEngine())
        ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));

      final header = Uint8List(8);
      header[0] = 0x4C;
      header[1] = 0x4B;
      header[2] = 0x52;
      header[3] = 0x53;
      header[4] = (totalBytes & 0xFF);
      header[5] = ((totalBytes >> 8) & 0xFF);
      header[6] = ((totalBytes >> 16) & 0xFF);
      header[7] = ((totalBytes >> 24) & 0xFF);
      sink.add(header);

      int bytesProcessed = 0;
      final raf = sourceFile.openSync();
      try {
        while (true) {
          final chunk = raf.readSync(_kChunkSize);
          if (chunk.isEmpty) break;
          sink.add(ctr.process(chunk));
          bytesProcessed += chunk.length;
          replyPort.send({
            'type': 'progress',
            'jobId': jobId,
            'bytesProcessed': bytesProcessed,
            'totalBytes': totalBytes,
          });
        }
      } finally {
        raf.closeSync();
      }
    }

    await sink.flush();
    await sink.close();

    await tempFile.rename(destPath);

    replyPort.send({
      'type': 'encrypt_complete',
      'jobId': jobId,
      'ivBase64': base64Encode(iv),
      'originalSize': totalBytes,
      'encryptedSize': File(destPath).lengthSync(),
    });
  } catch (e) {
    try { await sink.flush(); } catch (_) {}
    try { await sink.close(); } catch (_) {}
    try { await tempFile.delete(); } catch (_) {}
    rethrow;
  }
}

Future<void> _workerDoDecrypt(
    Map<String, dynamic> params, SendPort replyPort, int jobId) async {
  final encryptedPath = params['encryptedPath'] as String;
  final destPath = params['destinationPath'] as String;
  final key = base64Decode(params['keyBase64'] as String);
  final iv = base64Decode(params['ivBase64'] as String);

  final encryptedFile = File(encryptedPath);
  final raf = encryptedFile.openSync();
  final magic = raf.readSync(4);

  if (magic.length < 4 || magic[0] != 0x4C || magic[1] != 0x4B || magic[2] != 0x52) {
    raf.closeSync();
    replyPort.send({'type': 'error', 'jobId': jobId, 'error': 'Invalid file format'});
    return;
  }

  final bool isGcmV2 = magic[3] == 0x32;
  final bool isGcmV1 = magic[3] == 0x47;
  final bool isCtr = magic[3] == 0x53;

  int headerSize;
  int originalSize;

  if (isGcmV2) {
    final rest = raf.readSync(5);
    headerSize = 9;
    originalSize = rest[1] | (rest[2] << 8) | (rest[3] << 16) | (rest[4] << 24);
  } else {
    final rest = raf.readSync(4);
    headerSize = 8;
    originalSize = rest[0] | (rest[1] << 8) | (rest[2] << 16) | (rest[3] << 24);
  }
  raf.closeSync();

  final fileSize = encryptedFile.lengthSync();
  final totalEncryptedBytes = fileSize - headerSize;

  final tempPath = '$destPath.tmp';
  final tempFile = File(tempPath);
  final sink = tempFile.openWrite();

  if (isGcmV2 || isGcmV1) {
    final gcm = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    final outBuf = Uint8List(_kChunkSize + 16);
    int bytesProcessed = 0;
    bool authFailed = false;

    final readRaf = encryptedFile.openSync();
    readRaf.setPositionSync(headerSize);
    try {
      while (true) {
        final chunk = readRaf.readSync(_kChunkSize);
        if (chunk.isEmpty) break;
        final outLen = gcm.processBytes(chunk, 0, chunk.length, outBuf, 0);
        if (outLen > 0) {
          sink.add(Uint8List.view(outBuf.buffer, 0, outLen));
        }
        bytesProcessed += chunk.length;
        replyPort.send({
          'type': 'progress',
          'jobId': jobId,
          'bytesProcessed': bytesProcessed,
          'totalBytes': totalEncryptedBytes,
        });
      }
    } finally {
      readRaf.closeSync();
    }

    try {
      final finalBuf = Uint8List(32);
      gcm.doFinal(finalBuf, 0);
    } on InvalidCipherTextException {
      authFailed = true;
    }

    await sink.flush();
    await sink.close();

    if (authFailed) {
      try {
        await tempFile.delete();
      } catch (_) {}
      replyPort.send({
        'type': 'error',
        'jobId': jobId,
        'error': 'GCM authentication failed',
      });
      return;
    }

    await tempFile.rename(destPath);
    replyPort.send({
      'type': 'decrypt_complete',
      'jobId': jobId,
      'decryptedSize': originalSize,
      'needsMigration': isGcmV1,
    });
  } else if (isCtr) {
    final ctr = CTRStreamCipher(AESEngine())
      ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));

    int bytesProcessed = 0;
    final readRaf = encryptedFile.openSync();
    readRaf.setPositionSync(headerSize);
    try {
      while (true) {
        final chunk = readRaf.readSync(_kChunkSize);
        if (chunk.isEmpty) break;
        sink.add(ctr.process(chunk));
        bytesProcessed += chunk.length;
        replyPort.send({
          'type': 'progress',
          'jobId': jobId,
          'bytesProcessed': bytesProcessed,
          'totalBytes': totalEncryptedBytes,
        });
      }
    } finally {
      readRaf.closeSync();
    }

    await sink.flush();
    await sink.close();
    await tempFile.rename(destPath);

    replyPort.send({
      'type': 'decrypt_complete',
      'jobId': jobId,
      'decryptedSize': originalSize,
      'needsMigration': false,
    });
  } else {
    await sink.close();
    try {
      await tempFile.delete();
    } catch (_) {}
    replyPort.send({
      'type': 'error',
      'jobId': jobId,
      'error': 'Unknown or unsupported file format',
    });
  }
}
