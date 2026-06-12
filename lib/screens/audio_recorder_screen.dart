import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/auto_kill_service.dart';
import '../themes/app_colors.dart';
import '../utils/toast_utils.dart';

enum AudioFormat { aac, wav }

class AudioRecorderScreen extends StatefulWidget {
  const AudioRecorderScreen({super.key});

  @override
  State<AudioRecorderScreen> createState() => _AudioRecorderScreenState();
}

class _AudioRecorderScreenState extends State<AudioRecorderScreen>
    with WidgetsBindingObserver {
  static const _recorderChannel =
      MethodChannel('com.mossapps.locker/audio_recorder');
  static const _amplitudeChannel =
      EventChannel('com.mossapps.locker/audio_amplitude');

  final AudioPlayer _player = AudioPlayer();

  bool _hasPermission = false;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isPreviewing = false;

  AudioFormat _format = AudioFormat.aac;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  Timer? _timer;
  double _amplitude = 0.0;
  StreamSubscription? _amplitudeSub;
  StreamSubscription? _positionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _positionSub?.cancel();
    _player.dispose();
    _cleanupTempRecording();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isRecording) {
      _stopRecording();
    }
  }

  Future<void> _checkPermission() async {
    final granted = await AutoKillService.runSafe(() async {
      final status = await Permission.microphone.request();
      return status.isGranted;
    });

    if (!mounted) return;
    setState(() {
      _hasPermission = granted;
    });

    if (!_hasPermission) {
      Navigator.pop(context);
    }
  }

  Future<void> _startRecording() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = _format == AudioFormat.aac ? 'm4a' : 'wav';
      final path = '${appDir.path}/.locker_vault/temp/recording_$timestamp.$ext';

      final dir = Directory('${appDir.path}/.locker_vault/temp');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final formatStr = _format == AudioFormat.aac ? 'aac' : 'wav';
      await _recorderChannel.invokeMethod('startRecording', {
        'path': path,
        'format': formatStr,
      });

      _amplitudeSub = _amplitudeChannel.receiveBroadcastStream().listen((amp) {
        if (mounted && amp is double) {
          setState(() {
            _amplitude = amp.clamp(0.0, 1.0);
          });
        }
      });

      setState(() {
        _isRecording = true;
        _isPaused = false;
        _recordingDuration = Duration.zero;
        _recordingPath = path;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordingDuration += const Duration(seconds: 1);
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('Failed to start recording: $e');
      }
    }
  }

  Future<void> _pauseRecording() async {
    try {
      await _recorderChannel.invokeMethod('pauseRecording');
      _timer?.cancel();
      _amplitudeSub?.cancel();
      setState(() {
        _isPaused = true;
        _amplitude = 0;
      });
    } catch (e) {
      debugPrint('Error pausing recording: $e');
    }
  }

  Future<void> _resumeRecording() async {
    try {
      await _recorderChannel.invokeMethod('resumeRecording');
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordingDuration += const Duration(seconds: 1);
          });
        }
      });
      _amplitudeSub = _amplitudeChannel.receiveBroadcastStream().listen((amp) {
        if (mounted && amp is double) {
          setState(() {
            _amplitude = amp.clamp(0.0, 1.0);
          });
        }
      });
      setState(() {
        _isPaused = false;
      });
    } catch (e) {
      debugPrint('Error resuming recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorderChannel.invokeMethod('stopRecording');
      _timer?.cancel();
      _amplitudeSub?.cancel();
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _amplitude = 0;
        _recordingPath = path as String?;
      });

      if (path != null) {
        await _player.setFilePath(path as String);
        setState(() => _isPreviewing = true);
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('Failed to stop recording: $e');
      }
    }
  }

  Future<void> _togglePreviewPlayback() async {
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        _positionSub?.cancel();
        _positionSub = _player.positionStream.listen((position) {
          final duration = _player.duration ?? Duration.zero;
          if (position >= duration && duration > Duration.zero) {
            _player.seek(Duration.zero);
            _player.pause();
          }
        });
        await _player.seek(Duration.zero);
        await _player.play();
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError('Playback failed: $e');
      }
    }
  }

  void _saveRecording() {
    if (_recordingPath != null) {
      Navigator.pop(context, _recordingPath);
    }
  }

  void _discardRecording() {
    _cleanupTempRecording();
    setState(() {
      _isPreviewing = false;
      _recordingPath = null;
      _recordingDuration = Duration.zero;
    });
  }

  void _retryRecording() {
    _cleanupTempRecording();
    _player.stop();
    _positionSub?.cancel();
    setState(() {
      _isPreviewing = false;
      _recordingPath = null;
      _recordingDuration = Duration.zero;
    });
  }

  void _cleanupTempRecording() {
    if (_recordingPath != null) {
      final file = File(_recordingPath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  void _cancel() {
    if (_isRecording) {
      _recorderChannel.invokeMethod('stopRecording');
      _timer?.cancel();
      _amplitudeSub?.cancel();
    }
    _cleanupTempRecording();
    Navigator.pop(context);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.backgroundColor,
      appBar: AppBar(
        backgroundColor: context.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.textPrimary),
          onPressed: _cancel,
        ),
        title: Text(
          'Record Audio',
          style: TextStyle(
            fontFamily: 'ProductSans',
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              if (!_isPreviewing) ...[
                _buildFormatSelector(),
                const SizedBox(height: 48),
                _buildTimerDisplay(),
                const SizedBox(height: 24),
                _buildAmplitudeIndicator(),
              ] else ...[
                _buildPreviewPanel(),
              ],
              const Spacer(),
              if (!_isPreviewing)
                _buildRecordingControls()
              else
                _buildPreviewActions(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormatSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFormatChip(AudioFormat.aac, 'AAC'),
              _buildFormatChip(AudioFormat.wav, 'WAV'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormatChip(AudioFormat format, String label) {
    final isSelected = _format == format;
    return GestureDetector(
      onTap: _isRecording
          ? null
          : () => setState(() => _format = format),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? context.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : context.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            fontFamily: 'ProductSans',
          ),
        ),
      ),
    );
  }

  Widget _buildTimerDisplay() {
    return Text(
      _formatDuration(_recordingDuration),
      style: TextStyle(
        fontFamily: 'ProductSans',
        fontSize: 56,
        fontWeight: FontWeight.w300,
        color: _isRecording
            ? (_isPaused ? context.textSecondary : context.accentColor)
            : context.textTertiary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _buildAmplitudeIndicator() {
    if (!_isRecording || _isPaused) {
      return const SizedBox(height: 48);
    }

    return SizedBox(
      height: 48,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(32, (i) {
          final barHeight =
              (_amplitude * 40 * (0.5 + 0.5 * (i % 3 == 0 ? 1.0 : 0.6)))
                  .clamp(4.0, 40.0);
          return Container(
            width: 4,
            height: barHeight,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: context.accentColor.withValues(alpha: 0.4 + _amplitude * 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_isRecording) ...[
          SizedBox(
            width: 56,
            height: 56,
            child: IconButton.filled(
              onPressed: _isPaused ? _resumeRecording : _pauseRecording,
              icon: Icon(
                _isPaused ? Icons.play_arrow : Icons.pause,
                size: 28,
              ),
              style: IconButton.styleFrom(
                backgroundColor: context.surfaceColor,
                foregroundColor: context.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 32),
        ],
        GestureDetector(
          onTap: _isRecording ? _stopRecording : _startRecording,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRecording ? Colors.red : context.accentColor,
              boxShadow: [
                BoxShadow(
                  color: (_isRecording ? Colors.red : context.accentColor)
                      .withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              _isRecording ? Icons.stop : Icons.mic,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewPanel() {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: context.accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Icon(
            Icons.music_note,
            size: 56,
            color: context.accentColor,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Recording Ready',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_formatDuration(_recordingDuration)} • ${_format == AudioFormat.aac ? 'AAC' : 'WAV'}',
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontSize: 14,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 32),
        StreamBuilder<bool>(
          stream: _player.playingStream,
          initialData: false,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;
            return Column(
              children: [
                _buildPreviewButton(isPlaying: isPlaying),
                const SizedBox(height: 12),
                Text(
                  isPlaying ? 'Playing...' : 'Tap to preview',
                  style: TextStyle(
                    fontFamily: 'ProductSans',
                    fontSize: 13,
                    color: context.textTertiary,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _buildRetryButton(),
      ],
    );
  }

  Widget _buildRetryButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _retryRecording,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh,
                size: 18,
                color: context.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Retry',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewButton({required bool isPlaying}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _togglePreviewPlayback,
        borderRadius: BorderRadius.circular(48),
        splashColor: Colors.white.withValues(alpha: 0.3),
        highlightColor: Colors.white.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isPlaying)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: context.accentColor.withValues(alpha: 0.35),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.accentColor,
                    boxShadow: [
                      BoxShadow(
                        color: context.accentColor.withValues(alpha: 0.25),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                if (isPlaying)
                  Positioned.fill(
                    child: _PlaybackProgressRing(
                      color: Colors.white.withValues(alpha: 0.6),
                      strokeWidth: 3,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _discardRecording,
            icon: const Icon(Icons.delete_outline),
            label: const Text(
              'Discard',
              style: TextStyle(fontFamily: 'ProductSans', fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: FilledButton.icon(
            onPressed: _saveRecording,
            icon: const Icon(Icons.lock_outline),
            label: const Text(
              'Hide',
              style: TextStyle(fontFamily: 'ProductSans', fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: context.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaybackProgressRing extends StatefulWidget {
  final Color color;
  final double strokeWidth;

  const _PlaybackProgressRing({
    required this.color,
    required this.strokeWidth,
  });

  @override
  State<_PlaybackProgressRing> createState() => _PlaybackProgressRingState();
}

class _PlaybackProgressRingState extends State<_PlaybackProgressRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 2 * 3.141592653589793,
          child: CustomPaint(
            painter: _RingPainter(
              color: widget.color,
              strokeWidth: widget.strokeWidth,
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _RingPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    const sweep = 2.0 * 3.141592653589793;
    const segmentCount = 4;
    const segmentGap = 0.3;
    final segmentLength = (sweep / segmentCount) - segmentGap;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < segmentCount; i++) {
      final startAngle = i * (segmentLength + segmentGap);
      canvas.drawArc(rect, startAngle, segmentLength, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
