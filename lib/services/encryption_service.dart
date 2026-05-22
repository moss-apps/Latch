import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

const int _streamChunkSize = 1024 * 1024;

const int _magicBytesGcm = 0x4C4B5247;
const int _magicBytesCtr = 0x4C4B5253;
const int _magicBytesCbc = 0x4C4B5244;

/// AES-256 Encryption Service for secure file encryption
/// Uses AES-256-CBC mode with PKCS7 padding
class EncryptionService {
  EncryptionService._();
  static final EncryptionService instance = EncryptionService._();

  // Using the new secure cipher defaults (RSA OAEP + AES-GCM)
  // instead of deprecated encryptedSharedPreferences
  // migrateOnAlgorithmChange ensures existing data is automatically migrated
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _masterKeyKey = 'vault_master_key';
  static const String _decoyKeyKey = 'vault_decoy_key';
  static const int _keySize = 32; // 256 bits
  static const int _ivSize = 16; // 128 bits

  Uint8List? _cachedMasterKey;
  Uint8List? _cachedDecoyKey;

  /// Initialize the encryption service
  /// Creates master key if not exists
  Future<void> initialize() async {
    await _ensureMasterKey();
  }

  /// Ensure master key exists, create if not
  Future<Uint8List> _ensureMasterKey() async {
    if (_cachedMasterKey != null) return _cachedMasterKey!;

    try {
      final storedKey = await _storage.read(key: _masterKeyKey);
      if (storedKey != null) {
        _cachedMasterKey = base64Decode(storedKey);
        return _cachedMasterKey!;
      }
    } catch (e) {
      debugPrint('Error reading master key: $e');
    }

    // Generate new master key
    _cachedMasterKey = _generateRandomBytes(_keySize);
    await _storage.write(
        key: _masterKeyKey, value: base64Encode(_cachedMasterKey!));
    return _cachedMasterKey!;
  }

  /// Get or create decoy key (for decoy mode)
  Future<Uint8List> _ensureDecoyKey() async {
    if (_cachedDecoyKey != null) return _cachedDecoyKey!;

    try {
      final storedKey = await _storage.read(key: _decoyKeyKey);
      if (storedKey != null) {
        _cachedDecoyKey = base64Decode(storedKey);
        return _cachedDecoyKey!;
      }
    } catch (e) {
      debugPrint('Error reading decoy key: $e');
    }

    // Generate new decoy key
    _cachedDecoyKey = _generateRandomBytes(_keySize);
    await _storage.write(
        key: _decoyKeyKey, value: base64Encode(_cachedDecoyKey!));
    return _cachedDecoyKey!;
  }

  /// Generate cryptographically secure random bytes
  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// Generate a random IV (Initialization Vector)
  Uint8List generateIV() {
    return _generateRandomBytes(_ivSize);
  }

  /// Derive key from password using PBKDF2
  Uint8List deriveKeyFromPassword(String password, {Uint8List? salt}) {
    salt ??= _generateRandomBytes(16);

    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 100000, _keySize));

    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// Get the encryption cipher
  PaddedBlockCipher _getCipher(
      Uint8List key, Uint8List iv, bool forEncryption) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );

    cipher.init(
      forEncryption,
      PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );

    return cipher;
  }

  GCMBlockCipher _getGcmCipher(
      Uint8List key, Uint8List iv, bool forEncryption) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(key), 128, iv, Uint8List(0));
    cipher.init(forEncryption, params);
    return cipher;
  }

  Stream<Uint8List> _createChunkedStream(Stream<List<int>> input) {
    return input.transform(_ChunkedStreamTransformer(_streamChunkSize));
  }

  int detectEncryptionFormat(List<int> bytes) {
    if (bytes.length < 4) return 0;
    final magic =
        bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
    if (magic == _magicBytesGcm) return 1; // GCM
    if (magic == _magicBytesCtr) return 2; // CTR (streamed)
    if (magic == _magicBytesCbc) return 3; // CBC (legacy)
    return 0;
  }

  /// Encrypt data using AES-256-CBC
  Future<EncryptionResult> encryptData(
    Uint8List data, {
    bool isDecoy = false,
    Uint8List? customKey,
  }) async {
    try {
      final key = customKey ??
          (isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey());
      final iv = generateIV();

      final cipher = _getCipher(key, iv, true);
      final encrypted = cipher.process(data);

      return EncryptionResult(
        success: true,
        data: encrypted,
        iv: base64Encode(iv),
      );
    } catch (e) {
      debugPrint('Encryption error: $e');
      return EncryptionResult(
        success: false,
        error: 'Encryption failed: $e',
      );
    }
  }

  /// Decrypt data using AES-256-CBC
  Future<DecryptionResult> decryptData(
    Uint8List encryptedData,
    String ivBase64, {
    bool isDecoy = false,
    Uint8List? customKey,
  }) async {
    try {
      debugPrint(
          '[Encryption] decryptData called with ${encryptedData.length} bytes');

      final key = customKey ??
          (isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey());
      final iv = base64Decode(ivBase64);

      // Validate input data length for CBC mode
      if (encryptedData.length % 16 != 0) {
        debugPrint(
            'Decryption error: Invalid data length ${encryptedData.length} (not multiple of 16)');
        // Try CTR mode as fallback - maybe file was incorrectly detected
        debugPrint('[Encryption] Attempting CTR fallback...');
        return await _tryCtrFallback(encryptedData, ivBase64, isDecoy);
      }

      final cipher = _getCipher(key, iv, false);
      final decrypted = cipher.process(encryptedData);

      return DecryptionResult(
        success: true,
        data: decrypted,
      );
    } catch (e) {
      debugPrint('Decryption error: $e');
      return DecryptionResult(
        success: false,
        error: 'Decryption failed: $e',
      );
    }
  }

  /// CTR fallback when CBC fails
  Future<DecryptionResult> _tryCtrFallback(
    Uint8List encryptedData,
    String ivBase64,
    bool isDecoy,
  ) async {
    try {
      final key = isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey();
      final iv = base64Decode(ivBase64);

      final ctr = CTRStreamCipher(AESEngine())
        ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));

      final decrypted = ctr.process(encryptedData);

      debugPrint('[Encryption] CTR fallback succeeded!');
      return DecryptionResult(
        success: true,
        data: decrypted,
      );
    } catch (e) {
      debugPrint('[Encryption] CTR fallback failed: $e');
      return DecryptionResult(
        success: false,
        error: 'Decryption failed: $e',
      );
    }
  }

  /// Encrypt a file and return the encrypted file path
  Future<FileEncryptionResult> encryptFile(
    String sourcePath,
    String destinationPath, {
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return FileEncryptionResult(
          success: false,
          error: 'Source file does not exist',
        );
      }

      final data = await sourceFile.readAsBytes();
      onProgress?.call(1, 3);

      final result = await encryptData(data, isDecoy: isDecoy);
      onProgress?.call(2, 3);

      if (!result.success || result.data == null) {
        return FileEncryptionResult(
          success: false,
          error: result.error ?? 'Encryption failed',
        );
      }

      final destFile = File(destinationPath);
      await destFile.writeAsBytes(result.data!);
      onProgress?.call(3, 3);

      return FileEncryptionResult(
        success: true,
        encryptedPath: destinationPath,
        iv: result.iv,
        originalSize: data.length,
        encryptedSize: result.data!.length,
      );
    } catch (e) {
      debugPrint('File encryption error: $e');
      return FileEncryptionResult(
        success: false,
        error: 'File encryption failed: $e',
      );
    }
  }

  /// Encrypt a file using chunked streaming (memory-efficient for large files)
  /// Processes file in chunks to avoid loading entire file into memory
  /// Uses CTR mode for streaming (CBC requires full blocks, not suitable for streaming)
  Future<FileEncryptionResult> encryptFileStreamed(
    String sourcePath,
    String destinationPath, {
    bool isDecoy = false,
    Function(int bytesProcessed, int totalBytes)? onProgress,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return FileEncryptionResult(
          success: false,
          error: 'Source file does not exist',
        );
      }

      final key = isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey();
      final iv = generateIV();
      final totalBytes = await sourceFile.length();

      // Use CTR mode for streaming - it's a stream cipher that doesn't require padding
      final ctr = CTRStreamCipher(AESEngine())
        ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));

      final destFile = File(destinationPath);
      final sink = destFile.openWrite();

      // Write 8-byte header: 4 bytes magic + 4 bytes original file size
      // Magic bytes help identify streamed encrypted files
      final header = Uint8List(8);
      header[0] = 0x4C; // 'L'
      header[1] = 0x4B; // 'K'
      header[2] = 0x52; // 'R'
      header[3] = 0x53; // 'S' (Latch Streamed)
      // Store original file size (little-endian)
      header[4] = (totalBytes & 0xFF);
      header[5] = ((totalBytes >> 8) & 0xFF);
      header[6] = ((totalBytes >> 16) & 0xFF);
      header[7] = ((totalBytes >> 24) & 0xFF);
      sink.add(header);

      int bytesProcessed = 0;

      final inputStream = _createChunkedStream(sourceFile.openRead());
      await for (final chunk in inputStream) {
        final encrypted = ctr.process(chunk);
        sink.add(encrypted);

        bytesProcessed += chunk.length;
        onProgress?.call(bytesProcessed, totalBytes);
      }

      await sink.flush();
      await sink.close();

      final encryptedSize = await destFile.length();

      return FileEncryptionResult(
        success: true,
        encryptedPath: destinationPath,
        iv: base64Encode(iv),
        originalSize: totalBytes,
        encryptedSize: encryptedSize,
      );
    } catch (e) {
      debugPrint('File streaming encryption error: $e');
      return FileEncryptionResult(
        success: false,
        error: 'File streaming encryption failed: $e',
      );
    }
  }

  /// Encrypt in-memory bytes using CTR streaming and write to file
  /// Avoids temp file I/O when data is already in memory (e.g. compressed images)
  Future<FileEncryptionResult> encryptBytesStreamed(
    Uint8List data,
    String destinationPath, {
    bool isDecoy = false,
    Function(int bytesProcessed, int totalBytes)? onProgress,
  }) async {
    try {
      final key = isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey();
      final iv = generateIV();
      final totalBytes = data.length;

      onProgress?.call(0, totalBytes);

      final ctr = CTRStreamCipher(AESEngine())
        ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));

      final encrypted = ctr.process(data);

      onProgress?.call(totalBytes, totalBytes);

      final header = Uint8List(8);
      header[0] = 0x4C;
      header[1] = 0x4B;
      header[2] = 0x52;
      header[3] = 0x53;
      header[4] = (totalBytes & 0xFF);
      header[5] = ((totalBytes >> 8) & 0xFF);
      header[6] = ((totalBytes >> 16) & 0xFF);
      header[7] = ((totalBytes >> 24) & 0xFF);

      final destFile = File(destinationPath);
      final sink = destFile.openWrite();
      sink.add(header);
      sink.add(encrypted);
      await sink.flush();
      await sink.close();

      final encryptedSize = await destFile.length();

      return FileEncryptionResult(
        success: true,
        encryptedPath: destinationPath,
        iv: base64Encode(iv),
        originalSize: totalBytes,
        encryptedSize: encryptedSize,
      );
    } catch (e) {
      debugPrint('Bytes streaming encryption error: $e');
      return FileEncryptionResult(
        success: false,
        error: 'Bytes streaming encryption failed: $e',
      );
    }
  }

  /// Encrypt in-memory bytes using GCM and write to file
  Future<FileEncryptionResult> encryptBytesStreamedGcm(
    Uint8List data,
    String destinationPath, {
    bool isDecoy = false,
  }) async {
    try {
      final key = isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey();
      final iv = generateIV();

      final gcm = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

      final encrypted = gcm.process(data);

      final header = Uint8List(8);
      header[0] = 0x4C;
      header[1] = 0x4B;
      header[2] = 0x52;
      header[3] = 0x47;
      header[4] = (data.length & 0xFF);
      header[5] = ((data.length >> 8) & 0xFF);
      header[6] = ((data.length >> 16) & 0xFF);
      header[7] = ((data.length >> 24) & 0xFF);

      final destFile = File(destinationPath);
      final sink = destFile.openWrite();
      sink.add(header);
      sink.add(encrypted);
      await sink.flush();
      await sink.close();

      final encryptedSize = await destFile.length();

      return FileEncryptionResult(
        success: true,
        encryptedPath: destinationPath,
        iv: base64Encode(iv),
        originalSize: data.length,
        encryptedSize: encryptedSize,
      );
    } catch (e) {
      debugPrint('Bytes GCM streaming encryption error: $e');
      return FileEncryptionResult(
        success: false,
        error: 'Bytes GCM streaming encryption failed: $e',
      );
    }
  }

  /// Decrypt a file and return the decrypted file path
  /// Automatically detects format (CTR streamed or CBC)
  Future<FileDecryptionResult> decryptFile(
    String encryptedPath,
    String destinationPath,
    String ivBase64, {
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      final encryptedFile = File(encryptedPath);
      if (!await encryptedFile.exists()) {
        return FileDecryptionResult(
          success: false,
          error: 'Encrypted file does not exist',
        );
      }

      // Check magic bytes to determine format
      final raf = await encryptedFile.open();
      final header = await raf.read(8);
      await raf.close();

      if (header.length >= 4 &&
          header[0] == 0x4C &&
          header[1] == 0x4B &&
          header[2] == 0x52 &&
          header[3] == 0x53) {
        // CTR-encrypted streamed file - use streaming decryption
        debugPrint('[Encryption] Using CTR format for decryptFile');
        onProgress?.call(1, 3);

        final result = await decryptFileStreamed(
          encryptedPath,
          destinationPath,
          ivBase64,
          isDecoy: isDecoy,
        );

        onProgress?.call(3, 3);
        return result;
      } else {
        // CBC-encrypted file
        onProgress?.call(1, 3);
        final encryptedData = await encryptedFile.readAsBytes();

        final result = await decryptData(
          encryptedData,
          ivBase64,
          isDecoy: isDecoy,
        );
        onProgress?.call(2, 3);

        if (!result.success || result.data == null) {
          return FileDecryptionResult(
            success: false,
            error: result.error ?? 'Decryption failed',
          );
        }

        final destFile = File(destinationPath);
        await destFile.writeAsBytes(result.data!);
        onProgress?.call(3, 3);

        return FileDecryptionResult(
          success: true,
          decryptedPath: destinationPath,
          decryptedSize: result.data!.length,
        );
      }
    } catch (e) {
      debugPrint('File decryption error: $e');
      return FileDecryptionResult(
        success: false,
        error: 'File decryption failed: $e',
      );
    }
  }

  /// Decrypt a file using chunked streaming (memory-efficient for large files)
  /// Matches the format created by encryptFileStreamed (8-byte header + CTR encrypted data)
  Future<FileDecryptionResult> decryptFileStreamed(
    String encryptedPath,
    String destinationPath,
    String ivBase64, {
    bool isDecoy = false,
    Function(int bytesProcessed, int totalBytes)? onProgress,
  }) async {
    try {
      final encryptedFile = File(encryptedPath);
      if (!await encryptedFile.exists()) {
        return FileDecryptionResult(
          success: false,
          error: 'Encrypted file does not exist',
        );
      }

      final key = isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey();
      final iv = base64Decode(ivBase64);
      final encryptedSize = await encryptedFile.length();

      // Open file and read header
      final raf = await encryptedFile.open();
      final header = await raf.read(8);

      // Verify magic bytes
      if (header.length < 8 ||
          header[0] != 0x4C ||
          header[1] != 0x4B ||
          header[2] != 0x52 ||
          header[3] != 0x53) {
        await raf.close();
        return FileDecryptionResult(
          success: false,
          error: 'Invalid encrypted file format (not a streamed file)',
        );
      }

      // Read original file size from header (little-endian)
      final originalSize =
          header[4] | (header[5] << 8) | (header[6] << 16) | (header[7] << 24);

      await raf.close();

      // Use CTR mode for streaming decryption
      final ctr = CTRStreamCipher(AESEngine())
        ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));

      final destFile = File(destinationPath);
      final sink = destFile.openWrite();

      final totalBytes = encryptedSize - 8; // Subtract header size
      int bytesProcessed = 0;

      onProgress?.call(0, totalBytes);

      // Read encrypted data after header - use chunked stream
      final inputStream = _createChunkedStream(encryptedFile.openRead(8));
      await for (final chunk in inputStream) {
        final decrypted = ctr.process(chunk);
        sink.add(decrypted);

        bytesProcessed += chunk.length;
        onProgress?.call(bytesProcessed, totalBytes);
      }

      onProgress?.call(totalBytes, totalBytes);

      await sink.flush();
      await sink.close();

      return FileDecryptionResult(
        success: true,
        decryptedPath: destinationPath,
        decryptedSize: originalSize,
      );
    } catch (e) {
      debugPrint('File streaming decryption error: $e');
      return FileDecryptionResult(
        success: false,
        error: 'File streaming decryption failed: $e',
      );
    }
  }

  /// Decrypt streamed file to memory (for viewing without writing to disk)
  /// Supports both CBC-encrypted files (legacy) and CTR-encrypted streamed files
  Future<DecryptionResult> decryptStreamedFileToMemory(
    String encryptedPath,
    String ivBase64, {
    bool isDecoy = false,
  }) async {
    try {
      final encryptedFile = File(encryptedPath);
      if (!await encryptedFile.exists()) {
        return DecryptionResult(
          success: false,
          error: 'Encrypted file does not exist',
        );
      }

      final fileSize = await encryptedFile.length();

      // Check magic bytes first (without loading entire file)
      final raf = await encryptedFile.open();
      final header = await raf.read(8);
      await raf.close();

      if (header.length >= 4 &&
          header[0] == 0x4C &&
          header[1] == 0x4B &&
          header[2] == 0x52 &&
          header[3] == 0x53) {
        // CTR-encrypted streamed file - use streaming decryption
        debugPrint('[Encryption] Detected CTR streamed format');
        final key =
            isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey();
        final iv = base64Decode(ivBase64);

        final ctr = CTRStreamCipher(AESEngine())
          ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));

        // Stream decryption without loading entire file
        final inputStream = _createChunkedStream(encryptedFile.openRead(8));
        final decryptedBytes = <int>[];

        await for (final chunk in inputStream) {
          final decrypted = ctr.process(chunk);
          decryptedBytes.addAll(decrypted);
        }

        return DecryptionResult(
          success: true,
          data: Uint8List.fromList(decryptedBytes),
        );
      } else if (header.length >= 4 &&
          header[0] == 0x4C &&
          header[1] == 0x4B &&
          header[2] == 0x52 &&
          header[3] == 0x44) {
        // CBC-encrypted file with header - skip the 8-byte header
        debugPrint('[Encryption] Detected CBC format with header');
        final raf2 = await encryptedFile.open();
        await raf2.setPosition(8); // Skip header
        final encryptedData = await raf2.read(fileSize - 8);
        await raf2.close();

        // Validate data length
        if (encryptedData.length % 16 != 0) {
          debugPrint(
              '[Encryption] Invalid CBC data length: ${encryptedData.length}');
          return DecryptionResult(
            success: false,
            error: 'Corrupted encrypted file: invalid data length',
          );
        }

        return await decryptData(
          Uint8List.fromList(encryptedData),
          ivBase64,
          isDecoy: isDecoy,
        );
      } else {
        // Legacy CBC file without header - decrypt entire file
        debugPrint('[Encryption] Detected legacy CBC format (no header)');
        final encryptedData = await encryptedFile.readAsBytes();

        // Validate data length
        if (encryptedData.length % 16 != 0) {
          debugPrint(
              '[Encryption] Invalid CBC data length: ${encryptedData.length}');
          debugPrint(
              '[Encryption] File size: $fileSize, Remainder: ${encryptedData.length % 16}');
          return DecryptionResult(
            success: false,
            error:
                'Corrupted encrypted file: data length ${encryptedData.length} is not a multiple of 16 bytes',
          );
        }

        return await decryptData(
          encryptedData,
          ivBase64,
          isDecoy: isDecoy,
        );
      }
    } catch (e) {
      debugPrint('Streamed file decryption to memory error: $e');
      return DecryptionResult(
        success: false,
        error: 'File decryption failed: $e',
      );
    }
  }

  /// Decrypt file to memory (for viewing without writing to disk)
  /// Automatically detects format (CTR streamed or CBC) and decrypts accordingly
  Future<DecryptionResult> decryptFileToMemory(
    String encryptedPath,
    String ivBase64, {
    bool isDecoy = false,
  }) async {
    // Delegate to the format-detecting function
    return decryptStreamedFileToMemory(
      encryptedPath,
      ivBase64,
      isDecoy: isDecoy,
    );
  }

  /// Encrypt data using AES-256-GCM (faster + authenticated)
  Future<EncryptionResult> encryptDataGcm(
    Uint8List data, {
    bool isDecoy = false,
    Uint8List? customKey,
  }) async {
    try {
      final key = customKey ??
          (isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey());
      final iv = generateIV();

      final cipher = _getGcmCipher(key, iv, true);
      final encrypted = cipher.process(data);

      return EncryptionResult(
        success: true,
        data: encrypted,
        iv: base64Encode(iv),
      );
    } catch (e) {
      debugPrint('GCM Encryption error: $e');
      return EncryptionResult(
        success: false,
        error: 'GCM Encryption failed: $e',
      );
    }
  }

  /// Decrypt data using AES-256-GCM (faster + authenticated)
  Future<DecryptionResult> decryptDataGcm(
    Uint8List encryptedData,
    String ivBase64, {
    bool isDecoy = false,
    Uint8List? customKey,
  }) async {
    try {
      final key = customKey ??
          (isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey());
      final iv = base64Decode(ivBase64);

      final cipher = _getGcmCipher(key, iv, false);
      final decrypted = cipher.process(encryptedData);

      return DecryptionResult(
        success: true,
        data: decrypted,
      );
    } catch (e) {
      debugPrint('GCM Decryption error: $e');
      return DecryptionResult(
        success: false,
        error: 'GCM Decryption failed: $e',
      );
    }
  }

  /// Encrypt file using AES-256-GCM (faster + authenticated)
  Future<FileEncryptionResult> encryptFileGcm(
    String sourcePath,
    String destinationPath, {
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return FileEncryptionResult(
          success: false,
          error: 'Source file does not exist',
        );
      }

      final data = await sourceFile.readAsBytes();
      onProgress?.call(1, 3);

      final result = await encryptDataGcm(
        data,
        isDecoy: isDecoy,
      );
      onProgress?.call(2, 3);

      if (!result.success || result.data == null) {
        return FileEncryptionResult(
          success: false,
          error: result.error ?? 'GCM Encryption failed',
        );
      }

      final destFile = File(destinationPath);
      final sink = destFile.openWrite();

      // Write GCM header: 4 bytes magic + 4 bytes original file size
      final header = Uint8List(8);
      header[0] = 0x4C; // 'L'
      header[1] = 0x4B; // 'K'
      header[2] = 0x52; // 'R'
      header[3] = 0x47; // 'G' (GCM)
      header[4] = (data.length & 0xFF);
      header[5] = ((data.length >> 8) & 0xFF);
      header[6] = ((data.length >> 16) & 0xFF);
      header[7] = ((data.length >> 24) & 0xFF);
      sink.add(header);
      sink.add(result.data!);

      await sink.flush();
      await sink.close();
      onProgress?.call(3, 3);

      return FileEncryptionResult(
        success: true,
        encryptedPath: destinationPath,
        iv: result.iv,
        originalSize: data.length,
        encryptedSize: result.data!.length + 8,
      );
    } catch (e) {
      debugPrint('GCM File encryption error: $e');
      return FileEncryptionResult(
        success: false,
        error: 'GCM File encryption failed: $e',
      );
    }
  }

  /// Decrypt file using AES-256-GCM (faster + authenticated)
  Future<FileDecryptionResult> decryptFileGcm(
    String encryptedPath,
    String destinationPath,
    String ivBase64, {
    bool isDecoy = false,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      final encryptedFile = File(encryptedPath);
      if (!await encryptedFile.exists()) {
        return FileDecryptionResult(
          success: false,
          error: 'Encrypted file does not exist',
        );
      }

      final raf = await encryptedFile.open();
      final header = await raf.read(8);

      // Verify GCM magic bytes
      if (header.length < 8 ||
          header[0] != 0x4C ||
          header[1] != 0x4B ||
          header[2] != 0x52 ||
          header[3] != 0x47) {
        await raf.close();
        return FileDecryptionResult(
          success: false,
          error: 'Not a GCM-encrypted file',
        );
      }

      final originalSize =
          header[4] | (header[5] << 8) | (header[6] << 16) | (header[7] << 24);

      final encryptedData = await raf.read(await encryptedFile.length() - 8);
      await raf.close();

      onProgress?.call(1, 2);

      final result = await decryptDataGcm(
        encryptedData,
        ivBase64,
        isDecoy: isDecoy,
      );
      onProgress?.call(2, 2);

      if (!result.success || result.data == null) {
        return FileDecryptionResult(
          success: false,
          error: result.error ?? 'GCM Decryption failed',
        );
      }

      final destFile = File(destinationPath);
      await destFile.writeAsBytes(result.data!);

      return FileDecryptionResult(
        success: true,
        decryptedPath: destinationPath,
        decryptedSize: originalSize,
      );
    } catch (e) {
      debugPrint('GCM File decryption error: $e');
      return FileDecryptionResult(
        success: false,
        error: 'GCM File decryption failed: $e',
      );
    }
  }

  /// Encrypt file using GCM with streaming (memory-efficient for large files)
  Future<FileEncryptionResult> encryptFileStreamedGcm(
    String sourcePath,
    String destinationPath, {
    bool isDecoy = false,
    Function(int bytesProcessed, int totalBytes)? onProgress,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return FileEncryptionResult(
          success: false,
          error: 'Source file does not exist',
        );
      }

      final key = isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey();
      final iv = generateIV();
      final totalBytes = await sourceFile.length();

      final gcm = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

      final destFile = File(destinationPath);
      final sink = destFile.openWrite();

      // Write GCM header
      final header = Uint8List(8);
      header[0] = 0x4C;
      header[1] = 0x4B;
      header[2] = 0x52;
      header[3] = 0x47;
      header[4] = (totalBytes & 0xFF);
      header[5] = ((totalBytes >> 8) & 0xFF);
      header[6] = ((totalBytes >> 16) & 0xFF);
      header[7] = ((totalBytes >> 24) & 0xFF);
      sink.add(header);

      int bytesProcessed = 0;
      final inputStream = _createChunkedStream(sourceFile.openRead());

      await for (final chunk in inputStream) {
        final encrypted = gcm.process(chunk);
        sink.add(encrypted);

        bytesProcessed += chunk.length;
        onProgress?.call(bytesProcessed, totalBytes);
      }

      await sink.flush();
      await sink.close();

      return FileEncryptionResult(
        success: true,
        encryptedPath: destinationPath,
        iv: base64Encode(iv),
        originalSize: totalBytes,
        encryptedSize: await destFile.length(),
      );
    } catch (e) {
      debugPrint('GCM streaming encryption error: $e');
      return FileEncryptionResult(
        success: false,
        error: 'GCM streaming encryption failed: $e',
      );
    }
  }

  /// Decrypt GCM streamed file to memory
  Future<DecryptionResult> decryptStreamedFileToMemoryGcm(
    String encryptedPath,
    String ivBase64, {
    bool isDecoy = false,
  }) async {
    try {
      final encryptedFile = File(encryptedPath);
      if (!await encryptedFile.exists()) {
        return DecryptionResult(
          success: false,
          error: 'Encrypted file does not exist',
        );
      }

      final key = isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey();
      final iv = base64Decode(ivBase64);

      final gcm = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

      final raf = await encryptedFile.open();
      await raf.read(8); // Skip header

      final encryptedData = await raf.read(await encryptedFile.length() - 8);
      await raf.close();

      final decrypted = gcm.process(encryptedData);

      return DecryptionResult(
        success: true,
        data: decrypted,
      );
    } catch (e) {
      debugPrint('GCM streamed decryption error: $e');
      return DecryptionResult(
        success: false,
        error: 'GCM decryption failed: $e',
      );
    }
  }

  /// Encrypt file in isolate (for large files)
  Future<FileEncryptionResult> encryptFileInIsolate(
    String sourcePath,
    String destinationPath, {
    bool isDecoy = false,
    bool useGcm = true,
    Function(int bytesProcessed, int totalBytes)? onProgress,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return FileEncryptionResult(
          success: false,
          error: 'Source file does not exist',
        );
      }

      final key = isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey();
      final iv = generateIV();
      final totalBytes = await sourceFile.length();

      onProgress?.call(0, totalBytes);

      final result = await compute(
        _encryptFileIsolate,
        _IsolateEncryptParams(
          sourcePath: sourcePath,
          destinationPath: destinationPath,
          keyBase64: base64Encode(key),
          ivBase64: base64Encode(iv),
          useGcm: useGcm,
        ),
      );

      onProgress?.call(totalBytes, totalBytes);

      if (result.success) {
        return FileEncryptionResult(
          success: true,
          encryptedPath: destinationPath,
          iv: base64Encode(iv),
          originalSize: totalBytes,
          encryptedSize: result.encryptedSize,
        );
      } else {
        return FileEncryptionResult(
          success: false,
          error: result.error,
        );
      }
    } catch (e) {
      debugPrint('Isolate encryption error: $e');
      return FileEncryptionResult(
        success: false,
        error: 'Isolate encryption failed: $e',
      );
    }
  }

  /// Decrypt file in isolate (for large files)
  Future<FileDecryptionResult> decryptFileInIsolate(
    String encryptedPath,
    String destinationPath,
    String ivBase64, {
    bool isDecoy = false,
    bool useGcm = false,
    Function(int bytesProcessed, int totalBytes)? onProgress,
  }) async {
    try {
      final encryptedFile = File(encryptedPath);
      if (!await encryptedFile.exists()) {
        return FileDecryptionResult(
          success: false,
          error: 'Encrypted file does not exist',
        );
      }

      final key = isDecoy ? await _ensureDecoyKey() : await _ensureMasterKey();

      final result = await compute(
        _decryptFileIsolate,
        _IsolateDecryptParams(
          encryptedPath: encryptedPath,
          destinationPath: destinationPath,
          keyBase64: base64Encode(key),
          ivBase64: ivBase64,
          useGcm: useGcm,
        ),
      );

      if (result.success) {
        return FileDecryptionResult(
          success: true,
          decryptedPath: destinationPath,
          decryptedSize: result.decryptedSize,
        );
      } else {
        return FileDecryptionResult(
          success: false,
          error: result.error,
        );
      }
    } catch (e) {
      debugPrint('Isolate decryption error: $e');
      return FileDecryptionResult(
        success: false,
        error: 'Isolate decryption failed: $e',
      );
    }
  }

  /// Generate a hash of the data (for integrity verification)
  String generateHash(Uint8List data) {
    return sha256.convert(data).toString();
  }

  /// Verify data integrity using hash
  bool verifyHash(Uint8List data, String expectedHash) {
    return generateHash(data) == expectedHash;
  }

  /// Securely delete a file (overwrite before delete) - optimized for large files
  Future<bool> secureDelete(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return true;

      // Get file size
      final length = await file.length();

      // Open file for random access
      final raf = await file.open(mode: FileMode.write);

      try {
        // Use 1MB chunks for processing
        const int chunkSize = 1024 * 1024;

        // Generate one chunk of random data to reuse (much faster/lighter than generating unique for whole file)
        // While theoretically less secure than unique random bytes for every byte,
        // it serves the purpose of destorying the original data structure.
        final randomChunk = _generateRandomBytes(chunkSize);
        final zeroChunk = Uint8List(chunkSize); // Default initialized to 0

        // Pass 1: Overwrite with random data
        int written = 0;
        await raf.setPosition(0);
        while (written < length) {
          final remaining = length - written;
          final toWrite = remaining < chunkSize ? remaining : chunkSize;

          if (toWrite == chunkSize) {
            await raf.writeFrom(randomChunk);
          } else {
            await raf.writeFrom(randomChunk, 0, toWrite.toInt());
          }
          written += toWrite;
        }

        // Pass 2: Overwrite with zeros
        written = 0;
        await raf.setPosition(0);
        while (written < length) {
          final remaining = length - written;
          final toWrite = remaining < chunkSize ? remaining : chunkSize;

          if (toWrite == chunkSize) {
            await raf.writeFrom(zeroChunk);
          } else {
            await raf.writeFrom(zeroChunk, 0, toWrite.toInt());
          }
          written += toWrite;
        }
      } finally {
        await raf.close();
      }

      // Delete the file
      await file.delete();
      return true;
    } catch (e) {
      debugPrint('Secure delete error: $e');
      try {
        // Try regular delete as fallback
        await File(filePath).delete();
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Re-encrypt all files with a new key (for key rotation)
  Future<KeyRotationResult> rotateKey({
    required List<String> encryptedFilePaths,
    required List<String> ivs,
    required String tempDirectory,
    Function(int current, int total)? onProgress,
  }) async {
    try {
      if (encryptedFilePaths.length != ivs.length) {
        return KeyRotationResult(
          success: false,
          error: 'File paths and IVs count mismatch',
        );
      }

      // Generate new key
      final newKey = _generateRandomBytes(_keySize);
      final newIvs = <String>[];

      // Re-encrypt each file
      for (int i = 0; i < encryptedFilePaths.length; i++) {
        onProgress?.call(i + 1, encryptedFilePaths.length);

        final path = encryptedFilePaths[i];
        final oldIv = ivs[i];

        // Decrypt with old key
        final decrypted = await decryptFileToMemory(path, oldIv);
        if (!decrypted.success || decrypted.data == null) {
          return KeyRotationResult(
            success: false,
            error: 'Failed to decrypt file at index $i',
            processedCount: i,
          );
        }

        // Encrypt with new key
        final newIv = generateIV();
        final cipher = _getCipher(newKey, newIv, true);
        final reEncrypted = cipher.process(decrypted.data!);

        // Write back
        await File(path).writeAsBytes(reEncrypted);
        newIvs.add(base64Encode(newIv));
      }

      // Save new key
      _cachedMasterKey = newKey;
      await _storage.write(key: _masterKeyKey, value: base64Encode(newKey));

      return KeyRotationResult(
        success: true,
        newIvs: newIvs,
        processedCount: encryptedFilePaths.length,
      );
    } catch (e) {
      debugPrint('Key rotation error: $e');
      return KeyRotationResult(
        success: false,
        error: 'Key rotation failed: $e',
      );
    }
  }

  /// Check if encryption is enabled
  Future<bool> hasEncryptionKey() async {
    try {
      final key = await _storage.read(key: _masterKeyKey);
      return key != null;
    } catch (e) {
      return false;
    }
  }

  /// Reset encryption keys (dangerous - all encrypted data will be lost!)
  Future<void> resetKeys() async {
    _cachedMasterKey = null;
    _cachedDecoyKey = null;
    await _storage.delete(key: _masterKeyKey);
    await _storage.delete(key: _decoyKeyKey);
  }
}

// ---------------------------------------------------------------------------
// Isolate helpers (top-level so they can be passed to compute())
// ---------------------------------------------------------------------------

class _IsolateEncryptParams {
  final String sourcePath;
  final String destinationPath;
  final String keyBase64;
  final String ivBase64;
  final bool useGcm;

  const _IsolateEncryptParams({
    required this.sourcePath,
    required this.destinationPath,
    required this.keyBase64,
    required this.ivBase64,
    required this.useGcm,
  });
}

class _IsolateDecryptParams {
  final String encryptedPath;
  final String destinationPath;
  final String keyBase64;
  final String ivBase64;
  final bool useGcm;

  const _IsolateDecryptParams({
    required this.encryptedPath,
    required this.destinationPath,
    required this.keyBase64,
    required this.ivBase64,
    required this.useGcm,
  });
}

class _IsolateEncryptResult {
  final bool success;
  final int encryptedSize;
  final String? error;

  const _IsolateEncryptResult({
    required this.success,
    this.encryptedSize = 0,
    this.error,
  });
}

class _IsolateDecryptResult {
  final bool success;
  final int decryptedSize;
  final String? error;

  const _IsolateDecryptResult({
    required this.success,
    this.decryptedSize = 0,
    this.error,
  });
}

Future<_IsolateEncryptResult> _encryptFileIsolate(
    _IsolateEncryptParams params) async {
  try {
    final key = base64Decode(params.keyBase64);
    final iv = base64Decode(params.ivBase64);
    final sourceFile = File(params.sourcePath);
    final destFile = File(params.destinationPath);
    final totalBytes = await sourceFile.length();
    final sink = destFile.openWrite();

    if (params.useGcm) {
      final gcm = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

      final header = Uint8List(8);
      header[0] = 0x4C;
      header[1] = 0x4B;
      header[2] = 0x52;
      header[3] = 0x47;
      header[4] = (totalBytes & 0xFF);
      header[5] = ((totalBytes >> 8) & 0xFF);
      header[6] = ((totalBytes >> 16) & 0xFF);
      header[7] = ((totalBytes >> 24) & 0xFF);
      sink.add(header);

      await for (final chunk in sourceFile
          .openRead()
          .transform(_ChunkedStreamTransformer(1024 * 1024))) {
        sink.add(gcm.process(chunk));
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

      await for (final chunk in sourceFile
          .openRead()
          .transform(_ChunkedStreamTransformer(1024 * 1024))) {
        sink.add(ctr.process(chunk));
      }
    }

    await sink.flush();
    await sink.close();

    return _IsolateEncryptResult(
      success: true,
      encryptedSize: await destFile.length(),
    );
  } catch (e) {
    return _IsolateEncryptResult(success: false, error: e.toString());
  }
}

Future<_IsolateDecryptResult> _decryptFileIsolate(
    _IsolateDecryptParams params) async {
  try {
    final key = base64Decode(params.keyBase64);
    final iv = base64Decode(params.ivBase64);
    final encryptedFile = File(params.encryptedPath);
    final destFile = File(params.destinationPath);
    final sink = destFile.openWrite();

    final raf = await encryptedFile.open();
    final header = await raf.read(8);
    await raf.close();

    if (header.length < 8) {
      return _IsolateDecryptResult(
          success: false, error: 'File too short to contain header');
    }

    final originalSize =
        header[4] | (header[5] << 8) | (header[6] << 16) | (header[7] << 24);

    if (params.useGcm &&
        header[0] == 0x4C &&
        header[1] == 0x4B &&
        header[2] == 0x52 &&
        header[3] == 0x47) {
      final gcm = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      await for (final chunk in encryptedFile
          .openRead(8)
          .transform(_ChunkedStreamTransformer(1024 * 1024))) {
        sink.add(gcm.process(chunk));
      }
    } else if (header[0] == 0x4C &&
        header[1] == 0x4B &&
        header[2] == 0x52 &&
        header[3] == 0x53) {
      final ctr = CTRStreamCipher(AESEngine())
        ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));
      await for (final chunk in encryptedFile
          .openRead(8)
          .transform(_ChunkedStreamTransformer(1024 * 1024))) {
        sink.add(ctr.process(chunk));
      }
    } else {
      await sink.close();
      return _IsolateDecryptResult(
          success: false, error: 'Unknown file format');
    }

    await sink.flush();
    await sink.close();

    return _IsolateDecryptResult(success: true, decryptedSize: originalSize);
  } catch (e) {
    return _IsolateDecryptResult(success: false, error: e.toString());
  }
}

/// Result of data encryption
class EncryptionResult {
  final bool success;
  final Uint8List? data;
  final String? iv;
  final String? error;

  const EncryptionResult({
    required this.success,
    this.data,
    this.iv,
    this.error,
  });
}

/// Result of data decryption
class DecryptionResult {
  final bool success;
  final Uint8List? data;
  final String? error;

  const DecryptionResult({
    required this.success,
    this.data,
    this.error,
  });
}

/// Result of file encryption
class FileEncryptionResult {
  final bool success;
  final String? encryptedPath;
  final String? iv;
  final int? originalSize;
  final int? encryptedSize;
  final String? error;

  const FileEncryptionResult({
    required this.success,
    this.encryptedPath,
    this.iv,
    this.originalSize,
    this.encryptedSize,
    this.error,
  });
}

/// Result of file decryption
class FileDecryptionResult {
  final bool success;
  final String? decryptedPath;
  final int? decryptedSize;
  final String? error;

  const FileDecryptionResult({
    required this.success,
    this.decryptedPath,
    this.decryptedSize,
    this.error,
  });
}

/// Result of key rotation
class KeyRotationResult {
  final bool success;
  final List<String>? newIvs;
  final int processedCount;
  final String? error;

  const KeyRotationResult({
    required this.success,
    this.newIvs,
    this.processedCount = 0,
    this.error,
  });
}

class _ChunkedStreamTransformer
    extends StreamTransformerBase<List<int>, Uint8List> {
  final int chunkSize;

  _ChunkedStreamTransformer(this.chunkSize);

  @override
  Stream<Uint8List> bind(Stream<List<int>> stream) {
    final controller = StreamController<Uint8List>();
    var buf = Uint8List(0);
    int fill = 0;

    stream.listen(
      (data) {
        if (data.isEmpty) return;

        final newFill = fill + data.length;
        if (newFill > buf.length) {
          final grown = Uint8List((newFill * 1.5).ceil());
          if (fill > 0) grown.setRange(0, fill, buf);
          buf = grown;
        }
        buf.setAll(fill, data);
        fill = newFill;

        while (fill >= chunkSize) {
          controller.add(Uint8List.sublistView(buf, 0, chunkSize));
          fill -= chunkSize;
          if (fill > 0) {
            buf = Uint8List.fromList(
                Uint8List.sublistView(buf, chunkSize, chunkSize + fill));
          } else {
            buf = Uint8List(0);
          }
        }
      },
      onDone: () {
        if (fill > 0) {
          controller.add(Uint8List.sublistView(buf, 0, fill));
        }
        controller.close();
      },
      onError: controller.addError,
    );

    return controller.stream;
  }
}
