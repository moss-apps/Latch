import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/screens/desktop_backup_screen.dart';
import 'package:locker/screens/restore_setup_screen.dart';
import 'package:locker/widgets/pairing_qr_scanner.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

const _manualLabel = 'Type the address and code instead';
const _previewKey = Key('fake-camera-preview');

class _FakeScannerPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  StartOptions? lastStartOptions;
  MobileScannerException? startError;
  int disposeCalls = 0;

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Widget buildCameraView() => const ColoredBox(
        key: _previewKey,
        color: Colors.black,
      );

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    lastStartOptions = startOptions;
    if (startError case final error?) throw error;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(1080, 1920),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

void main() {
  late MobileScannerPlatform originalPlatform;
  late _FakeScannerPlatform platform;

  setUp(() {
    originalPlatform = MobileScannerPlatform.instance;
    platform = _FakeScannerPlatform();
    MobileScannerPlatform.instance = platform;
    MobileScannerController.resetPlatformSessionOwner();
  });

  tearDown(() async {
    await platform.captures.close();
    MobileScannerPlatform.instance = originalPlatform;
    MobileScannerController.resetPlatformSessionOwner();
  });

  void setWindow(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<void> pumpScanner(
    WidgetTester tester, {
    double textScale = 1,
    VoidCallback? onManual,
    void Function(BarcodeCapture)? onDetect,
  }) async {
    final controller = MobileScannerController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(title: const Text('Desktop Backup')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: PairingQrScanner(
                controller: controller,
                onDetect: onDetect ?? (_) {},
                onManual: onManual ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('camera expands with available height, not a fixed 240px box',
      (tester) async {
    setWindow(tester, const Size(400, 800));
    await pumpScanner(tester);

    final initialHeight = tester.getSize(find.byType(MobileScanner)).height;
    expect(initialHeight, greaterThan(480));
    expect(find.text(_manualLabel).hitTestable(), findsOneWidget);
    expect(
      tester.getRect(find.widgetWithText(TextButton, _manualLabel)).bottom,
      lessThanOrEqualTo(768),
    );

    tester.view.physicalSize = const Size(400, 1000);
    await tester.pumpAndSettle();

    final tallerHeight = tester.getSize(find.byType(MobileScanner)).height;
    expect(tallerHeight - initialHeight, closeTo(200, 1));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, closeTo(0, 1));
    expect(tester.takeException(), isNull);
  });

  for (final window in [
    (name: 'small portrait', size: const Size(360, 640), textScale: 1.0),
    (name: 'landscape', size: const Size(844, 390), textScale: 1.0),
    (name: 'tablet', size: const Size(900, 1200), textScale: 1.0),
    (name: 'large text', size: const Size(320, 480), textScale: 2.0),
  ]) {
    testWidgets('${window.name}: full frame and reachable manual fallback',
        (tester) async {
      setWindow(tester, window.size);
      var manualCalls = 0;
      await pumpScanner(
        tester,
        textScale: window.textScale,
        onManual: () => manualCalls++,
      );

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      expect(scanner.fit, BoxFit.contain);
      expect(scanner.scanWindow, isNull);
      final viewport = tester.getRect(find.byType(MobileScanner));
      expect(viewport.height, greaterThanOrEqualTo(240));
      final preview = tester.getRect(find.byKey(_previewKey));
      expect(preview.left, greaterThanOrEqualTo(viewport.left - 1));
      expect(preview.top, greaterThanOrEqualTo(viewport.top - 1));
      expect(preview.right, lessThanOrEqualTo(viewport.right + 1));
      expect(preview.bottom, lessThanOrEqualTo(viewport.bottom + 1));

      final manualButton = find.widgetWithText(TextButton, _manualLabel);
      await tester.ensureVisible(manualButton);
      await tester.pumpAndSettle();
      expect(tester.getSize(manualButton).height, greaterThanOrEqualTo(48));
      await tester.tap(manualButton);
      expect(manualCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scanner and manual action stay inside system safe areas',
      (tester) async {
    setWindow(tester, const Size(400, 800));
    tester.view.padding = const FakeViewPadding(
      top: 24,
      bottom: 24,
      left: 16,
      right: 16,
    );
    addTearDown(tester.view.resetPadding);
    await pumpScanner(tester);

    final viewport = tester.getRect(find.byType(MobileScanner));
    expect(viewport.left, greaterThanOrEqualTo(36));
    expect(viewport.right, lessThanOrEqualTo(364));
    final manualButton = find.widgetWithText(TextButton, _manualLabel);
    expect(tester.getRect(manualButton).bottom, lessThanOrEqualTo(776));
    expect(manualButton.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detected QR captures still reach the pairing callback',
      (tester) async {
    final detected = <BarcodeCapture>[];
    await pumpScanner(tester, onDetect: detected.add);
    const capture = BarcodeCapture(
      barcodes: [Barcode(rawValue: 'http://192.168.1.2:8080/#code=123456')],
    );

    platform.captures.add(capture);
    await tester.pump();

    expect(detected, [capture]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera errors retain a usable fallback with large text',
      (tester) async {
    setWindow(tester, const Size(320, 480));
    platform.startError = const MobileScannerException(
      errorCode: MobileScannerErrorCode.permissionDenied,
    );
    var manualCalls = 0;
    await pumpScanner(
      tester,
      textScale: 2,
      onManual: () => manualCalls++,
    );

    expect(find.text('Camera unavailable (permissionDenied).'), findsOneWidget);
    final manualButton = find.widgetWithText(TextButton, _manualLabel).last;
    await tester.ensureVisible(manualButton);
    await tester.pumpAndSettle();
    await tester.tap(manualButton);
    expect(manualCalls, 1);
    expect(tester.takeException(), isNull);
  });

  for (final flow in [
    (
      name: 'desktop backup',
      screen: const DesktopBackupScreen(),
      action: 'Scan the QR code',
    ),
    (
      name: 'existing-vault restore',
      screen: const DesktopBackupScreen(),
      action: 'Restore from this computer',
    ),
    (
      name: 'fresh-install restore',
      screen: const RestoreSetupScreen(),
      action: 'Scan the QR code',
    ),
  ]) {
    testWidgets('${flow.name} uses the tall QR scanner and releases the camera',
        (tester) async {
      setWindow(tester, const Size(400, 900));
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(home: flow.screen)),
      );
      await tester.ensureVisible(find.text(flow.action));
      await tester.tap(find.text(flow.action));
      await tester.pumpAndSettle();

      expect(find.byType(PairingQrScanner), findsOneWidget);
      expect(
          tester.getSize(find.byType(MobileScanner)).height, greaterThan(500));
      expect(platform.lastStartOptions!.autoZoom, isTrue);
      expect(platform.lastStartOptions!.formats, [BarcodeFormat.qrCode]);
      expect(
          platform.lastStartOptions!.cameraResolution, const Size(1920, 1080));

      await tester.tap(find.text(_manualLabel));
      await tester.pumpAndSettle();
      expect(find.byType(MobileScanner), findsNothing);
      expect(find.widgetWithText(TextField, 'Address'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Pairing code'), findsOneWidget);
      expect(platform.disposeCalls, 1);

      await tester.tap(find.text('Scan the QR code instead'));
      await tester.pumpAndSettle();
      expect(find.byType(PairingQrScanner), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(platform.disposeCalls, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
