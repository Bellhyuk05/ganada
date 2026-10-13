import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../features/companion/models.dart';
import '../features/companion/repositories.dart';
import 'app_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  if (AppConfig.firebaseConfigured && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: AppConfig.firebaseOptions);
  }
  // Background notification payloads are displayed by Android. The authoritative
  // inbox is in Supabase; never write another notification from the client.
}

class PushService {
  PushService(
    this.repository, {
    required this.onInboxChanged,
    required this.onOpenRide,
  });
  final CompanionRepository repository;
  final Future<void> Function() onInboxChanged;
  final Future<void> Function(String) onOpenRide;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _token;
  bool _disposed = false;
  bool _started = false;
  bool _disconnecting = false;
  String? lastError;
  bool moduleReady = false;
  bool get available =>
      moduleReady &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      AppConfig.firebaseConfigured;

  Future<void> start() async {
    if (!available || _started) return;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: AppConfig.firebaseOptions);
    }
    if (_disposed) return;
    _started = true;
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
    _subscriptions.add(
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        try {
          await _register(token);
        } catch (_) {
          lastError = '기기 알림 등록을 다시 시도해 주세요.';
        }
      }),
    );
    _subscriptions.add(FirebaseMessaging.onMessage.listen((_) => _receive()));
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m)),
    );
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    }
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null && !_disposed) await _open(initial);
  }

  Future<void> _register(String token) async {
    if (_disposed || _disconnecting || !moduleReady) return;
    await repository
        .registerDeviceToken(token)
        .timeout(const Duration(seconds: 20));
    if (_disposed) return;
    final old = _token;
    _token = token;
    if (old != null && old != token) await repository.removeDeviceToken(old);
    lastError = null;
  }

  Future<void> _receive() async {
    if (_disposed) return;
    try {
      await onInboxChanged();
    } catch (_) {
      lastError = '알림함을 다시 불러와 주세요.';
    }
  }

  Future<void> _open(RemoteMessage message) async {
    if (_disposed) return;
    try {
      await onInboxChanged();
      final id = message.data['ride_id'];
      if (id != null && !_disposed) await onOpenRide(id);
    } catch (_) {
      lastError = '알림에 연결된 팟을 다시 확인해 주세요.';
    }
  }

  Future<void> enable() async {
    if (!available) {
      throw const FeatureFailure('기기 푸시 설정이 아직 준비되지 않았어요. 앱 내 알림은 확인할 수 있어요.');
    }
    await start();
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      throw const FeatureFailure('휴대폰 설정에서 알림을 허용해 주세요.');
    }
    final token = await FirebaseMessaging.instance.getToken().timeout(
      const Duration(seconds: 20),
    );
    if (token == null) throw const FeatureFailure('기기 알림 등록을 다시 시도해 주세요.');
    await _register(token);
  }

  Future<void> disconnect() async {
    _disconnecting = true;
    try {
      final token = _token;
      try {
        if (token != null) {
          await repository
              .removeDeviceToken(token)
              .timeout(const Duration(seconds: 10));
        }
      } finally {
        _token = null;
        try {
          if (_started) await FirebaseMessaging.instance.deleteToken();
        } finally {
          dispose();
        }
      }
    } finally {
      _disconnecting = false;
    }
  }

  void dispose() {
    _disposed = true;
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
  }
}
