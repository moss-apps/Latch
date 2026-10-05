import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/vault_settings.dart';
import 'package:locker/services/session_service.dart';
import 'package:locker/utils/navigator_key.dart';
import 'package:locker/widgets/session_host.dart';

void main() {
  test('manual lock gates immediately and waits for cleanup before auth',
      () async {
    final cleanup = Completer<void>();
    var calls = 0;
    final session = SessionService(onLock: () {
      calls++;
      return cleanup.future;
    });
    addTearDown(session.dispose);
    session.unlock();
    final generation = session.generation;
    final locking = session.lock();
    expect(session.isUnlocked, false);
    expect(session.generation, greaterThan(generation));
    expect(calls, 1);
    expect(identical(session.lock(), locking), true);
    var ready = false;
    session.readyToAuthenticate.then((_) => ready = true);
    await Future<void>.delayed(Duration.zero);
    expect(ready, false);
    cleanup.complete();
    await locking;
    expect(ready, true);
  });

  testWidgets('inactivity timer resets with activity and locks at the deadline',
      (tester) async {
    final session = SessionService(now: tester.binding.clock.now);
    addTearDown(session.dispose);
    session.configure(const VaultSettings(
        inactivityLockSeconds: 30, backgroundLockDelaySeconds: -1));
    session.unlock();
    await tester.pump(const Duration(seconds: 20));
    session.recordActivity();
    await tester.pump(const Duration(seconds: 29));
    expect(session.isUnlocked, true);
    await tester.pump(const Duration(seconds: 1));
    expect(session.isUnlocked, false);
  });

  test('failed cleanup blocks unlocking until a successful retry', () async {
    var fail = true;
    final session = SessionService(onLock: () async {
      if (fail) throw StateError('temporary content is still present');
    });
    addTearDown(session.dispose);
    session.unlock();
    await expectLater(session.lock(), throwsStateError);
    expect(session.unlock, throwsStateError);
    fail = false;
    await session.retryCleanup();
    session.unlock();
    expect(session.isUnlocked, true);
  });

  test('manual lock revokes outstanding exemptions before the next session',
      () async {
    final session = SessionService();
    addTearDown(session.dispose);
    session.unlock();
    final interaction = session.beginSystemInteraction(waitForResume: true);
    await session.lock();
    await interaction.released;
    expect(session.hasSystemInteraction, false);
    session.unlock();
    interaction.complete();
    session.handleLifecycle(AppLifecycleState.paused);
    expect(session.isUnlocked, false);
    await session.readyToAuthenticate;
  });

  test('immediate background lock ignores transient inactive state', () async {
    final session = SessionService();
    addTearDown(session.dispose);
    session.unlock();
    session.handleLifecycle(AppLifecycleState.inactive);
    expect(session.isUnlocked, true);
    expect(session.isObscured, true);
    session.handleLifecycle(AppLifecycleState.paused);
    expect(session.isUnlocked, false);
    await session.readyToAuthenticate;
  });

  test('foreground checks wall time even when background timers did not run',
      () {
    var now = DateTime(2026);
    final session = SessionService(now: () => now);
    addTearDown(session.dispose);
    session.configure(const VaultSettings(
        inactivityLockSeconds: 0, backgroundLockDelaySeconds: 30));
    session.unlock();
    session.handleLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 29));
    session.handleLifecycle(AppLifecycleState.resumed);
    expect(session.isUnlocked, true);
    session.handleLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 30));
    session.handleLifecycle(AppLifecycleState.resumed);
    expect(session.isUnlocked, false);
    expect(session.isObscured, false);
  });

  test('background never does not disable the inactivity deadline', () {
    var now = DateTime(2026);
    final session = SessionService(now: () => now);
    addTearDown(session.dispose);
    session.configure(const VaultSettings(
        inactivityLockSeconds: 60, backgroundLockDelaySeconds: -1));
    session.unlock();
    session.handleLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    session.handleLifecycle(AppLifecycleState.resumed);
    expect(session.isUnlocked, false);
  });

  testWidgets('both never settings keep the session unlocked', (tester) async {
    final session = SessionService(now: tester.binding.clock.now);
    addTearDown(session.dispose);
    session.configure(const VaultSettings(
        inactivityLockSeconds: 0, backgroundLockDelaySeconds: -1));
    session.unlock();
    session.handleLifecycle(AppLifecycleState.paused);
    await tester.pump(const Duration(hours: 24));
    session.handleLifecycle(AppLifecycleState.resumed);
    expect(session.isUnlocked, true);
  });

  testWidgets('picker exemption lasts until return and restarts inactivity',
      (tester) async {
    final session = SessionService(now: tester.binding.clock.now);
    addTearDown(session.dispose);
    session.configure(const VaultSettings(inactivityLockSeconds: 30));
    session.unlock();
    await tester.pump(const Duration(seconds: 25));
    final picker = session.beginSystemInteraction();
    session.handleLifecycle(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 10));
    picker.complete();
    expect(session.hasSystemInteraction, true);
    expect(session.isUnlocked, true);
    session.handleLifecycle(AppLifecycleState.resumed);
    await picker.released;
    expect(session.hasSystemInteraction, false);
    await tester.pump(const Duration(seconds: 29));
    expect(session.isUnlocked, true);
    await tester.pump(const Duration(seconds: 1));
    expect(session.isUnlocked, false);
  });

  testWidgets('early-return external launch stays exempt for the round trip',
      (tester) async {
    final session = SessionService(now: tester.binding.clock.now);
    addTearDown(session.dispose);
    session.unlock();
    final intent = session.beginSystemInteraction(waitForResume: true);
    intent.complete();
    await tester.pump(const Duration(milliseconds: 100));
    session.handleLifecycle(AppLifecycleState.paused);
    await tester.pump(const Duration(hours: 1));
    expect(session.isUnlocked, true);
    session.handleLifecycle(AppLifecycleState.resumed);
    await intent.released;
    expect(session.hasSystemInteraction, false);
    session.handleLifecycle(AppLifecycleState.paused);
    expect(session.isUnlocked, false);
  });

  testWidgets('failed or non-launching intent cannot leave relock disabled',
      (tester) async {
    final session = SessionService(now: tester.binding.clock.now);
    addTearDown(session.dispose);
    session.unlock();
    final failed = session.beginSystemInteraction(waitForResume: true);
    failed.complete(failed: true);
    await failed.released;
    final noLaunch = session.beginSystemInteraction(waitForResume: true);
    noLaunch.complete();
    await tester.pump(const Duration(seconds: 2));
    await noLaunch.released;
    expect(session.hasSystemInteraction, false);
    session.handleLifecycle(AppLifecycleState.paused);
    expect(session.isUnlocked, false);
  });

  test('nested scopes and biometric inactive/resumed callbacks stay exempt',
      () {
    final session = SessionService();
    addTearDown(session.dispose);
    session.unlock();
    final outer = session.beginSystemInteraction();
    final inner = session.beginSystemInteraction();
    session.handleLifecycle(AppLifecycleState.inactive);
    session.handleLifecycle(AppLifecycleState.resumed);
    inner.complete();
    expect(session.hasSystemInteraction, true);
    expect(session.isUnlocked, true);
    outer.complete();
    expect(session.hasSystemInteraction, false);
    session.handleLifecycle(AppLifecycleState.paused);
    expect(session.isUnlocked, false);
  });

  testWidgets(
      'lock disposes protected routes and dialogs; back cannot bypass it',
      (tester) async {
    final session = SessionService(now: tester.binding.clock.now);
    addTearDown(session.dispose);
    var editorDisposed = false;
    session.unlock();
    await tester.pumpWidget(SessionHost(
      session: session,
      builder: (_) => MaterialApp(
        navigatorKey: navigatorKeyForSession(session.generation),
        home: Scaffold(
          body: Text(session.isUnlocked ? 'Vault' : 'Authentication'),
        ),
      ),
    ));
    final navigator = navigatorKeyForSession(session.generation).currentState!;
    unawaited(navigator.push(MaterialPageRoute<void>(
      builder: (_) => _Editor(onDispose: () => editorDisposed = true),
    )));
    await tester.pumpAndSettle();
    unawaited(showDialog<void>(
      context: tester.element(find.text('Sensitive editor')),
      builder: (_) => const AlertDialog(content: Text('Sensitive dialog')),
    ));
    await tester.pumpAndSettle();
    await session.lock();
    await tester.pumpAndSettle();
    expect(editorDisposed, true);
    expect(find.text('Sensitive editor'), findsNothing);
    expect(find.text('Sensitive dialog'), findsNothing);
    expect(find.text('Authentication'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Authentication'), findsOneWidget);
    session.unlock();
    await tester.pumpAndSettle();
    expect(find.text('Vault'), findsOneWidget);
    expect(navigatorKeyForSession(session.generation).currentState!.canPop(),
        false);
    await session.lock();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pointer activity resets timeout and inactive content is covered',
      (tester) async {
    final session = SessionService(now: tester.binding.clock.now);
    addTearDown(session.dispose);
    session.configure(const VaultSettings(inactivityLockSeconds: 30));
    session.unlock();
    await tester.pumpWidget(SessionHost(
      session: session,
      builder: (_) => const MaterialApp(home: Scaffold(body: Text('Vault'))),
    ));
    await tester.pump(const Duration(seconds: 25));
    await tester.tap(find.text('Vault'));
    await tester.pump(const Duration(seconds: 25));
    expect(session.isUnlocked, true);
    session.handleLifecycle(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(Positioned), findsOneWidget);
    session.handleLifecycle(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(Positioned), findsNothing);
    await session.lock();
    await tester.pumpWidget(const SizedBox());
  });

  test('relock settings round-trip and old saved choices are preserved', () {
    final old = VaultSettings.fromJson({
      'autoKillDelaySeconds': 30,
      'encryptionEnabled': true,
    });
    expect(old.autoKillEnabled, true);
    expect(old.inactivityLockSeconds, 300);
    expect(old.backgroundLockDelaySeconds, 0);
    expect(old.encryptionEnabled, true);
    final settings = old.copyWith(
      autoKillEnabled: false,
      inactivityLockSeconds: 0,
      backgroundLockDelaySeconds: -1,
    );
    final restored = VaultSettings.fromJson(settings.toJson());
    expect(restored.autoKillEnabled, false);
    expect(restored.inactivityLockSeconds, 0);
    expect(restored.backgroundLockDelaySeconds, -1);
    expect(restored.autoKillDelaySeconds, 30);
    expect(restored.encryptionEnabled, true);
  });

  testWidgets('soft-keyboard editing counts as activity', (tester) async {
    final session = SessionService(now: tester.binding.clock.now);
    addTearDown(session.dispose);
    session.configure(const VaultSettings(inactivityLockSeconds: 30));
    session.unlock();
    await tester.pumpWidget(SessionHost(
      session: session,
      builder: (_) => const MaterialApp(home: Scaffold(body: TextField())),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(seconds: 25));
    tester.testTextInput.enterText('typing in the editor');
    await tester.pump(const Duration(seconds: 25));
    expect(session.isUnlocked, true);
    await tester.pump(const Duration(seconds: 5));
    expect(session.isUnlocked, false);
    await tester.pumpWidget(const SizedBox());
  });
}

class _Editor extends StatefulWidget {
  const _Editor({required this.onDispose});
  final VoidCallback onDispose;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('Sensitive editor'));
}
