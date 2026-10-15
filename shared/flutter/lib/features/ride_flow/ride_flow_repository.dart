import 'package:supabase_flutter/supabase_flutter.dart';

import '../companion/models.dart';

/// F-04·F-05·F-06 data layer. SQL names live here only
/// (supabase/migrations/202610130000_f04_f05_f06.sql).
class RideFlowRepository {
  RideFlowRepository(this.client);
  final SupabaseClient client;

  String get userId =>
      client.auth.currentUser?.id ?? (throw const FeatureFailure('로그인이 필요해요.'));

  // F-04 ---------------------------------------------------------------------
  Future<void> requestJoin(String rideId) =>
      _call('request_join', {'p_ride_id': rideId});
  Future<void> approve(String rideId, String applicantId) => _call(
    'approve_applicant',
    {'p_ride_id': rideId, 'p_user_id': applicantId},
  );
  Future<void> reject(String rideId, String applicantId) => _call(
    'reject_applicant',
    {'p_ride_id': rideId, 'p_user_id': applicantId},
  );
  Future<void> kick(String rideId, String memberId) => _call(
    'kick_participant',
    {'p_ride_id': rideId, 'p_user_id': memberId},
  );

  /// Participant leaves, or an applicant withdraws a pending request.
  Future<void> leave(String rideId) => _call('leave_ride', {'p_ride_id': rideId});
  Future<void> cancelRide(String rideId) =>
      _call('cancel_ride', {'p_ride_id': rideId});

  /// Pending applicants with their profile numbers (F-07) and block marks (F-10).
  /// Missing optional modules only hide those extras.
  Future<List<RideApplicant>> applicants(String rideId) => _guard(() async {
    final rows = await client.rpc(
      'list_ride_applicants',
      params: {'p_ride_id': rideId},
    );
    final users = (rows as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .map((m) => (id: m['id'] as String, name: m['display_name'] as String))
        .toList();
    final stats = <String, Map<String, dynamic>>{};
    var blocked = <String>{};
    if (users.isNotEmpty) {
      try {
        final ids = users.map((u) => u.id).toList();
        for (var i = 0; i < ids.length; i += 20) {
          final part = ids.sublist(i, i + 20 > ids.length ? ids.length : i + 20);
          final summaries = await client.rpc(
            'get_profile_summaries',
            params: {'p_user_ids': part},
          );
          for (final row in summaries as List) {
            final m = Map<String, dynamic>.from(row as Map);
            stats[m['id'] as String] = m;
          }
        }
      } catch (_) {
        // F-07 not installed or not readable: show names only.
      }
      try {
        final rows = await client.rpc('list_my_blocks');
        blocked = (rows as List)
            .map((v) => (v as Map)['id'] as String)
            .toSet();
      } catch (_) {
        // F-10 not installed.
      }
    }
    return users.map((u) {
      final s = stats[u.id];
      return RideApplicant(
        id: u.id,
        name: u.name,
        hasStats: s != null,
        averageRating: (s?['average_rating'] as num?)?.toDouble(),
        participationCount: (s?['participation_count'] as num?)?.toInt() ?? 0,
        noShowCount: (s?['no_show_count'] as num?)?.toInt() ?? 0,
        blocked: blocked.contains(u.id),
      );
    }).toList();
  });

  // F-05 ---------------------------------------------------------------------
  Future<List<RideChatMessage>> messages(String rideId) => _guard(() async {
    final rows = await client
        .from('ride_messages')
        .select('id,ride_id,sender_id,sender_name,kind,body,created_at')
        .eq('ride_id', rideId)
        .order('id', ascending: false)
        .limit(300);
    return rows.map(RideChatMessage.fromJson).toList().reversed.toList();
  });

  Future<RideChatMessage> send(String rideId, String body) => _guard(() async {
    final row = await client.rpc(
      'send_ride_message',
      params: {'p_ride_id': rideId, 'p_body': body},
    );
    return RideChatMessage.fromJson(Map<String, dynamic>.from(row as Map));
  });

  /// New messages (including system notices) for one ride. RLS applies.
  RealtimeChannel subscribe(
    String rideId,
    void Function(RideChatMessage message) onMessage,
  ) {
    final channel = client.channel('ride-chat-$rideId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ride_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ride_id',
            value: rideId,
          ),
          callback: (payload) {
            try {
              onMessage(RideChatMessage.fromJson(payload.newRecord));
            } catch (_) {
              // Ignore malformed events; the next reload shows the stored rows.
            }
          },
        )
        .subscribe();
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await client.removeChannel(channel);
    } catch (_) {}
  }

  // F-06 ---------------------------------------------------------------------
  Future<RideFlowState> state(String rideId) => _guard(() async {
    final row = await client.rpc(
      'get_ride_flow_state',
      params: {'p_ride_id': rideId},
    );
    return RideFlowState.fromJson(Map<String, dynamic>.from(row as Map));
  });
  Future<void> confirmBoarding(String rideId) =>
      _call('confirm_boarding', {'p_ride_id': rideId});
  Future<void> answerAbsence(String rideId, String memberId, bool present) =>
      _call('answer_absence', {
        'p_ride_id': rideId,
        'p_user_id': memberId,
        'p_present': present,
      });
  Future<void> confirmArrival(String rideId) =>
      _call('confirm_arrival', {'p_ride_id': rideId});

  // --------------------------------------------------------------------------
  Future<void> _call(String fn, Map<String, dynamic> params) =>
      _guard(() async {
        await client.rpc(fn, params: params);
      });

  Future<T> _guard<T>(Future<T> Function() action) async {
    userId;
    try {
      return await action().timeout(const Duration(seconds: 20));
    } on PostgrestException catch (e) {
      // Missing function / table: this feature's migration is not applied yet.
      if (const {'PGRST202', 'PGRST205', '42883', '42P01'}.contains(e.code)) {
        throw const FeatureFailure(rideFlowMissingMessage);
      }
      final known = _messages[e.message];
      if (known != null) throw FeatureFailure(known);
      if (e.code == '42501') throw const FeatureFailure('이 작업을 할 수 있는 권한이 없어요.');
      throw const FeatureFailure('요청을 처리하지 못했어요. 다시 불러온 뒤 시도해 주세요.');
    } on AuthException {
      throw const FeatureFailure('로그인 상태를 확인해 주세요.');
    }
  }

  static const _messages = {
    'ride_missing': '팟을 찾을 수 없어요. 다시 불러와 주세요.',
    'join_host': '내가 만든 팟에는 신청할 수 없어요.',
    'join_kicked': '방장이 내보낸 팟에는 다시 신청할 수 없어요.',
    'join_closed': '모집이 끝났거나 출발 시각이 지난 팟이에요.',
    'join_full': '정원이 모두 찼어요.',
    'host_only': '방장만 할 수 있어요.',
    'applicant_missing': '이미 처리된 신청이에요. 다시 불러와 주세요.',
    'participant_missing': '이미 나간 참여자예요. 다시 불러와 주세요.',
    'kick_closed': '출발 확인이 끝난 뒤에는 내보낼 수 없어요.',
    'leave_closed': '출발 확인이 끝난 뒤에는 나갈 수 없어요.',
    'host_cannot_leave': '방장은 나갈 수 없어요. 대신 팟을 취소할 수 있어요.',
    'not_participant': '이 팟의 참여자가 아니에요.',
    'cancel_closed': '출발 확인이 끝난 팟은 취소할 수 없어요.',
    'chat_closed': '채팅방이 닫혔거나 참여자가 아니에요.',
    'message_invalid': '메시지는 1~1000자로 입력해 주세요.',
    'boarding_closed': '출발 확인이 이미 끝났어요.',
    'boarding_not_open': '출발 시각이 되면 탑승을 확인할 수 있어요.',
    'marked_absent': '다른 참여자가 참여 안 함으로 기록했어요.',
    'answer_ineligible': '탑승을 확인한 참여자만 할 수 있어요.',
    'absence_invalid': '확인할 참여자를 다시 선택해 주세요.',
    'absence_resolved': '이미 확인된 참여자예요.',
    'arrival_closed': '도착을 확인할 수 있는 상태가 아니에요.',
  };
}

const rideFlowMissingMessage =
    'F-04·F-05·F-06 마이그레이션이 적용되지 않았어요. 적용 후 다시 불러와 주세요.';

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.parse(value as String).toUtc();

class RideApplicant {
  const RideApplicant({
    required this.id,
    required this.name,
    required this.hasStats,
    this.averageRating,
    this.participationCount = 0,
    this.noShowCount = 0,
    this.blocked = false,
  });
  final String id;
  final String name;
  final bool hasStats;
  final double? averageRating;
  final int participationCount;
  final int noShowCount;
  final bool blocked;
  String get statsLabel => !hasStats
      ? '프로필 정보 없음'
      : '★ ${averageRating == null ? '평가 부족' : averageRating!.toStringAsFixed(1)}'
            ' · 총 참여 $participationCount회 · 참여 안 함 $noShowCount회';
}

class RideChatMessage {
  const RideChatMessage({
    required this.id,
    required this.system,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.senderName,
  });
  factory RideChatMessage.fromJson(Map<String, dynamic> json) => RideChatMessage(
    id: (json['id'] as num).toInt(),
    system: json['kind'] == 'system',
    body: json['body'] as String,
    createdAt: _date(json['created_at']) ?? DateTime.now().toUtc(),
    senderId: json['sender_id'] as String?,
    senderName: json['sender_name'] as String?,
  );
  final int id;
  final bool system;
  final String body;
  final DateTime createdAt;
  final String? senderId;
  final String? senderName;
}

/// before → boarding(출발 확인) → departed(이동 중) → ended / cancelled
enum RidePhase { before, boarding, departed, ended, cancelled }

class RideFlowMember {
  const RideFlowMember({
    required this.id,
    required this.name,
    required this.isHost,
    this.boardedAt,
    this.noShow = false,
  });
  final String id;
  final String name;
  final bool isHost;
  final DateTime? boardedAt;
  final bool noShow;
  bool get boarded => boardedAt != null && !noShow;
  bool get unresolved => boardedAt == null && !noShow;
}

class RideFlowState {
  const RideFlowState({
    required this.rideId,
    required this.hostId,
    required this.status,
    required this.capacity,
    required this.occupancy,
    required this.departureAt,
    required this.phase,
    required this.absenceDeadline,
    required this.chatExpiresAt,
    required this.members,
    this.departedAt,
    this.endedAt,
    this.autoEndAt,
    this.pendingCount = 0,
  });
  factory RideFlowState.fromJson(Map<String, dynamic> json) => RideFlowState(
    rideId: json['ride_id'] as String,
    hostId: json['host_id'] as String,
    status: json['status'] as String,
    capacity: (json['capacity'] as num).toInt(),
    occupancy: (json['occupancy'] as num).toInt(),
    departureAt: _date(json['departure_at'])!,
    departedAt: _date(json['departed_at']),
    endedAt: _date(json['ended_at']),
    autoEndAt: _date(json['auto_end_at']),
    absenceDeadline: _date(json['absence_deadline'])!,
    chatExpiresAt: _date(json['chat_expires_at'])!,
    pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
    phase: RidePhase.values.firstWhere(
      (p) => p.name == json['phase'],
      orElse: () => RidePhase.before,
    ),
    members: (json['members'] as List? ?? const []).map((v) {
      final m = Map<String, dynamic>.from(v as Map);
      return RideFlowMember(
        id: m['id'] as String,
        name: m['display_name'] as String,
        isHost: m['is_host'] as bool? ?? false,
        boardedAt: _date(m['boarded_at']),
        noShow: m['no_show'] as bool? ?? false,
      );
    }).toList(),
  );
  final String rideId;
  final String hostId;
  final String status;
  final int capacity;
  final int occupancy;
  final DateTime departureAt;
  final DateTime? departedAt;
  final DateTime? endedAt;
  final DateTime? autoEndAt;
  final DateTime absenceDeadline;
  final DateTime chatExpiresAt;
  final int pendingCount;
  final RidePhase phase;
  final List<RideFlowMember> members;

  RideFlowMember? member(String userId) =>
      members.where((m) => m.id == userId).firstOrNull;

  /// Kick / leave / cancel are allowed until 출발 처리 (spec F-04).
  bool get changesAllowed =>
      phase == RidePhase.before || phase == RidePhase.boarding;
}
