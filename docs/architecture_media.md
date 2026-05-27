# Architecture Diagram

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interface                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  VaultOperationProgressDialog                            │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐        │  │
│  │  │ Compress   │→ │  Encrypt   │→ │  Complete  │        │  │
│  │  └────────────┘  └────────────┘  └────────────┘        │  │
│  │  Progress: ████████░░░░░░░░░░ 45%                       │  │
│  │  [Cancel Button]                                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                   ImprovedVaultOperations                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Orchestration Layer                                     │  │
│  │  • Progress callbacks                                    │  │
│  │  • Rollback mechanism                                    │  │
│  │  • Error handling                                        │  │
│  │  • Resource cleanup                                      │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                    ↓                           ↓
    ┌───────────────────────────┐   ┌──────────────────────────┐
    │ ImprovedCompressionService│   │   EncryptionService      │
    │                           │   │                          │
    │  ┌─────────────────────┐ │   │  ┌────────────────────┐ │
    │  │   Main Thread       │ │   │  │   Main Thread      │ │
    │  │  • Task tracking    │ │   │  │  • Key management  │ │
    │  │  • Cancellation     │ │   │  │  • Streaming       │ │
    │  └─────────────────────┘ │   │  └────────────────────┘ │
    │           ↓               │   │           ↓              │
    │  ┌─────────────────────┐ │   │  ┌────────────────────┐ │
    │  │   Background Isolate│ │   │  │   CTR/CBC/GCM Cipher   │ │
    │  │  • FFmpeg process   │ │   │  │  • Chunk streaming │ │
    │  │  • Progress parsing │ │   │  │  • Memory efficient│ │
    │  │  • Auth tag (GCM)  │ │
    │  │  • SendPort comms   │ │   │  └────────────────────┘ │
    │  └─────────────────────┘ │   └──────────────────────────┘
    └───────────────────────────┘
                    ↓
    ┌───────────────────────────┐
    │      FFmpeg Process       │
    │                           │
    │  • Video compression      │
    │  • Stderr output          │
    │  • Progress reporting     │
    └───────────────────────────┘
```

## Data Flow

### Normal Operation Flow

```
1. User selects file
        ↓
2. showVaultOperationProgress()
        ↓
3. ImprovedVaultOperations.addFileToVault()
        ↓
4. [Compression Stage]
   ├─→ Spawn isolate
   ├─→ Start FFmpeg
   ├─→ Parse progress
   ├─→ Update UI (0-100%)
   └─→ Return compressed path
        ↓
5. [Encryption Stage]
   ├─→ Stream file in chunks
   ├─→ Encrypt each chunk
   ├─→ Update UI (0-100%)
   └─→ Write to vault
        ↓
6. [Cleanup Stage]
   ├─→ Delete temp files
   ├─→ Update index
   └─→ Close dialog
        ↓
7. Success!
```

### Cancellation Flow

```
1. User clicks Cancel
        ↓
2. onCancel() callback
        ↓
3. cancelOperation(taskId)
        ↓
4. [Rollback Actions]
   ├─→ Kill isolate
   ├─→ Kill FFmpeg process
   ├─→ Delete compressed temp file
   ├─→ Delete encrypted vault file
   └─→ Close resources
        ↓
5. Return cancelled status
        ↓
6. Show "Operation cancelled" message
```

### Error Flow

```
1. Error occurs (any stage)
        ↓
2. Catch exception
        ↓
3. [Rollback Actions]
   ├─→ Execute rollback stack
   ├─→ Delete temp files
   ├─→ Clean up resources
   └─→ Log error
        ↓
4. Return error result
        ↓
5. Show error message to user
```

## Component Interactions

```
┌──────────────────────────────────────────────────────────────┐
│                      Main Thread                             │
│                                                              │
│  ┌────────────┐    ┌──────────────┐    ┌────────────────┐  │
│  │    UI      │◄───│ VaultService │◄───│  VaultOps      │  │
│  └────────────┘    └──────────────┘    └────────────────┘  │
│        ↑                                        ↑            │
│        │                                        │            │
│        │ Progress                               │ Control    │
│        │ Updates                                │ Messages   │
│        │                                        │            │
└────────┼────────────────────────────────────────┼────────────┘
         │                                        │
         │                                        │
┌────────┼────────────────────────────────────────┼────────────┐
│        │              Isolate                   │            │
│        │                                        │            │
│  ┌─────▼──────┐                          ┌─────▼────────┐  │
│  │ ReceivePort│                          │  SendPort    │  │
│  └────────────┘                          └──────────────┘  │
│        ↑                                        ↓            │
│        │                                        │            │
│        │ Progress                               │ Commands   │
│        │ Messages                               │            │
│        │                                        │            │
│  ┌─────┴──────────────────────────────────────┴─────────┐  │
│  │           Compression Worker                          │  │
│  │  • FFmpeg process management                          │  │
│  │  • Progress parsing                                   │  │
│  │  • Error handling                                     │  │
│  └───────────────────────────────────────────────────────┘  │
│                            ↓                                 │
│                   ┌────────────────┐                         │
│                   │ FFmpeg Process │                         │
│                   └────────────────┘                         │
└──────────────────────────────────────────────────────────────┘
```

## State Machine

```
                    ┌─────────┐
                    │  IDLE   │
                    └────┬────┘
                         │ addFileToVault()
                         ↓
                  ┌──────────────┐
                  │ COMPRESSING  │◄──────┐
                  └──────┬───────┘       │
                         │               │ Retry
                         │ Success       │
                         ↓               │
                  ┌──────────────┐       │
                  │ ENCRYPTING   │───────┘
                  └──────┬───────┘
                         │
                         │ Success
                         ↓
                  ┌──────────────┐
                  │  COMPLETE    │
                  └──────────────┘

Cancel at any stage:
                         │
                         ↓
                  ┌──────────────┐
                  │  CANCELLING  │
                  └──────┬───────┘
                         │
                         ↓
                  ┌──────────────┐
                  │  ROLLING BACK│
                  └──────┬───────┘
                         │
                         ↓
                  ┌──────────────┐
                  │  CANCELLED   │
                  └──────────────┘

Error at any stage:
                         │
                         ↓
                  ┌──────────────┐
                  │    ERROR     │
                  └──────┬───────┘
                         │
                         ↓
                  ┌──────────────┐
                  │  ROLLING BACK│
                  └──────┬───────┘
                         │
                         ↓
                  ┌──────────────┐
                  │    FAILED    │
                  └──────────────┘
```

## Memory Management

```
┌─────────────────────────────────────────────────────────┐
│                    Memory Layout                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Main Thread (Constant ~50MB)                          │
│  ┌───────────────────────────────────────────────┐    │
│  │ UI State, VaultService, Settings              │    │
│  └───────────────────────────────────────────────┘    │
│                                                         │
│  Compression Isolate (Peak ~100MB)                     │
│  ┌───────────────────────────────────────────────┐    │
│  │ FFmpeg buffers, temp data                     │    │
│  │ (Cleaned up after completion)                 │    │
│  └───────────────────────────────────────────────┘    │
│                                                         │
│  Encryption Streaming (Constant ~10MB)                 │
│  ┌───────────────────────────────────────────────┐    │
│  │ 1MB chunk buffer (reused)                     │    │
│  │ Cipher state                                  │    │
│  └───────────────────────────────────────────────┘    │
│                                                         │
│  Total Peak: ~160MB (vs 500MB+ before)                │
└─────────────────────────────────────────────────────────┘
```

## File System Operations

```
Source File
    │
    ↓ [Compression]
Temp Compressed File (/tmp/compressed_xxx.mp4)
    │
    ↓ [Encryption]
Vault File (/vault/images/encrypted_xxx.enc)
    │
    ↓ [Cleanup]
Delete Temp File
    │
    ↓ [Index Update]
Add to vault_file_index

On Cancel/Error:
    │
    ↓ [Rollback]
Delete Temp Compressed File (if exists)
Delete Vault File (if exists)
    │
    ↓ [Complete]
No files left behind
```

## Progress Calculation

### Compression Progress

```
FFmpeg Output:
"frame= 123 fps=30 time=00:00:04.10 bitrate=1234.5kbits/s"
                           ↓
Extract time: 00:00:04.10 = 4.1 seconds
                           ↓
Total duration: 60 seconds (from ffprobe)
                           ↓
Progress: 4.1 / 60 = 0.068 = 6.8%
                           ↓
Update UI: "Compressing video... 7%"
```

### Encryption Progress

For both CTR and GCM modes, progress is tracked by chunk count:

```
File size: 100MB
Chunk size: 1MB
                           ↓
Chunks processed: 45
                           ↓
Progress: 45 / 100 = 0.45 = 45%
                           ↓
Update UI: "Encrypting file... 45%"
```

GCM additionally writes a 16-byte authentication tag at the end of each file for integrity verification on decryption.

## Rollback Stack

```
Operation starts with empty stack:
rollbackActions = []

After compression:
rollbackActions = [
    () => delete(tempCompressedFile)
]

After encryption:
rollbackActions = [
    () => delete(tempCompressedFile),
    () => delete(vaultFile)
]

On cancel/error:
Execute in reverse order:
1. delete(vaultFile)
2. delete(tempCompressedFile)
```

## Thread Safety

```
┌──────────────────────────────────────────────────────┐
│              Thread Safety Mechanisms                │
├──────────────────────────────────────────────────────┤
│                                                      │
│  1. Isolate Communication                           │
│     • SendPort/ReceivePort (message passing)        │
│     • No shared memory                              │
│     • Thread-safe by design                         │
│                                                      │
│  2. Task Tracking                                   │
│     • Map<String, CompressionTask>                  │
│     • Accessed only from main thread                │
│     • No concurrent modifications                   │
│                                                      │
│  3. File Operations                                 │
│     • Unique temp file names (timestamp)            │
│     • No concurrent access to same file             │
│     • Atomic operations where possible              │
│                                                      │
│  4. State Management                                │
│     • Completer for async coordination              │
│     • Single owner per task                         │
│     • Clean lifecycle management                    │
│                                                      │
└──────────────────────────────────────────────────────┘
```

## Performance Characteristics

```
┌─────────────────────────────────────────────────────────┐
│                  Performance Profile                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  File Size: 100MB Video                                │
│                                                         │
│  Compression:  ~30-45 seconds (FFmpeg)                 │
│  Encryption:   ~5-10 seconds (streaming)               │
│  Total:        ~35-55 seconds                          │
│                                                         │
│  Memory:       ~160MB peak                             │
│  CPU:          ~80% (compression), ~30% (encryption)   │
│  Disk I/O:     Sequential reads/writes                 │
│                                                         │
│  UI:           Fully responsive throughout             │
│  Cancellation: <1 second response time                 │
│  Cleanup:      <2 seconds                              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

This architecture provides:
- ✅ Non-blocking operations
- ✅ Real-time progress
- ✅ Instant cancellation
- ✅ Automatic cleanup
- ✅ Memory efficiency
- ✅ Thread safety

---

## Encryption Modes

Latch supports two AES-256 encryption modes, selectable via the Encryption Settings screen:

### AES-256-CTR (Counter Mode)
- **Speed**: Fast, no integrity verification
- **Parallelizable**: Encryption and decryption can be parallelized
- **Magic bytes**: `0x4C4B5253`
- **Use case**: Default mode for performance

### AES-256-GCM (Galois/Counter Mode)
- **Speed**: Slightly slower due to authentication overhead
- **Integrity**: Authenticated encryption with built-in integrity verification
- **Magic bytes**: `0x4C4B5247`
- **Use case**: Recommended for security-sensitive vaults

```
┌──────────────────────────────────────────────────────────────┐
│                     Encryption Flow                          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐                                            │
│  │ Source File  │                                            │
│  └──────┬───────┘                                            │
│         ↓                                                    │
│  ┌──────────────────────────────────────────────────┐       │
│  │              Algorithm Selection                  │       │
│  │  ┌─────────────────┐   ┌─────────────────────┐   │       │
│  │  │   AES-256-CTR   │   │    AES-256-GCM      │   │       │
│  │  │  16-byte IV     │   │   12-byte nonce     │   │       │
│  │  │  No auth tag    │   │   16-byte auth tag  │   │       │
│  │  └────────┬────────┘   └──────────┬──────────┘   │       │
│  └───────────┼───────────────────────┼──────────────┘       │
│              ↓                       ↓                       │
│  ┌─────────────────┐   ┌─────────────────────────┐         │
│  │ Stream encrypt  │   │ Encrypt + auth tag      │         │
│  │ in 1MB chunks   │   │ appended to each file   │         │
│  └────────┬────────┘   └────────────┬────────────┘         │
│           ↓                          ↓                      │
│  ┌────────────────────────────────────────────────┐         │
│  │              Vault Storage                     │         │
│  │  [magic][IV/nonce][ciphertext][auth tag (GCM)]│         │
│  └────────────────────────────────────────────────┘         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## PBKDF2 Key Derivation

All password-based secrets (master key, decoy credentials, PIN/password hashes) use PBKDF2 with SHA-256 for key derivation:

```
User Password/PIN
        │
        ↓
┌──────────────────────────────┐
│  PBKDF2-HMAC-SHA256          │
│  • Iteration count: 100,000  │
│  • Salt: 32-byte random      │
│  • Key length: 32 bytes      │
│  • Configurable iterations   │
└──────────────┬───────────────┘
               ↓
        Derived 256-bit Key
```

### Salt Generation
- Each credential gets a unique 32-byte random salt
- Salt is stored alongside the derived hash for verification
- Prevents rainbow table attacks across vaults

### Legacy Migration
- Pre-PBKDF2 vaults stored passwords using plain SHA-256
- On unlock, legacy hashes are detected and automatically migrated to PBKDF2
- Decoy credentials migrated with separate salted hashing

---

## Re-Encryption (Algorithm Migration)

When the user changes the encryption algorithm (e.g., CTR → GCM), existing vault files are re-encrypted:

```
┌──────────────────────────────────────────────────────────────┐
│                  Re-Encryption Flow                          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Select new algorithm in Encryption Settings              │
│              ↓                                               │
│  2. Decrypt each vault file with old algorithm               │
│              ↓                                               │
│  3. Encrypt plaintext with new algorithm                     │
│              ↓                                               │
│  4. Verify integrity (GCM auth tag validation)              │
│              ↓                                               │
│  5. Replace vault file with new-format file                  │
│              ↓                                               │
│  6. Update vault index metadata                              │
│              ↓                                               │
│  7. Clean up temporary plaintext                             │
│                                                              │
│  Rollback: If any file fails, operation is aborted           │
│  and original files are preserved.                           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### ReEncryptNotifier
- Manages re-encryption state across all vault files
- Provides progress tracking per file
- Reports success, failure, and progress to UI

### Security Guarantees
- Plaintext is never written to persistent storage
- Temporary decrypted data is held in memory only
- On cancellation or failure, the original vault files are untouched
- GCM auth tag validation catches corruption during migration
