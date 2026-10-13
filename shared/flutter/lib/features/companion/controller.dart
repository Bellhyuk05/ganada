import 'package:flutter/foundation.dart';

import 'models.dart';
import 'repositories.dart';

class CompanionController extends ChangeNotifier {
  CompanionController(this.repository);
  final CompanionRepository repository;
  FeatureSnapshot? snapshot;
  bool loading = false;
  bool busy = false;
  String? error;
  bool _disposed = false;
  final Map<String, Future<ProfileStats>> _visibleProfiles = {};
  bool get companionReady => featureReady(CompanionFeature.profile);
  bool featureReady(CompanionFeature feature) =>
      snapshot?.featureReady(feature) == true;
  String featureMessage(CompanionFeature feature) =>
      snapshot?.featureMessage(feature) ?? '기능 정보를 불러오는 중이에요.';
  String get companionMessage => featureMessage(CompanionFeature.profile);
  Future<ProfileStats> visibleProfile(String userId) {
    if (!companionReady) {
      return Future.error(FeatureFailure(companionMessage));
    }
    return _visibleProfiles.putIfAbsent(userId, () {
      if (_visibleProfiles.length >= 64) {
        _visibleProfiles.remove(_visibleProfiles.keys.first);
      }
      return repository.profile(userId).timeout(const Duration(seconds: 20));
    });
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (loading || _disposed) return;
    loading = true;
    _visibleProfiles.clear();
    error = null;
    _emit();
    try {
      final value = await repository.load();
      if (!_disposed) snapshot = value;
    } catch (e) {
      error = _message(e);
    } finally {
      loading = false;
      _emit();
    }
  }

  Future<bool> perform(
    Future<void> Function() action, {
    bool allowUserInteraction = false,
    CompanionFeature feature = CompanionFeature.profile,
  }) async {
    if (busy || loading || _disposed) return false;
    if (!featureReady(feature)) {
      error = featureMessage(feature);
      _emit();
      return false;
    }
    busy = true;
    error = null;
    _emit();
    var committed = false;
    try {
      // Writes aren't automatically repeated: the server owns idempotency.
      final request = action();
      if (allowUserInteraction) {
        await request;
      } else {
        await request.timeout(const Duration(seconds: 20));
      }
      committed = true;
      await refresh();
      if (error != null || !featureReady(feature)) {
        error = '저장은 완료됐지만 새 정보를 불러오지 못했어요. 다시 불러와 주세요.';
      }
    } catch (e) {
      error = _message(e);
    } finally {
      busy = false;
      _emit();
    }
    return committed;
  }

  String _message(Object error) => error is FeatureFailure
      ? error.message
      : '연결 상태를 확인한 뒤 다시 시도해 주세요. 요청 결과가 불확실하면 먼저 다시 불러와 주세요.';

  @override
  void dispose() {
    _disposed = true;
    _visibleProfiles.clear();
    super.dispose();
  }
}
