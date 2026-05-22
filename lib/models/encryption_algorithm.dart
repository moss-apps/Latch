enum EncryptionAlgorithm {
  aes256Ctr,
  aes256Gcm;

  String get displayName {
    switch (this) {
      case EncryptionAlgorithm.aes256Ctr:
        return 'AES-256-CTR';
      case EncryptionAlgorithm.aes256Gcm:
        return 'AES-256-GCM';
    }
  }

  String get description {
    switch (this) {
      case EncryptionAlgorithm.aes256Ctr:
        return 'Fast, no integrity verification';
      case EncryptionAlgorithm.aes256Gcm:
        return 'Authenticated encryption with integrity check';
    }
  }
}