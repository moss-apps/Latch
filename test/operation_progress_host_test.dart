import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/providers/operation_provider.dart';
import 'package:locker/services/file_operation_gate.dart';
import 'package:locker/services/operation_controller.dart';
import 'package:locker/widgets/operation_progress_host.dart';
import 'package:locker/widgets/operation_progress_sheet.dart';

void main() {
  final pill = find.byKey(const ValueKey('operation-pill'));
  final panel = find.byKey(const ValueKey('operation-panel'));
  late OperationController controller;
  late Completer<OperationOutcome> done;
  late OperationJob lastJob;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    controller = OperationController(gate: FileOperationGate());
    done = Completer<OperationOutcome>();
    navigatorKey = GlobalKey<NavigatorState>();
  });
  tearDown(() {
    controller.dispose();
    if (!done.isCompleted) {
      done.complete(const OperationOutcome(message: 'Done'));
    }
  });

  Future<void> frames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(); // Mount routes before advancing their entrance ticker.
    await tester.pump(const Duration(milliseconds: 400));
    // A tap on the pill waits out the double-tap recognizer before expanding,
    // so give the pill/panel cross-fade its own frame budget to settle too.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> pumpApp(WidgetTester tester,
      {double textScale = 1, Brightness brightness = Brightness.light}) async {
    done = Completer<
        OperationOutcome>(); // Create futures inside the widget clock's zone.
    await tester.pumpWidget(ProviderScope(
      overrides: [operationControllerProvider.overrideWithValue(controller)],
      child: Consumer(
          builder: (context, ref, _) => MaterialApp(
                navigatorKey: navigatorKey,
                navigatorObservers: [
                  ref.watch(operationNavigatorObserverProvider)
                ],
                theme: ThemeData(brightness: brightness, useMaterial3: true),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: OperationProgressHost(
                      navigatorKey: navigatorKey, child: child!),
                ),
                home: Scaffold(
                    body: Center(
                        child: TextButton(
                  onPressed: () =>
                      navigatorKey.currentState!.push(MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                        body: Center(child: Text('Another screen'))),
                  )),
                  child: const Text('Navigate'),
                ))),
              )),
    ));
    controller.start(
      type: OperationType.hide,
      initialProgress: const OperationProgressState(
          totalFiles: 3,
          totalSizeBytes: 1000,
          processedSizeBytes: 500,
          currentFileName: 'large-video.mp4',
          statusMessage: 'Copying large-video.mp4...'),
      task: (job) {
        lastJob = job;
        return done.future;
      },
    );
    await frames(tester);
  }

  Future<void> minimize(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Minimize'));
    await tester.tap(find.text('Minimize'));
    await frames(tester);
    expect(find.byType(OperationProgressSheet), findsNothing);
    expect(pill, findsOneWidget);
  }

  testWidgets('Cancel is red with white text and remains honestly disabled',
      (tester) async {
    await pumpApp(tester);
    final button = tester.widget<FilledButton>(find.descendant(
        of: find.byType(OperationCancelButton),
        matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull);
    expect(button.style!.backgroundColor!.resolve({}), const Color(0xFFB3261E));
    expect(button.style!.foregroundColor!.resolve({}), Colors.white);
    expect(button.style!.backgroundColor!.resolve({WidgetState.disabled}),
        const Color(0xFF8C4542));
    expect(tester.widget<Text>(find.text('Cancel')).style!.color, Colors.white);
    expect(find.textContaining('cannot be cancelled safely'), findsOneWidget);
    await minimize(tester);
  });

  testWidgets(
      'single tap expands, collapse returns to pill, double tap restores sheet',
      (tester) async {
    await pumpApp(tester);
    await minimize(tester);
    expect(find.text('50%'), findsOneWidget);
    await tester.tap(pill);
    await frames(tester);
    expect(panel, findsOneWidget);
    expect(find.text('large-video.mp4'), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse progress'));
    await frames(tester);
    expect(pill, findsOneWidget);
    await tester.tap(pill);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(pill);
    await frames(tester);
    expect(find.byType(OperationProgressSheet), findsOneWidget);
    expect(pill, findsNothing);
    expect(controller.isRunning, isTrue);
    await minimize(tester);
    await tester.tap(pill);
    await frames(tester);
    await tester.tap(find.text('Restore'));
    await frames(tester);
    expect(find.byType(OperationProgressSheet), findsOneWidget);
  });

  testWidgets(
      'completion after navigation never pops the current screen or reopens the sheet',
      (tester) async {
    await pumpApp(tester);
    await minimize(tester);
    await tester.tap(find.text('Navigate'));
    await frames(tester);
    expect(find.text('Another screen'), findsOneWidget);
    expect(pill, findsOneWidget);
    done.complete(const OperationOutcome(
        kind: OperationOutcomeKind.warning,
        message: 'Imported 2 · 1 original retained',
        processedFiles: 2));
    await frames(tester);
    expect(find.text('Another screen'), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isTrue);
    expect(find.byType(OperationProgressSheet), findsNothing);
    expect(find.text('Review'), findsOneWidget);
    await tester.tap(pill);
    await frames(tester);
    expect(find.text('Imported 2 · 1 original retained'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await frames(tester);
    expect(panel, findsNothing);
    expect(find.text('Another screen'), findsOneWidget);
  });

  testWidgets(
      'floating progress stays below unrelated dialogs and resumes afterwards',
      (tester) async {
    await pumpApp(tester);
    await minimize(tester);
    final dialog = showDialog<void>(
        context: navigatorKey.currentState!.overlay!.context,
        builder: (context) =>
            AlertDialog(title: const Text('Confirmation'), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close dialog')),
            ]));
    await frames(tester);
    expect(pill, findsNothing);
    expect(find.text('Confirmation'), findsOneWidget);
    await tester.tap(find.text('Close dialog'));
    await frames(tester);
    await dialog;
    expect(pill, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dragging remains within safe screen bounds and clears bottom navigation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    await minimize(tester);
    expect(tester.getRect(pill).bottom, lessThanOrEqualTo(844 - 112));
    await tester.drag(pill, const Offset(-2000, -2000));
    await frames(tester);
    expect(tester.getRect(pill).left, greaterThanOrEqualTo(12));
    expect(tester.getRect(pill).top, greaterThanOrEqualTo(12));
    await tester.drag(pill, const Offset(4000, 4000));
    await frames(tester);
    expect(tester.getRect(pill).right, lessThanOrEqualTo(390 - 12));
    expect(tester.getRect(pill).bottom, lessThanOrEqualTo(844 - 112));
  });

  for (final configuration in [
    (size: const Size(320, 568), scale: 2.0, brightness: Brightness.dark),
    (size: const Size(1200, 800), scale: 1.0, brightness: Brightness.light),
  ]) {
    testWidgets(
        'sheet and floating panel fit ${configuration.size} at ${configuration.scale}x text',
        (tester) async {
      tester.view.physicalSize = configuration.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpApp(tester,
          textScale: configuration.scale, brightness: configuration.brightness);
      expect(tester.takeException(), isNull);
      await minimize(tester);
      await tester.tap(pill);
      await frames(tester);
      expect(panel, findsOneWidget);
      expect(tester.getRect(panel).bottom,
          lessThanOrEqualTo(configuration.size.height - 112));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Restore'));
      await tester.tap(find.text('Restore'));
      await frames(tester);
      expect(find.byType(OperationProgressSheet), findsOneWidget);
      done.complete(const OperationOutcome(
          kind: OperationOutcomeKind.error,
          message: 'Import failed. Originals were kept.'));
      await frames(tester);
      expect(find.text('Operation failed'), findsOneWidget);
      expect(find.text('Completed successfully'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'system Back minimizes instead of cancelling or popping the source route',
      (tester) async {
    await pumpApp(tester);
    await navigatorKey.currentState!.maybePop();
    await frames(tester);
    expect(pill, findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
    expect(controller.isRunning, isTrue);
  });

  testWidgets('enlarged panel cancel matches the Dismiss button size',
      (tester) async {
    await pumpApp(tester);
    await minimize(tester);
    await tester.tap(pill);
    await frames(tester);
    expect(find.text('Cancel'), findsOneWidget);
    final cancel = tester.getSize(find.descendant(
        of: find.byType(OperationCancelButton),
        matching: find.byType(FilledButton)));
    done.complete(const OperationOutcome(message: 'Done'));
    await frames(tester);
    final dismiss =
        tester.getSize(find.widgetWithText(FilledButton, 'Dismiss'));
    expect(cancel.height, dismiss.height);
  });

  testWidgets('finalizing keeps the last file name above the actions',
      (tester) async {
    await pumpApp(tester);
    await minimize(tester);
    await tester.tap(pill);
    await frames(tester);
    lastJob.batchProgress(2, 3,
        currentSize: 700, totalSize: 1000, currentFileName: 'third.mov');
    lastJob.batchProgress(3, 3,
        currentSize: 1000, totalSize: 1000, currentFileName: 'third.mov');
    await frames(tester);
    expect(find.text('Finalizing...'), findsOneWidget);
    expect(find.text('third.mov'), findsOneWidget);
  });
}
