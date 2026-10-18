import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/operation_provider.dart';
import '../services/operation_controller.dart';
import '../themes/app_colors.dart';
import 'operation_progress_sheet.dart';

/// App-wide presentation. Only this host owns/removes the progress sheet route.
class OperationProgressHost extends ConsumerStatefulWidget {
  const OperationProgressHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<OperationProgressHost> createState() =>
      _OperationProgressHostState();
}

class _OperationProgressHostState extends ConsumerState<OperationProgressHost> {
  static const _motionDuration = Duration(milliseconds: 240);
  static const _motionCurve = Curves.easeOutCubic;

  late final OperationController _controller;
  ModalBottomSheetRoute<void>? _sheet;
  bool _syncScheduled = false;
  int? _positionId;
  Offset? _position;
  Size _floatingSize = const Size(220, 64);
  final _floatingKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = ref.read(operationControllerProvider);
    _controller.addListener(_scheduleSheetSync);
    _scheduleSheetSync();
  }

  void _scheduleSheetSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _syncSheet();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _syncSheet() {
    final showSheet = _controller.type != null &&
        _controller.presentation == OperationPresentation.sheet;
    if (!showSheet) {
      final sheet = _sheet;
      _sheet = null;
      if (sheet?.isActive == true) sheet!.navigator?.removeRoute(sheet);
      return;
    }
    if (_sheet != null) return;
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    final id = _controller.id;
    final sheet = _sheet = ModalBottomSheetRoute<void>(
      settings: const RouteSettings(name: 'operation-progress'),
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      modalBarrierColor: Colors.black54,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (context) => ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final state = _controller.progress;
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _controller.minimize();
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.9,
              ),
              child: SingleChildScrollView(
                child: OperationProgressSheet(
                  operationType: _controller.type ?? OperationType.hide,
                  totalFiles: state.totalFiles,
                  currentFile: state.currentFile,
                  currentFileName: state.currentFileName,
                  totalSizeBytes: state.totalSizeBytes,
                  processedSizeBytes: state.processedSizeBytes,
                  statusMessage: state.statusMessage,
                  isProcessing: state.isProcessing,
                  isComplete: state.isComplete,
                  isEncrypting: state.isEncrypting,
                  outcome: _controller.outcome,
                  onMinimize: _controller.minimize,
                  onDone: _controller.dismiss,
                ),
              ),
            ),
          );
        },
      ),
    );
    navigator.push(sheet).then((_) {
      if (!mounted || !identical(_sheet, sheet)) return;
      _sheet = null;
      if (_controller.id == id) _controller.minimize();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_scheduleSheetSync);
    // The session's navigator disposes its routes with this host. Never pop a
    // route through a context that may now belong to another screen/session.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final observer = ref.watch(operationNavigatorObserverProvider);
    // MaterialApp.builder sits above its Navigator's overlay. Supply an outer
    // overlay for the floating controls' tooltips without making them modal.
    return Overlay.wrap(
        child: ListenableBuilder(
      listenable: Listenable.merge([_controller, observer.popupVisible]),
      child: widget.child,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child!,
          if (_controller.type != null &&
              _controller.presentation != OperationPresentation.sheet &&
              !observer.popupVisible.value)
            Positioned.fill(
              child: LayoutBuilder(builder: _buildFloating),
            ),
        ],
      ),
    ));
  }

  Widget _buildFloating(BuildContext context, BoxConstraints constraints) {
    final media = MediaQuery.of(context);
    final panel = _controller.presentation == OperationPresentation.panel;
    final left = media.padding.left + 12;
    final top = media.padding.top + 12;
    final right = media.padding.right + 12;
    // Clear both the capsule navigation bar and ordinary completion toasts.
    final bottom =
        math.max(media.padding.bottom, media.viewInsets.bottom) + 112;
    final width = math.min(panel ? 340.0 : 220.0,
        math.max(0.0, constraints.maxWidth - left - right));
    final maxHeight = math.max(0.0, constraints.maxHeight - top - bottom);
    final height = math.min(_floatingSize.height, maxHeight);
    final maxLeft = math.max(left, constraints.maxWidth - right - width);
    final maxTop = math.max(top, constraints.maxHeight - bottom - height);
    if (_positionId != _controller.id) {
      _positionId = _controller.id;
      _position = null;
    }
    Offset clamp(Offset point) => Offset(
          point.dx.clamp(left, maxLeft),
          point.dy.clamp(top, maxTop),
        );
    final position = clamp(_position ?? Offset(maxLeft, maxTop));
    void drag(DragUpdateDetails details) {
      setState(
          () => _position = clamp((_position ?? position) + details.delta));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _floatingKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize && box.size != _floatingSize) {
        setState(() => _floatingSize = box.size);
      }
    });

    return Stack(
      children: [
        Positioned(
          left: position.dx,
          top: position.dy,
          child: AnimatedSize(
            duration: _motionDuration,
            curve: _motionCurve,
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              key: _floatingKey,
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: panel ? 16 : 32),
                duration: _motionDuration,
                curve: _motionCurve,
                builder: (context, radius, child) => Material(
                  color: context.backgroundColor,
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(radius),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
                child: AnimatedSwitcher(
                  duration: _motionDuration,
                  switchInCurve: _motionCurve,
                  switchOutCurve: Curves.easeIn,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.topLeft,
                    children: [
                      // Outgoing states stay positioned so the stack is sized
                      // by the incoming state and AnimatedSize can animate
                      // between the pill and the panel without a jump.
                      for (final child in previousChildren)
                        Positioned(top: 0, left: 0, child: child),
                      if (currentChild != null) currentChild,
                    ],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: SizedBox(
                    key: ValueKey(panel ? 'operation-panel' : 'operation-pill'),
                    width: width,
                    child: panel ? _buildPanel(drag) : _buildPill(drag),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String get _resultLabel => switch (_controller.outcome?.kind) {
        OperationOutcomeKind.error => 'Failed',
        OperationOutcomeKind.warning => 'Review',
        _ => 'Done',
      };

  IconData get _resultIcon => switch (_controller.outcome?.kind) {
        OperationOutcomeKind.error => Icons.error_outline,
        OperationOutcomeKind.warning => Icons.warning_amber_rounded,
        _ => Icons.check_circle_outline,
      };

  Widget _buildPill(GestureDragUpdateCallback drag) {
    final progress = _controller.progress;
    final label = _controller.type!.shortLabel;
    final percentage = '${(progress.fraction * 100).toInt()}%';
    final progressLabel = progress.totalFiles > 0 || progress.totalSizeBytes > 0
        ? percentage
        : 'Working';
    return Semantics(
      button: true,
      label: _controller.isRunning
          ? '$label, $progressLabel. Expand progress'
          : '$_resultLabel. Expand operation result',
      onTap: _controller.expand,
      child: Tooltip(
        message: 'Tap to expand. Double-tap to restore the bottom sheet.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _controller.expand,
          onDoubleTap: _controller.restore,
          onPanUpdate: drag,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: _controller.isRunning
                      ? CircularProgressIndicator(
                          value: progress.totalSizeBytes > 0 ||
                                  progress.currentFile > 0
                              ? progress.fraction
                              : null,
                          strokeWidth: 2.5,
                          color: context.accentColor,
                        )
                      : Icon(_resultIcon, color: context.accentColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'GoogleSansFlex',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _controller.isRunning ? progressLabel : _resultLabel,
                  style: TextStyle(
                    fontFamily: 'GoogleSansFlex',
                    fontSize: 14,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(GestureDragUpdateCallback drag) {
    final state = _controller.progress;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: drag,
              onDoubleTap: _controller.restore,
              child: Row(
                children: [
                  Icon(Icons.drag_indicator, color: context.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _controller.type!.title,
                      style: TextStyle(
                        fontFamily: 'GoogleSansFlex',
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Collapse progress',
                    onPressed: _controller.minimize,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_controller.isRunning) ...[
              Text(
                state.totalFiles > 0
                    ? '${state.currentFile} of ${state.totalFiles} files · ${(state.fraction * 100).toInt()}%'
                    : 'Working on files...',
                style: TextStyle(color: context.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: state.totalFiles > 0 || state.totalSizeBytes > 0
                    ? state.fraction
                    : null,
                color: context.accentColor,
                backgroundColor: context.dividerColor,
                borderRadius: BorderRadius.circular(4),
                minHeight: 6,
              ),
              if (state.currentFileName.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  state.currentFileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                ),
              ],
            ],
            const SizedBox(height: 8),
            Semantics(
              liveRegion: !_controller.isRunning,
              child: Text(
                state.statusMessage,
                style: TextStyle(color: context.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (_controller.isRunning)
                  const OperationCancelButton(compact: true)
                else
                  FilledButton(
                    onPressed: _controller.dismiss,
                    child: const Text('Dismiss'),
                  ),
                TextButton.icon(
                  onPressed: _controller.restore,
                  icon: const Icon(Icons.open_in_full, size: 18),
                  label: const Text('Restore'),
                ),
              ],
            ),
            if (_controller.isRunning) ...[
              const SizedBox(height: 8),
              Text(
                'Cancellation is not supported safely for this operation.',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
