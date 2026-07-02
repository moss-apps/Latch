import 'dart:io';
import 'dart:typed_data';

/// Encryption format identifiers returned by [HeaderCodec.detectFormat].
const int kFormatUnknown = 0;
const int kFormatGcmV1 = 1;
const int kFormatCtr = 2;
const int kFormatCbc = 3;
const int kFormatGcmV2 = 4;

/// Magic words for each on-disk format, combined the same way
/// [detectFormat] reads them (LE: X<<24 | 0x52<<16 | 0x4B<<8 | 0x4C). The
/// on-disk prefix is always 0x4C,0x4B,0x52,X.
const int kMagicGcmV1 = 0x47524B4C; // 'L','K','R','G'
const int kMagicGcmV2 = 0x32524B4C; // 'L','K','R','2'
const int kMagicCtr = 0x53524B4C; // 'L','K','R','S'
const int kMagicCbc = 0x44524B4C; // 'L','K','R','D'

/// AES-GCM authentication tag size in bytes.
const int kGcmTagSize = 16;

/// Size of the v2 (authenticated) GCM header in bytes.
const int kV2HeaderSize = 9;

/// Size of the legacy stream header (magic + original size).
const int kStreamHeaderSize = 8;

/// Decoded view of an on-disk encrypted file's header.
class HeaderInfo {
  final int format;
  final int headerSize;
  final int originalSize;

  const HeaderInfo({
    required this.format,
    required this.headerSize,
    required this.originalSize,
  });
}

/// Stateless encode/decode of the magic-byte headers that prefix every
/// encrypted file. Pure (no I/O except [detectFormatFromFile], which only reads
/// 4 bytes for format sniffing).
class HeaderCodec {
  HeaderCodec._();

  /// Sniff the format from the first bytes of encrypted data.
  /// Returns one of the `kFormat*` constants.
  static int detectFormat(List<int> bytes) {
    if (bytes.length < 4) return kFormatUnknown;
    final magic =
        bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
    if (magic == kMagicGcmV2) return kFormatGcmV2;
    if (magic == kMagicGcmV1) return kFormatGcmV1;
    if (magic == kMagicCtr) return kFormatCtr;
    if (magic == kMagicCbc) return kFormatCbc;
    return kFormatUnknown;
  }

  /// Sniff format by reading only the first 4 bytes of a file.
  static int detectFormatFromFile(String path) {
    try {
      final raf = File(path).openSync();
      final header = raf.readSync(4);
      raf.closeSync();
      return detectFormat(header);
    } catch (_) {
      return kFormatUnknown;
    }
  }

  /// The 4-byte magic prefix for a given format, or null for unknown.
  static Uint8List? magicFor(int format) {
    const prefix = <int>[0x4C, 0x4B, 0x52];
    switch (format) {
      case kFormatGcmV1:
        return Uint8List.fromList([...prefix, 0x47]);
      case kFormatGcmV2:
        return Uint8List.fromList([...prefix, 0x32]);
      case kFormatCtr:
        return Uint8List.fromList([...prefix, 0x53]);
      case kFormatCbc:
        return Uint8List.fromList([...prefix, 0x44]);
      default:
        return null;
    }
  }

  /// Encode the legacy 8-byte stream header: magic(4) + original size(4, LE).
  static Uint8List encodeStreamHeader(int format, int originalSize) {
    final magic = magicFor(format);
    if (magic == null) {
      throw ArgumentError('No magic bytes for format $format');
    }
    final header = Uint8List(kStreamHeaderSize)
      ..setRange(0, 4, magic)
      ..[4] = originalSize & 0xFF
      ..[5] = (originalSize >> 8) & 0xFF
      ..[6] = (originalSize >> 16) & 0xFF
      ..[7] = (originalSize >> 24) & 0xFF;
    return header;
  }

  /// Encode the 9-byte v2 (authenticated) GCM header:
  /// magic(4) + version(1) + original size(4, LE).
  static Uint8List encodeV2Header(int originalSize, {int version = 0x02}) {
    final magic = magicFor(kFormatGcmV2)!;
    return Uint8List(kV2HeaderSize)
      ..setRange(0, 4, magic)
      ..[4] = version
      ..[5] = originalSize & 0xFF
      ..[6] = (originalSize >> 8) & 0xFF
      ..[7] = (originalSize >> 16) & 0xFF
      ..[8] = (originalSize >> 24) & 0xFF;
  }

  /// Decode the size bytes (little-endian) at [offset] for [count] bytes.
  static int decodeLeInt(Uint8List bytes, int offset, int count) {
    int value = 0;
    for (int i = 0; i < count; i++) {
      value |= bytes[offset + i] << (8 * i);
    }
    return value;
  }
}
