import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/backend/voryn_backend.dart';
import 'core/notifications/lock_screen_service.dart';
import 'core/notifications/voryn_firebase_messaging.dart';
import 'core/presence/voryn_presence_service.dart';
import 'core/theme/voryn_theme.dart';
import 'core/theme/voryn_theme_controller.dart';
import 'features/auth/auth_screens.dart';
import 'features/auth/voryn_auth_service.dart';
import 'features/connect/connect_live_screen.dart';
import 'features/connect/mock_voryn_state.dart';
import 'features/calling/active_audio_call_screen.dart';
import 'features/calling/active_video_call_screen.dart';
import 'features/calling/group_call_screen.dart';
import 'features/calling/incoming_call_screen.dart';
import 'features/calling/multi_call_coordinator.dart';
import 'features/calling/voryn_active_call_presentation_service.dart';
import 'features/calling/voryn_call_history_service.dart';
import 'features/calling/voryn_call_latency_tracker.dart';
import 'features/calling/voryn_call_runtime_coordinator.dart';
import 'features/calling/voryn_call_service.dart';
import 'features/calling/voryn_livekit_service.dart';
import 'features/calling/voryn_mini_call_bar.dart';
import 'features/contacts/contacts_live_screen.dart';
import 'features/recents/recents_live_screen.dart';
import 'features/meetings/meetings_screen.dart';
import 'features/onboarding/onboarding_screens.dart';
import 'features/onboarding/landing_screen.dart';
import 'features/messages/call_messages_screen.dart';
import 'features/messages/conversation_screen.dart';
import 'features/messages/voryn_background_auth_bridge.dart';
import 'features/messages/voryn_message_repository.dart';
import 'shared/widgets/voryn_avatar.dart';
import 'shared/widgets/voryn_card.dart';
import 'shared/widgets/voryn_presence.dart';

enum AppLaunchMode { normal, incomingCall, acceptedCall }

class AppLaunchConfig {
  final AppLaunchMode mode;
  final String? callId;
  final String? callType;
  final String initialLocation;

  const AppLaunchConfig({
    required this.mode,
    this.callId,
    this.callType,
    required this.initialLocation,
  });
}

Future<AppLaunchConfig> resolveAppLaunchConfig() async {
  final defaultRoute =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  debugPrint('[CALL_ROUTE] defaultRouteName=$defaultRoute');

  final nativeLaunch = await LockScreenService.getInitialCallLaunch();
  var action = nativeLaunch?['action'] ?? '';
  var actionId = nativeLaunch?['actionId'] ?? '';
  var callId = nativeLaunch?['callId'] ?? '';
  var callType = nativeLaunch?['callType'] ?? '';

  if (callId.isEmpty) {
    if (defaultRoute.startsWith('/active-audio-call/')) {
      callId = defaultRoute.substring('/active-audio-call/'.length);
      callType = 'audio';
      actionId = 'accept';
      action = 'ACCEPT_CALL';
    } else if (defaultRoute.startsWith('/active-video-call/')) {
      callId = defaultRoute.substring('/active-video-call/'.length);
      callType = 'video';
      actionId = 'accept';
      action = 'ACCEPT_CALL';
    }
  }

  debugPrint(
    '[BOOT] onCreate action=$action actionId=$actionId callId=$callId',
  );

  if (actionId == 'decline' && callId.isNotEmpty) {
    debugPrint('[BOOT] launch action is decline for callId=$callId');
    await VorynFirebaseMessaging.handleDeclineAction(callId);
    return const AppLaunchConfig(
      mode: AppLaunchMode.normal,
      initialLocation: '/splash',
    );
  }

  final isCallIntent = callId.isNotEmpty || actionId == 'accept';
  if (isCallIntent && callId.isNotEmpty) {
    if (await LockScreenService.isCallOwnedByOtherHost(callId)) {
      debugPrint(
        '[HOST_OWNERSHIP] cold start callId=$callId is owned by other host, suppressing MainActivity call launch',
      );
      return const AppLaunchConfig(
        mode: AppLaunchMode.normal,
        initialLocation: '/splash',
      );
    }
    debugPrint('[BOOT] initial callId=$callId');
    VorynFirebaseMessaging.markCallLaunchHandled(callId);
    final isVideo = callType == 'video';

    if (actionId == 'accept') {
      final acceptTimestamp =
          int.tryParse(nativeLaunch?['acceptTimestamp'] ?? '') ?? 0;
      final tracker = VorynCallLatencyTracker.start(
        callId: callId,
        baseTimestampMs: acceptTimestamp > 0 ? acceptTimestamp : null,
      );
      unawaited(tracker.stage('flutter_accept_received'));
      await LockScreenService.cancelNativeIncomingCall(
        callId,
        reason: 'accept',
      );
      final loc = isVideo
          ? '/active-video-call/$callId'
          : '/active-audio-call/$callId';
      debugPrint('[BOOT] launchMode=acceptedCall');
      debugPrint('[BOOT] router initialLocation=$loc');
      debugPrint('[CALL_ROUTE] firstRoute=$loc');
      return AppLaunchConfig(
        mode: AppLaunchMode.acceptedCall,
        callId: callId,
        callType: isVideo ? 'video' : 'audio',
        initialLocation: loc,
      );
    } else {
      final loc = '/incoming-call/$callId';
      debugPrint('[BOOT] launchMode=incomingCall');
      debugPrint('[BOOT] router initialLocation=$loc');
      return AppLaunchConfig(
        mode: AppLaunchMode.incomingCall,
        callId: callId,
        callType: isVideo ? 'video' : 'audio',
        initialLocation: loc,
      );
    }
  }

  // Open-app pending call recovery: User opens Voryn while an incoming call is pending
  try {
    final pending = await const VorynCallService().getPendingIncomingCall();
    if (pending != null &&
        (pending.status == 'calling' || pending.status == 'ringing')) {
      if (await LockScreenService.isCallOwnedByOtherHost(pending.id)) {
        debugPrint(
          '[HOST_OWNERSHIP] pending call ${pending.id} is owned by other host',
        );
      } else {
        final isVideo = pending.callType == 'video';
        final loc = '/incoming-call/${pending.id}';
        debugPrint('[BOOT] recovered pending incoming call: ${pending.id}');
        debugPrint('[BOOT] launchMode=incomingCall');
        debugPrint('[BOOT] router initialLocation=$loc');
        return AppLaunchConfig(
          mode: AppLaunchMode.incomingCall,
          callId: pending.id,
          callType: isVideo ? 'video' : 'audio',
          initialLocation: loc,
        );
      }
    }
  } catch (e) {
    debugPrint('[BOOT] error checking pending incoming call on cold start: $e');
  }

  debugPrint('[BOOT] launchMode=normal');
  debugPrint('[BOOT] router initialLocation=/splash');
  return const AppLaunchConfig(
    mode: AppLaunchMode.normal,
    initialLocation: '/splash',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = VorynThemeController();
  await controller.load();
  await VorynBackend.initialize();
  await const VorynCallService().reconcileStaleActiveCallOnStartup();

  // Cold-start call gate: Resolve launch config BEFORE building router or UI
  final launchConfig = await resolveAppLaunchConfig();

  runApp(
    VorynApp(
      controller: controller,
      initialLocation: launchConfig.initialLocation,
      initialLaunchConfig: launchConfig,
    ),
  );
}

/// Dedicated Dart entrypoint for VorynCallActivity (isolated call host).
/// Never builds VorynShell, dashboard tabs, or initializes unneeded background services.
@pragma('vm:entry-point')
Future<void> callMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  LockScreenService.isCallHostApp = true;
  final controller = VorynThemeController();
  await controller.load();
  await VorynBackend.initialize();

  final defaultRoute =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  debugPrint('[CALL_MAIN] defaultRouteName=$defaultRoute');

  final nativeLaunch = await LockScreenService.getInitialCallLaunch();
  var callId = nativeLaunch?['callId'] ?? '';
  var callType = nativeLaunch?['callType'] ?? 'audio';

  if (callId.isEmpty) {
    if (defaultRoute.startsWith('/active-audio-call/')) {
      callId = defaultRoute.substring('/active-audio-call/'.length);
      callType = 'audio';
    } else if (defaultRoute.startsWith('/active-video-call/')) {
      callId = defaultRoute.substring('/active-video-call/'.length);
      callType = 'video';
    }
  }

  debugPrint('[CALL_MAIN] resolved callId=$callId callType=$callType');

  final isVideo = callType == 'video';
  final initialRoute = isVideo
      ? '/active-video-call/$callId'
      : '/active-audio-call/$callId';
  debugPrint('[CALL_ROUTE] firstRoute=$initialRoute');

  final acceptTimestamp =
      int.tryParse(nativeLaunch?['acceptTimestamp'] ?? '') ?? 0;
  if (callId.isNotEmpty) {
    final tracker = VorynCallLatencyTracker.start(
      callId: callId,
      baseTimestampMs: acceptTimestamp > 0 ? acceptTimestamp : null,
    );
    unawaited(tracker.stage('call_main_bootstrap'));
  }

  runApp(
    VorynCallHostApp(
      controller: controller,
      initialLocation: initialRoute,
      callId: callId,
      isVideo: isVideo,
    ),
  );
}

class VorynCallHostApp extends StatefulWidget {
  const VorynCallHostApp({
    super.key,
    required this.controller,
    required this.initialLocation,
    required this.callId,
    required this.isVideo,
  });

  final VorynThemeController controller;
  final String initialLocation;
  final String callId;
  final bool isVideo;

  @override
  State<VorynCallHostApp> createState() => _VorynCallHostAppState();
}

class _VorynCallHostAppState extends State<VorynCallHostApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: widget.initialLocation,
    routes: [
      GoRoute(
        path: '/active-audio-call/:callId',
        builder: (context, state) {
          final callId = state.pathParameters['callId'] ?? widget.callId;
          final extra = state.extra as Map<String, dynamic>?;
          return ActiveAudioCallScreen(
            callId: callId,
            user: extra?['user'] as VorynMockUser?,
            existingSession: extra?['session'] as VorynLiveKitSession?,
          );
        },
      ),
      GoRoute(
        path: '/active-video-call/:callId',
        builder: (context, state) {
          final callId = state.pathParameters['callId'] ?? widget.callId;
          final extra = state.extra as Map<String, dynamic>?;
          return ActiveVideoCallScreen(
            callId: callId,
            user: extra?['user'] as VorynMockUser?,
            existingSession: extra?['session'] as VorynLiveKitSession?,
          );
        },
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    LockScreenService.setCallLaunchListener(
      (data) {
        final actionId = data['actionId'] ?? '';
        final callId = data['callId'] ?? '';
        if (actionId == 'hold_and_accept' && callId.isNotEmpty) {
          unawaited(MultiCallCoordinator.instance.holdAndAccept(callId));
        } else {
          debugPrint('[CALL_HOST] onCallLaunchIntent ignored during active call: $data');
        }
      },
      onDeclined: (callId) {
        debugPrint('[CALL_HOST] onDeclined for callId=$callId');
      },
      onIncoming: (data) {
        debugPrint('[CALL_HOST] onIncoming ignored in call host');
      },
      onCallWaiting: (data) {
        final callId = data['callId'] ?? '';
        final callerName = data['callerName'] ?? 'Voryn User';
        final callType = data['callType'] ?? 'audio';
        if (callId.isNotEmpty) {
          MultiCallCoordinator.instance.handleIncomingWaitingCall(
            callId: callId,
            callerName: callerName,
            callType: callType,
          );
        }
      },
      onCallWaitingCancelled: (callId) {
        MultiCallCoordinator.instance.dismissWaitingCall(callId);
      },
      onTerminal: (callId, type) {
        debugPrint('[CALL_HOST] onTerminal for callId=$callId type=$type');
        MultiCallCoordinator.instance.endCall(callId, isLocalInitiator: false);
      },
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'Voryn Call',
          debugShowCheckedModeBanner: false,
          themeMode: widget.controller.mode,
          theme: VorynTheme.light,
          darkTheme: VorynTheme.dark,
          routerConfig: _router,
        );
      },
    );
  }
}

class VorynApp extends StatefulWidget {
  const VorynApp({
    super.key,
    this.controller,
    this.initialLocation,
    this.initialLaunchConfig,
  });
  final VorynThemeController? controller;
  final String? initialLocation;
  final AppLaunchConfig? initialLaunchConfig;
  @override
  State<VorynApp> createState() => _VorynAppState();
}

class _VorynAppState extends State<VorynApp> with WidgetsBindingObserver {
  final _auth = const VorynAuthService();
  late final VorynThemeController _controller =
      widget.controller ?? VorynThemeController();
  late final GoRouter _router = _buildRouter(
    initialLocation: widget.initialLocation,
  );
  StreamSubscription<AuthState>? _authSubscription;
  bool _firstFrameReported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VorynPresenceService.onLifecycleChanged(AppLifecycleState.resumed);
    VorynBackgroundAuthBridge.instance.initialize();
    VorynBackgroundAuthBridge.instance.onOpenThread.listen((threadId) {
      if (mounted && !_isCallRouteActive()) {
        _router.go('/messages/thread/$threadId');
      }
    });
    VorynBackgroundAuthBridge.instance.onOpenInbox.listen((_) {
      if (mounted && !_isCallRouteActive()) {
        _router.go('/messages');
      }
    });

    final initialSession = VorynBackend.client?.auth.currentSession;
    if (initialSession != null) {
      VorynBackgroundAuthBridge.instance.syncSession(initialSession);
      VorynMessageRepository.instance.initializeRealtime();
      unawaited(
        VorynMessageRepository.instance.reconcile(reason: 'cold_start'),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_firstFrameReported) {
        _firstFrameReported = true;
        final loc = widget.initialLocation ?? '/splash';
        debugPrint('[BOOT] first frame route=$loc');
      }
      await VorynFirebaseMessaging.initialize();
      if (!mounted) return;
      await _handlePendingCallLaunch();
      final pendingThread = await VorynBackgroundAuthBridge.instance
          .getPendingMessageThread();
      if (pendingThread != null &&
          pendingThread.isNotEmpty &&
          mounted &&
          !_isCallRouteActive()) {
        _router.go('/messages/thread/$pendingThread');
      }
      unawaited(initializeVorynContactState());
    });

    // Listen for warm-app call launch intents (onNewIntent) and native FCM events
    LockScreenService.setCallLaunchListener(
      _handleWarmCallLaunch,
      onDeclined: (callId) {
        debugPrint('[BOOT] onDeclined from native receiver for callId=$callId');
        VorynFirebaseMessaging.handleDeclineAction(callId);
      },
      onIncoming: (data) async {
        final callId = data['callId'] ?? '';
        debugPrint('[BOOT] onIncoming from native service for callId=$callId');
        final isLocked = await LockScreenService.isKeyguardLocked();
        if (isLocked) {
          debugPrint(
            '[LOCKSCREEN] suppressed Flutter incoming route while locked',
          );
          return;
        }
        final activeSnapshot =
            VorynActiveCallPresentationService.instance.currentSnapshot;
        if (activeSnapshot != null &&
            activeSnapshot.isActive &&
            (activeSnapshot.callId == callId ||
                activeSnapshot.callId.isNotEmpty)) {
          debugPrint(
            '[HOST_OWNERSHIP] suppressed onIncoming in MainActivity: active call ${activeSnapshot.callId} already present',
          );
          return;
        }
        if (await LockScreenService.isCallOwnedByOtherHost(callId)) {
          debugPrint(
            '[HOST_OWNERSHIP] suppressed onIncoming in MainActivity: callId=$callId owned by other host',
          );
          return;
        }
        if (callId.isNotEmpty && !_isCallRouteActive() && mounted) {
          _router.go('/incoming-call/$callId');
        }
      },
      onCallWaiting: (data) {
        final callId = data['callId'] ?? '';
        final callerName = data['callerName'] ?? 'Voryn User';
        final callType = data['callType'] ?? 'audio';
        if (callId.isNotEmpty) {
          MultiCallCoordinator.instance.handleIncomingWaitingCall(
            callId: callId,
            callerName: callerName,
            callType: callType,
          );
        }
      },
      onCallWaitingCancelled: (callId) {
        MultiCallCoordinator.instance.dismissWaitingCall(callId);
      },
      onTerminal: (callId, type) {
        debugPrint(
          '[BOOT] onTerminal from native service for callId=$callId type=$type',
        );
        VorynFirebaseMessaging.clearPendingIncomingCall(callId);
        VorynActiveCallPresentationService.instance.clearSnapshot();
        MultiCallCoordinator.instance.endCall(callId, isLocalInitiator: false);
      },
      onActiveCallStateChanged: (snapshot) {
        debugPrint(
          '[CALL_MINIMIZE] onActiveCallStateChanged in MainActivity: $snapshot',
        );
        VorynActiveCallPresentationService.instance.updateSnapshotFromMap(
          snapshot,
        );
      },
    );
    VorynActiveCallPresentationService.instance.refreshSnapshot();

    if (_auth.isAvailable) {
      _authSubscription = _auth.authStateChanges.listen((state) async {
        final user = state.session?.user;
        if (user == null || !mounted) return;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _router.go('/reset-password');
        } else if (state.event == AuthChangeEvent.signedIn) {
          VorynPresenceService.setOnline();
          VorynFirebaseMessaging.registerTokenAfterSplash();
          if (state.session != null) {
            VorynBackgroundAuthBridge.instance.syncSession(state.session!);
            VorynMessageRepository.instance.initializeRealtime();
            unawaited(
              VorynMessageRepository.instance.reconcile(reason: 'signed_in'),
            );
          }
          if (!_isCallRouteActive() &&
              widget.initialLaunchConfig?.mode == AppLaunchMode.normal) {
            final isLocked = await LockScreenService.isKeyguardLocked();
            if (!isLocked && !_isCallRouteActive()) {
              final target = _auth.routeAfterAuthentication(user);
              debugPrint('[BOOT] auth redirect to $target');
              _router.go(target);
            } else {
              debugPrint(
                '[BOOT] suppressed auth redirect: phone locked or call active',
              );
            }
          }
        } else if (state.event == AuthChangeEvent.signedOut) {
          VorynPresenceService.setOffline();
          VorynBackgroundAuthBridge.instance.clearSession();
          VorynMessageRepository.instance.disposeRealtime();
          VorynMessageRepository.instance.totalUnreadCount.value = 0;
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    VorynPresenceService.onLifecycleChanged(state);
    if (state == AppLifecycleState.resumed) {
      _checkPendingIncomingCall();
      VorynActiveCallPresentationService.instance.refreshSnapshot();
      unawaited(
        VorynMessageRepository.instance.reconcile(reason: 'app_resume'),
      );
    }
  }

  Future<void> _checkPendingIncomingCall() async {
    if (_isCallRouteActive()) return;
    final isLocked = await LockScreenService.isKeyguardLocked();
    if (isLocked) {
      debugPrint('[LOCKSCREEN] suppressed pending incoming check while locked');
      return;
    }
    final currentUser = VorynBackend.client?.auth.currentUser;
    if (currentUser == null) return;

    final activeSnapshot =
        VorynActiveCallPresentationService.instance.currentSnapshot;
    final currentActiveId = activeSnapshot?.callId;
    if (activeSnapshot != null && activeSnapshot.isActive) {
      debugPrint(
        '[INCOMING_RECOVERY] active call present ($currentActiveId), suppressing pending incoming check',
      );
      return;
    }

    try {
      final nativeMap = await LockScreenService.getPendingIncomingCall();
      if (nativeMap != null) {
        final nCallId = nativeMap['callId']?.toString() ?? '';
        final nState = nativeMap['state']?.toString() ?? '';
        final nReceivedAt =
            int.tryParse(nativeMap['receivedAt']?.toString() ?? '') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        final isFresh = nReceivedAt == 0 || (now - nReceivedAt) < 60000;
        if (nCallId.isNotEmpty && isFresh) {
          if (nCallId == currentActiveId ||
              await LockScreenService.isCallOwnedByOtherHost(nCallId)) {
            debugPrint(
              '[HOST_OWNERSHIP] suppressed pending incoming check in MainActivity: callId=$nCallId owned by other host or active',
            );
            return;
          }
          if (VorynCallRuntimeCoordinator.isAcceptInFlight(nCallId)) {
            debugPrint(
              '[RESUME] accept in-flight for $nCallId, suppressing incoming screen',
            );
            return;
          }
          if (nState == 'RINGING') {
            if (!_isCallRouteActive() && mounted) {
              debugPrint(
                '[RESUME] recovered native pending incoming call: $nCallId',
              );
              _router.go('/incoming-call/$nCallId');
              return;
            }
          }
        }
      }

      final pending = await const VorynCallService().getPendingIncomingCall();
      if (pending != null) {
        if (pending.id == currentActiveId ||
            await LockScreenService.isCallOwnedByOtherHost(pending.id)) {
          debugPrint(
            '[HOST_OWNERSHIP] suppressed pending incoming check in MainActivity: callId=${pending.id} owned by other host or active',
          );
          return;
        }
        if (VorynCallRuntimeCoordinator.isAcceptInFlight(pending.id)) {
          debugPrint(
            '[RESUME] accept in-flight for ${pending.id}, suppressing incoming screen',
          );
          return;
        }
        if (pending.status == 'calling' || pending.status == 'ringing') {
          if (!_isCallRouteActive() && mounted) {
            debugPrint(
              '[RESUME] recovered pending incoming call: ${pending.id}',
            );
            _router.go('/incoming-call/${pending.id}');
          }
        }
      }
    } catch (e) {
      debugPrint('[RESUME] error checking pending incoming call: $e');
    }
  }

  bool _isCallRouteActive() {
    try {
      final loc = _router.routerDelegate.currentConfiguration.uri.toString();
      return loc.contains('/incoming-call') ||
          loc.contains('/active-audio-call') ||
          loc.contains('/active-video-call') ||
          loc.contains('/group-call');
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleWarmCallLaunch(Map<String, String> data) async {
    final callId = data['callId'] ?? '';
    final actionId = data['actionId'] ?? '';
    final callType = data['callType'] ?? '';

    debugPrint('[BOOT] warm app launch callId=$callId actionId=$actionId');
    if (callId.isEmpty) return;

    if (await LockScreenService.isCallOwnedByOtherHost(callId)) {
      debugPrint(
        '[HOST_OWNERSHIP] suppressed warm call launch in MainActivity: callId=$callId owned by other host',
      );
      return;
    }

    if (actionId == 'hold_and_accept') {
      await MultiCallCoordinator.instance.holdAndAccept(callId);
      return;
    }

    if (actionId == 'decline') {
      await VorynFirebaseMessaging.handleDeclineAction(callId);
      return;
    }

    final activeCall = await const VorynCallHistoryService()
        .loadIncomingActiveCall(callId: callId);

    if (activeCall == null) {
      debugPrint('[BOOT] warm call $callId is stale');
      final isLocked = await LockScreenService.isKeyguardLocked();
      if (isLocked) {
        await LockScreenService.moveCallTaskBehindKeyguard();
      }
      return;
    }

    VorynFirebaseMessaging.markCallLaunchHandled(callId);
    final isVideo = activeCall.callType == 'video' || callType == 'video';

    if (actionId == 'accept') {
      final acceptTimestamp = int.tryParse(data['acceptTimestamp'] ?? '') ?? 0;
      final tracker = VorynCallLatencyTracker.start(
        callId: callId,
        baseTimestampMs: acceptTimestamp > 0 ? acceptTimestamp : null,
      );
      unawaited(tracker.stage('flutter_accept_received'));
      try {
        await VorynCallRuntimeCoordinator.runAcceptOnce(callId, () async {
          _router.go(
            isVideo
                ? '/active-video-call/$callId'
                : '/active-audio-call/$callId',
          );
        });
      } catch (_) {}
    } else {
      _router.go('/incoming-call/$callId');
    }
  }

  Future<void> _handlePendingCallLaunch() async {
    final launch = VorynFirebaseMessaging.pendingLaunch;
    if (launch == null) return;
    if (VorynFirebaseMessaging.isCallLaunchHandled(launch.callId)) {
      debugPrint(
        '[BOOT] ignoring duplicate pending call launch ${launch.callId}',
      );
      return;
    }

    if (await LockScreenService.isCallOwnedByOtherHost(launch.callId)) {
      debugPrint(
        '[HOST_OWNERSHIP] suppressed pending call launch in MainActivity: callId=${launch.callId} owned by other host',
      );
      return;
    }

    final currentUser = VorynBackend.client?.auth.currentUser;
    if (!_auth.isAvailable || currentUser == null) {
      final isLocked = await LockScreenService.isKeyguardLocked();
      if (isLocked) {
        await LockScreenService.moveCallTaskBehindKeyguard();
      } else {
        _router.go('/welcome');
      }
      return;
    }

    // Stale Call Protection (Section 11)
    final activeCall = await const VorynCallHistoryService()
        .loadIncomingActiveCall(callId: launch.callId);

    if (activeCall == null) {
      VorynFirebaseMessaging.clearPendingIncomingCall(launch.callId);
      final isLocked = await LockScreenService.isKeyguardLocked();
      if (isLocked) {
        await LockScreenService.moveCallTaskBehindKeyguard();
      } else {
        _router.go('/connect');
      }
      return;
    }

    VorynFirebaseMessaging.markCallLaunchHandled(launch.callId);
    // Call is active and valid: map explicit action
    if (launch.action == VorynNotificationActionType.accept) {
      VorynFirebaseMessaging.clearPendingIncomingCall(launch.callId);
      await LockScreenService.cancelNativeIncomingCall(
        launch.callId,
        reason: 'accept',
      );
      final isVideo = activeCall.callType == 'video';
      try {
        await VorynCallRuntimeCoordinator.runAcceptOnce(
          launch.callId,
          () async {
            if (isVideo) {
              _router.go('/active-video-call/${launch.callId}');
            } else {
              _router.go('/active-audio-call/${launch.callId}');
            }
          },
        );
      } catch (_) {}
    } else {
      _router.go('/incoming-call/${launch.callId}');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller == null) {
      return _buildApp(ThemeMode.system);
    }

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildApp(_controller.mode),
    );
  }

  Widget _buildApp(ThemeMode mode) => MaterialApp.router(
    title: 'Voryn',
    debugShowCheckedModeBanner: false,
    theme: VorynTheme.light,
    darkTheme: VorynTheme.dark,
    themeMode: mode,
    routerConfig: _router,
  );
}

GoRouter _buildRouter({String? initialLocation}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final shellNavigatorConnectKey = GlobalKey<NavigatorState>(
    debugLabel: 'connect',
  );
  final shellNavigatorRecentsKey = GlobalKey<NavigatorState>(
    debugLabel: 'recents',
  );
  final shellNavigatorContactsKey = GlobalKey<NavigatorState>(
    debugLabel: 'contacts',
  );
  final shellNavigatorMeetingsKey = GlobalKey<NavigatorState>(
    debugLabel: 'meetings',
  );

  final loc = initialLocation ?? '/splash';
  debugPrint('[BOOT] router creation initialLocation=$loc');
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: loc,
    onException: (context, state, router) {
      final callback =
          state.uri.scheme == 'io.supabase.voryn' &&
          state.uri.host == 'login-callback';
      router.go(callback ? '/login-callback' : '/splash');
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/landing',
        builder: (context, state) => const LandingScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/login-callback',
        builder: (context, state) => const OAuthCallbackScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/incoming-call/:callId',
        builder: (context, state) {
          final callId = state.pathParameters['callId'] ?? '';
          final extra = state.extra as Map<String, dynamic>?;
          final user = extra?['user'] as VorynMockUser?;
          return IncomingCallScreen(callId: callId, initialUser: user);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/incoming-call',
        builder: (context, state) {
          final pendingId =
              VorynFirebaseMessaging.pendingIncomingCallId ?? 'incoming';
          return IncomingCallScreen(callId: pendingId);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/active-audio-call/:callId',
        builder: (context, state) {
          final callId = state.pathParameters['callId'] ?? '';
          final extra = state.extra as Map<String, dynamic>?;
          final user = extra?['user'] as VorynMockUser?;
          final session = extra?['session'] as VorynLiveKitSession?;
          return ActiveAudioCallScreen(
            callId: callId,
            user: user,
            existingSession: session,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/active-video-call/:callId',
        builder: (context, state) {
          final callId = state.pathParameters['callId'] ?? '';
          final extra = state.extra as Map<String, dynamic>?;
          final user = extra?['user'] as VorynMockUser?;
          final session = extra?['session'] as VorynLiveKitSession?;
          return ActiveVideoCallScreen(
            callId: callId,
            user: user,
            existingSession: session,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/group-call/:callId',
        builder: (context, state) {
          final callId = state.pathParameters['callId'] ?? 'meeting';
          final extra = state.extra as Map<String, dynamic>?;
          final title = extra?['title'] as String? ?? 'Meeting $callId';
          final session = extra?['session'] as VorynLiveKitSession?;
          return GroupCallScreen(
            callId: callId,
            title: title,
            existingSession: session,
          );
        },
      ),
      GoRoute(
        path: '/onboarding/profile',
        builder: (context, state) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: '/onboarding/voryn-id',
        builder: (context, state) => const CreateVorynIdScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/messages',
        builder: (context, state) => const CallMessagesScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/messages/thread/:threadId',
        builder: (context, state) {
          final threadId = state.pathParameters['threadId'] ?? '';
          final extra = state.extra as Map<String, dynamic>?;
          return ConversationScreen(
            threadId: threadId,
            otherUserUid: extra?['otherUserUid'] as String?,
            otherUserName: extra?['otherUserName'] as String?,
            otherUserVorynId: extra?['otherUserVorynId'] as String?,
            otherUserAvatarUrl: extra?['otherUserAvatarUrl'] as String?,
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return VorynShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: shellNavigatorConnectKey,
            routes: [
              GoRoute(
                path: '/connect',
                builder: (context, state) => const ConnectLiveScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: shellNavigatorRecentsKey,
            routes: [
              GoRoute(
                path: '/recents',
                builder: (context, state) => const RecentsLiveScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: shellNavigatorContactsKey,
            routes: [
              GoRoute(
                path: '/contacts',
                builder: (context, state) => const ContactsLiveScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: shellNavigatorMeetingsKey,
            routes: [
              GoRoute(
                path: '/meetings',
                builder: (context, state) => const MeetingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

enum VorynTab {
  connect(
    label: 'Connect',
    icon: VorynIcons.connect,
    headline: 'Connect',
    detail: 'Primary Connect tab placeholder',
  ),
  recents(
    label: 'Recents',
    icon: VorynIcons.recents,
    headline: 'Recents',
    detail: 'Recent activity placeholder',
  ),
  contacts(
    label: 'Contacts',
    icon: VorynIcons.contacts,
    headline: 'Contacts',
    detail: 'Contacts list placeholder',
  ),
  meetings(
    label: 'Meetings',
    icon: VorynIcons.meetings,
    headline: 'Meetings',
    detail: 'Meetings hub placeholder',
  );

  const VorynTab({
    required this.label,
    required this.icon,
    required this.headline,
    required this.detail,
  });

  final String label;
  final IconData icon;
  final String headline;
  final String detail;
}

class VorynShell extends StatefulWidget {
  const VorynShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<VorynShell> createState() => _VorynShellState();
}

class _VorynShellState extends State<VorynShell> with WidgetsBindingObserver {
  Timer? _incomingCallTimer;
  bool _showingIncomingCall = false;
  bool _isKeyguardLocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LockScreenService.isKeyguardLocked().then((locked) {
      if (mounted && locked != _isKeyguardLocked) {
        setState(() => _isKeyguardLocked = locked);
      }
    });
    VorynActiveCallPresentationService.instance.refreshSnapshot();
    _incomingCallTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkIncomingCall(),
    );
    _checkIncomingCall();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      LockScreenService.isKeyguardLocked().then((locked) {
        if (mounted && locked != _isKeyguardLocked) {
          setState(() => _isKeyguardLocked = locked);
        }
      });
      VorynActiveCallPresentationService.instance.refreshSnapshot();
      _checkIncomingCall();
    }
  }

  Future<void> _checkIncomingCall() async {
    if (!mounted || _showingIncomingCall) return;
    try {
      final isLocked = await LockScreenService.isKeyguardLocked();
      if (isLocked) return;

      final pendingCallId = VorynFirebaseMessaging.pendingIncomingCallId;
      if (pendingCallId == null) return;
      final call = await const VorynCallHistoryService().loadIncomingActiveCall(
        callId: pendingCallId,
      );
      if (!mounted || call == null || _showingIncomingCall) return;
      _showingIncomingCall = true;
      VorynFirebaseMessaging.clearPendingIncomingCall(call.id);
      context.push('/incoming-call/${call.id}', extra: {'call': call});
    } catch (_) {
      // A temporary offline state should not interrupt the current screen.
    } finally {
      _showingIncomingCall = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingCallTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isKeyguardLocked) {
      debugPrint('[LOCKSCREEN] shellBuildWhileLocked=false');
      return const SizedBox.shrink();
    }
    debugPrint('[BOOT] VorynShell build');
    final colors = context.vorynColors;

    return Scaffold(
      backgroundColor: colors.background,
      body: widget.navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VorynMiniCallBar(),
          VorynBottomNavigation(
            currentIndex: widget.navigationShell.currentIndex,
            onDestinationSelected: (index) {
              widget.navigationShell.goBranch(
                index,
                initialLocation: index == widget.navigationShell.currentIndex,
              );
            },
          ),
        ],
      ),
    );
  }
}

class VorynBottomNavigation extends StatelessWidget {
  const VorynBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.backgroundSoft,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (final (index, tab) in VorynTab.values.indexed)
                Expanded(
                  child: _VorynBottomNavigationItem(
                    tab: tab,
                    selected: index == currentIndex,
                    onPressed: () => onDestinationSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VorynBottomNavigationItem extends StatelessWidget {
  const _VorynBottomNavigationItem({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final VorynTab tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final itemColor = selected ? colors.accent : colors.textMuted;

    return Semantics(
      selected: selected,
      button: true,
      label: tab.label,
      child: InkWell(
        onTap: onPressed,
        splashColor: colors.accentSoft,
        highlightColor: colors.surfacePressed,
        child: Padding(
          padding: const EdgeInsets.only(top: 9, bottom: 7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, color: itemColor, size: 24),
              const SizedBox(height: 4),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: itemColor,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class VorynTabLanding extends StatelessWidget {
  const VorynTabLanding({super.key, required this.tab});

  final VorynTab tab;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;
    final spacing = context.vorynSpacing;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(spacing.screen),
          children: [
            Row(
              children: [
                VorynAvatar(
                  initials: tab.label.substring(0, 1),
                  size: VorynAvatarSize.medium,
                ),
                SizedBox(width: spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tab.headline,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      SizedBox(height: spacing.xxs),
                      Text(
                        tab.detail,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.xl),
            VorynSurface(
              child: Row(
                children: [
                  Icon(tab.icon, color: colors.accent, size: 28),
                  SizedBox(width: spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${tab.label} tab ready',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SizedBox(height: spacing.xxs),
                        Text(
                          'Phase 1.2 verifies the app shell and navigation only.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.md),
            VorynCard(
              child: Row(
                children: [
                  const VorynPresenceIndicator(
                    status: VorynPresenceStatus.online,
                    label: 'Navigation active',
                  ),
                  const Spacer(),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colors.iconMuted,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.md),
            Text(
              'Placeholder content only',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            SizedBox(height: spacing.xs),
            Text(
              'The real ${tab.label} UI is reserved for its later authorized checkpoint.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
