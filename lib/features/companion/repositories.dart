import 'models.dart';

abstract interface class RatingRepository {
  Future<ProfileStats> profile(String userId);

  /// Own profile only. Null removes the photo; bytes are stored in PostgreSQL.
  Future<void> saveProfilePhoto(ProfilePhoto? photo);
  Future<List<RatingTask>> ratingTasks();

  /// Atomic batch, including optional blocks. Same payload retries are idempotent.
  Future<void> submitRatings(String rideId, List<RatingInput> inputs);
}

abstract interface class KeywordRepository {
  Future<List<Keyword>> keywords();
  Future<bool> keywordAlertsEnabled();
  Future<void> addKeyword(String text);
  Future<void> removeKeyword(String keywordId);
  Future<void> setKeywordEnabled(String keywordId, bool enabled);
  Future<void> setKeywordAlerts(bool enabled);
}

abstract interface class BlockingRepository {
  Future<List<UserSummary>> blockedUsers();
  Future<void> block(String targetId);
  Future<void> unblock(String targetId);
  Future<List<UserSummary>> blockedParticipants(String rideId);
}

abstract interface class NoticeRepository {
  Future<List<AppNotice>> notices();
  Future<void> markNoticeRead(String noticeId);
}

abstract interface class RideReadRepository {
  /// Common F-02/F-04/F-06 contract; excludes unauthorized memberships.
  Future<List<RideRecord>> rides();
  Future<RideRecord?> ride(String rideId);

  /// Only the host can read pending applicants.
  Future<List<UserSummary>> applicants(String rideId);
}

abstract interface class DeviceTokenRepository {
  Future<void> registerDeviceToken(String token);
  Future<void> removeDeviceToken(String token);
}

abstract class CompanionRepository
    implements
        RatingRepository,
        KeywordRepository,
        BlockingRepository,
        NoticeRepository,
        RideReadRepository,
        DeviceTokenRepository {
  String get userId;
  Future<UserSummary?> account();
  Future<bool> companionInstalled();
  Future<Map<String, ProfileStats>> profiles(Set<String> ids) async {
    final rows = await Future.wait(ids.map(profile));
    return {for (final value in rows) value.user.id: value};
  }

  Future<RideFeed> rideFeed() async {
    final rows = await rides();
    return (rides: rows, profiles: <String, ProfileStats>{});
  }

  Future<FeatureSnapshot> load() async {
    UserSummary? user;
    String? accountError;
    var feed = (rides: <RideRecord>[], profiles: <String, ProfileStats>{});
    String? rideError;
    var status = CompanionStatus.error;
    String? moduleError;
    ProfileStats? ownProfile;
    List<RatingTask> tasks = [];
    List<Keyword> keywordRows = [];
    bool alertsEnabled = false;
    List<AppNotice> noticeRows = [];
    List<UserSummary> blockRows = [];
    final featureErrors = <CompanionFeature, String>{};
    Map<String, ProfileStats> hostStats = {};
    String message(Object error) =>
        error is FeatureFailure ? error.message : '연결 상태를 확인하고 다시 시도해 주세요.';
    // One module failure must not discard another module's real results.
    await Future.wait([
      (() async {
        try {
          user = await account().timeout(const Duration(seconds: 20));
        } catch (e) {
          accountError = message(e);
        }
      })(),
      (() async {
        try {
          feed = await rideFeed().timeout(const Duration(seconds: 20));
        } catch (e) {
          rideError = message(e);
        }
      })(),
      (() async {
        try {
          if (!await companionInstalled().timeout(
            const Duration(seconds: 20),
          )) {
            status = CompanionStatus.missing;
            return;
          }
          status = CompanionStatus.ready;
        } catch (e) {
          moduleError = message(e);
        }
      })(),
    ]);
    Future<void> readFeature(
      CompanionFeature feature,
      Future<void> Function() read,
    ) async {
      try {
        await read().timeout(const Duration(seconds: 20));
      } catch (e) {
        featureErrors[feature] = message(e);
      }
    }

    if (status == CompanionStatus.ready) {
      await Future.wait([
        readFeature(CompanionFeature.profile, () async {
          final data = await Future.wait<Object>([
            profile(userId),
            ratingTasks(),
            profiles(feed.rides.map((r) => r.host.id).toSet()),
          ]);
          ownProfile = data[0] as ProfileStats;
          tasks = data[1] as List<RatingTask>;
          hostStats = data[2] as Map<String, ProfileStats>;
        }),
        readFeature(CompanionFeature.keywords, () async {
          final data = await Future.wait<Object>([
            keywords(),
            keywordAlertsEnabled(),
            notices(),
          ]);
          keywordRows = data[0] as List<Keyword>;
          alertsEnabled = data[1] as bool;
          noticeRows = data[2] as List<AppNotice>;
        }),
        readFeature(CompanionFeature.blocking, () async {
          blockRows = await blockedUsers();
        }),
      ]);
    }
    return FeatureSnapshot(
      account: user,
      accountError: accountError,
      profile: ownProfile,
      keywords: keywordRows,
      keywordAlertsEnabled: alertsEnabled,
      blockedUsers: blockRows,
      rides: feed.rides,
      rideError: rideError,
      companionStatus: status,
      companionError: moduleError,
      featureErrors: Map.unmodifiable(featureErrors),
      ratingTasks: tasks,
      notices: noticeRows,
      hostStats: hostStats,
    );
  }
}
