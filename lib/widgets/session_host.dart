import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/session_service.dart';

class SessionHost extends StatefulWidget {
  const SessionHost({super.key, required this.session, required this.builder});

  final SessionService session;
  final WidgetBuilder builder;

  @override
  State<SessionHost> createState() => _SessionHostState();
}

class _SessionHostState extends State<SessionHost> with WidgetsBindingObserver {
  TextEditingController? _focusedController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    FocusManager.instance.addListener(_trackTextInput);
  }

  void _trackTextInput() {
    final editable = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    final controller = editable?.widget.controller;
    if (identical(controller, _focusedController)) return;
    _focusedController?.removeListener(_onTextInput);
    _focusedController = controller;
    _focusedController?.addListener(_onTextInput);
  }

  void _onTextInput() => widget.session.recordActivity();

  bool _onKey(KeyEvent event) {
    widget.session.recordActivity();
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.session.handleLifecycle(state);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_trackTextInput);
    _focusedController?.removeListener(_onTextInput);
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => widget.session.recordActivity(),
          onPointerMove: (_) => widget.session.recordActivity(),
          onPointerSignal: (_) => widget.session.recordActivity(),
          child: Stack(
            fit: StackFit.expand,
            textDirection: TextDirection.ltr,
            children: [
              KeyedSubtree(
                key: ValueKey(widget.session.generation),
                child: widget.builder(context),
              ),
              if (widget.session.isObscured)
                const Positioned.fill(
                  child: ColoredBox(color: Color(0xFF1A1A1D)),
                ),
            ],
          ),
        ),
      );
}
