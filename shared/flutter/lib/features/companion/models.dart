import 'dart:convert';
import 'dart:typed_data';

String normalizeKeyword(String text) => text.trim().toLowerCase();

/// Small, static PNG bytes. No URL, filename, EXIF or animation is retained.
class ProfilePhoto {
  ProfilePhoto._(Uint8List value) : bytes = value.asUnmodifiableView();
  static const maxBytes = 64 * 1024;
  static const maxDimension = 256;
  final Uint8List bytes;

  factory ProfilePhoto.fromPng(Uint8List source) {
    if (source.length < 45 || source.length > maxBytes) {
      throw const FeatureFailure('프로필 사진은 64KiB 이하의 PNG여야 해요.');
    }
    final data = ByteData.sublistView(source);
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < signature.length; i++) {
      if (source[i] != signature[i]) {
        throw const FeatureFailure('정적 PNG 사진만 저장할 수 있어요.');
      }
    }
    final width = data.getUint32(16);
    final height = data.getUint32(20);
    if (width < 1 ||
        height < 1 ||
        width > maxDimension ||
        height > maxDimension ||
        source[24] != 8 ||
        ![2, 6].contains(source[25]) ||
        source[26] != 0 ||
        source[27] != 0 ||
        source[28] != 0) {
      throw const FeatureFailure('사진은 가로·세로 256px 이하의 8비트 PNG여야 해요.');
    }
    final clean = BytesBuilder(copy: true)..add(signature);
    var offset = 8;
    var hasData = false;
    while (offset + 12 <= source.length) {
      final length = data.getUint32(offset);
      final end = offset + length + 12;
      if (end > source.length) {
        break;
      }
      final type = ascii.decode(
        source.sublist(offset + 4, offset + 8),
        allowInvalid: true,
      );
      if ((offset == 8 && (type != 'IHDR' || length != 13)) ||
          (offset != 8 && type == 'IHDR') ||
          ['acTL', 'fcTL', 'fdAT'].contains(type)) {
        break;
      }
      if (type == 'IDAT') {
        hasData = hasData || length > 0;
      }
      if (['IHDR', 'IDAT', 'IEND'].contains(type)) {
        clean.add(source.sublist(offset, end));
      } else if (type.codeUnitAt(0) < 97) {
        // Unknown critical chunks, including indexed palette images, are rejected.
        break;
      }
      if (type == 'IEND') {
        if (length != 0 || end != source.length || !hasData) break;
        return ProfilePhoto._(clean.takeBytes());
      }
      offset = end;
    }
    throw const FeatureFailure('프로필 사진 데이터를 확인해 주세요.');
  }

  static ProfilePhoto? fromResponse(dynamic encoded) {
    if (encoded == null) return null;
    if (encoded is! String || encoded.length > 87384) return null;
    try {
      return ProfilePhoto.fromPng(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }
}

class FeatureFailure implements Exception {
  const FeatureFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class UserSummary {
  const UserSummary({required this.id, required this.name, this.photo});
  final String id;
  final String name;
  final ProfilePhoto? photo;
}

class ProfileStats {
  const ProfileStats({
    required this.user,
    this.averageRating,
    this.participationCount = 0,
    this.noShowCount = 0,
  });
  final UserSummary user;
  final double? averageRating;
  final int participationCount;
  final int noShowCount;
  String get ratingLabel =>
      averageRating == null ? '평가 부족' : averageRating!.toStringAsFixed(1);
}

class RideMember {
  const RideMember({
    required this.user,
    required this.status,
    this.boardedAt,
    this.noShow = false,
  });
  final UserSummary user;
  final String status;
  final DateTime? boardedAt;
  final bool noShow;
  bool get actuallyRode => status == 'approved' && boardedAt != null && !noShow;
}

class RideRecord {
  const RideRecord({
    required this.id,
    required this.host,
    required this.from,
    required this.to,
    required this.condition,
    required this.departureAt,
    required this.status,
    required this.capacity,
    required this.members,
    this.departedAt,
    this.endedAt,
  });
  final String id;
  final UserSummary host;
  final String from;
  final String to;
  final String condition;
  final DateTime departureAt;
  final DateTime? departedAt;
  final DateTime? endedAt;
  final String status;
  final int capacity;
  final List<RideMember> members;
  List<RideMember> get participants =>
      members.where((m) => m.status == 'approved').toList();
  DateTime? get ratingDeadline => endedAt?.add(const Duration(days: 3));
  bool ratingOpen(DateTime now) =>
      status == 'completed' &&
      departedAt != null &&
      endedAt != null &&
      !now.isBefore(endedAt!) &&
      now.isBefore(ratingDeadline!);
}

class RatingTask {
  const RatingTask({
    required this.ride,
    required this.targets,
    required this.submittedUserIds,
  });
  final RideRecord ride;
  final List<UserSummary> targets;
  final Set<String> submittedUserIds;
  List<UserSummary> get pending =>
      targets.where((u) => !submittedUserIds.contains(u.id)).toList();
}

class RatingInput {
  const RatingInput({
    required this.targetId,
    required this.halfUnits,
    this.block = false,
  });
  final String targetId;

  /// 1..10, representing 0.5..5.0 stars without floating point rounding.
  final int halfUnits;
  final bool block;
  Map<String, Object> toJson() => {
    'target_id': targetId,
    'half_units': halfUnits,
    'block': block,
  };
}

class Keyword {
  const Keyword({required this.id, required this.text, this.enabled = true});
  final String id;
  final String text;
  final bool enabled;
}

class AppNotice {
  const AppNotice({
    required this.id,
    required this.rideId,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
  });
  final String id;
  final String rideId;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
}

enum CompanionStatus { ready, missing, error }

enum CompanionFeature { profile, keywords, blocking }

const companionMissingMessage =
    'F-07·F-08·F-10 마이그레이션이 적용되지 않았어요. 적용 후 다시 불러와 주세요.';

class FeatureSnapshot {
  const FeatureSnapshot({
    this.account,
    this.accountError,
    this.profile,
    this.keywords = const [],
    this.keywordAlertsEnabled = false,
    this.blockedUsers = const [],
    required this.rides,
    this.rideError,
    required this.companionStatus,
    this.companionError,
    this.featureErrors = const {},
    this.ratingTasks = const [],
    this.notices = const [],
    this.hostStats = const {},
  });
  final UserSummary? account;
  final String? accountError;
  final ProfileStats? profile;
  final CompanionStatus companionStatus;
  final String? companionError;
  final Map<CompanionFeature, String> featureErrors;
  final String? rideError;
  bool get companionReady => companionStatus == CompanionStatus.ready;
  bool featureReady(CompanionFeature feature) =>
      companionReady && !featureErrors.containsKey(feature);
  String featureMessage(CompanionFeature feature) =>
      featureErrors[feature] ?? companionMessage;
  String get companionMessage => companionStatus == CompanionStatus.missing
      ? companionMissingMessage
      : companionError ?? '기능 정보를 불러오지 못했어요. 다시 시도해 주세요.';
  final List<Keyword> keywords;
  final bool keywordAlertsEnabled;
  final List<UserSummary> blockedUsers;
  final List<RideRecord> rides;
  final List<RatingTask> ratingTasks;
  final List<AppNotice> notices;
  final Map<String, ProfileStats> hostStats;
  Set<String> get blockedIds => blockedUsers.map((u) => u.id).toSet();
}

/// One feed fetch supplies both the ride rows and their authorized host profiles.
typedef RideFeed = ({
  List<RideRecord> rides,
  Map<String, ProfileStats> profiles,
});
