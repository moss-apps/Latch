import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/auto_kill_service.dart';
import '../themes/app_colors.dart';
import 'dart:ui';

enum CameraMode { photo, video }

class CameraScreen extends StatefulWidget {
  final CameraMode initialMode;

  const CameraScreen({
    super.key,
    this.initialMode = CameraMode.photo,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isInitialized = false;
  bool _isRecording = false;
  CameraMode _mode = CameraMode.photo;
  FlashMode _flashMode = FlashMode.off;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;

  // Recording Timer
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;

  // Animation controllers
  late AnimationController _focusAnimationController;
  late Animation<double> _focusAnimation;
  Offset? _focusPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mode = widget.initialMode;
    _focusAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _focusAnimation = Tween<double>(begin: 1.0, end: 0.0)
        .chain(CurveTween(curve: Curves.easeIn))
        .animate(_focusAnimationController);

    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _focusAnimationController.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Check permissions safely (disable auto-kill while dialog is shown)
      Map<Permission, PermissionStatus> statuses =
          await AutoKillService.runSafe(() async {
        return await [
          Permission.camera,
          Permission.microphone,
        ].request();
      });

      if (statuses[Permission.camera] != PermissionStatus.granted) {
        if (mounted) Navigator.pop(context);
        return;
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }

      await _initController(_cameras[_selectedCameraIndex]);
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _initController(CameraDescription description) async {
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.jpeg
          : ImageFormatGroup.bgra8888,
    );

    _controller = controller;

    try {
      await controller.initialize();
      await controller.setFlashMode(_flashMode);

      _maxAvailableZoom = await controller.getMaxZoomLevel();
      _minAvailableZoom = await controller.getMinZoomLevel();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error creating camera controller: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length <= 1) return;

    setState(() {
      _isInitialized = false;
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    });

    await _initController(_cameras[_selectedCameraIndex]);
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;

    FlashMode newMode;
    switch (_flashMode) {
      case FlashMode.off:
        newMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        newMode = FlashMode.always;
        break;
      case FlashMode.always:
        newMode = FlashMode.torch;
        break;
      case FlashMode.torch:
        newMode = FlashMode.off;
        break;
    }

    try {
      await _controller!.setFlashMode(newMode);
      setState(() => _flashMode = newMode);
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      if (_controller!.value.isTakingPicture) return;

      final XFile image = await _controller!.takePicture();
      if (mounted) {
        Navigator.pop(context, image.path);
      }
    } catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isRecordingVideo) return;

    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      _startTimer();
    } catch (e) {
      debugPrint('Error starting video recording: $e');
    }
  }

  void _startTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration += const Duration(seconds: 1);
      });
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _stopRecording() async {
    if (_controller == null || !_controller!.value.isRecordingVideo) return;

    try {
      final XFile video = await _controller!.stopVideoRecording();
      _recordingTimer?.cancel();
      setState(() => _isRecording = false);
      if (mounted) {
        Navigator.pop(context, video.path);
      }
    } catch (e) {
      debugPrint('Error stopping video recording: $e');
    }
  }

  void _onTapFocus(TapDownDetails details, BoxConstraints constraints) {
    if (_controller == null || !_isInitialized) return;

    final offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );

    try {
      _controller!.setFocusPoint(offset);
      _controller!.setExposurePoint(offset);

      setState(() {
        _focusPoint = details.localPosition;
      });
      _focusAnimationController.forward(from: 0.0);
    } catch (e) {
      debugPrint('Error setting focus: $e');
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null || !_isInitialized) return;

    _currentScale = (_baseScale * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom);

    await _controller!.setZoomLevel(_currentScale);
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onTapDown: (details) => _onTapFocus(details, constraints),
                child: Center(
                  child: CameraPreview(_controller!),
                ),
              );
            },
          ),

          // Focus Indicator
          if (_focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 30,
              top: _focusPoint!.dy - 30,
              child: IgnorePointer(
                child: AnimatedBuilder(
                    animation: _focusAnimationController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _focusAnimation.value,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.yellow, width: 2),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }),
              ),
            ),

          // Top Control Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      icon: Icon(_getFlashIcon(), color: Colors.white),
                      onPressed: _toggleFlash,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Control Bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: EdgeInsets.only(
                    top: 24,
                    bottom: MediaQuery.of(context).padding.bottom + 24,
                    left: 24,
                    right: 24,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.black.withValues(alpha: 0.4),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Mode Selector
                      if (!_isRecording)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildModeButton(CameraMode.photo, 'PHOTO'),
                              _buildModeButton(CameraMode.video, 'VIDEO'),
                            ],
                          ),
                        ),

                      const SizedBox(height: 32),

                      // Camera Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Gallery placeholder (or empty spacing)
                          const SizedBox(width: 48, height: 48),

                          // Shutter Button
                          GestureDetector(
                            onTap: _mode == CameraMode.photo
                                ? _capturePhoto
                                : (_isRecording
                                    ? _stopRecording
                                    : _startRecording),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 4,
                                ),
                                color: _mode == CameraMode.video
                                    ? (_isRecording ? Colors.red : Colors.white)
                                    : Colors.white,
                              ),
                              child: _isRecording
                                  ? Center(
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ),

                          // Switch Camera
                          IconButton(
                            icon: const Icon(Icons.flip_camera_ios,
                                color: Colors.white, size: 30),
                            onPressed: _switchCamera,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_isRecording)
                        Text(
                          _formatDuration(_recordingDuration),
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            fontFamily: 'GoogleSansFlex',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(CameraMode mode, String label) {
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () async {
        if (!isSelected) {
          setState(() => _mode = mode);
          // When switching modes, ensure not recording
          if (_isRecording) {
            await _stopRecording();
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            fontFamily: 'GoogleSansFlex',
          ),
        ),
      ),
    );
  }
}
