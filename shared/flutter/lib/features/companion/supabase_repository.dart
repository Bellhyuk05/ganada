import 'dart:convert';
import 'dart:ui' as ui;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repositories.dart';

/// SQL identifiers live here. Adapt this layer after the team approves the contract.
class SupabaseCompanionRepository extends CompanionRepository {
  SupabaseCompanionRepository(this.client);
  final SupabaseClient client;
  @override
  Future<bool> companionInstalled() => _guard(() async {
    final value = await client.rpc('get_gachita_capabilities');
    if (value is! Map || value['f07_f08_f10'] is! bool) {
      throw const FeatureFailure('공통 DB 계약을 확인해 주세요.');
    }
    return value['f07_f08_f10'] as bool;
  });
  @override
  Future<UserSummary?> account() => _guard(() async {
    final row = await client
        .from('profiles')
        .select('id,display_name')
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : _user(row);
  });
  @override
  Future<Map<String, ProfileStats>> profiles(Set<String> ids) =>
      _guard(() async {
        if (ids.isEmpty) return {};
        final result = <String, ProfileStats>{};
        final requested = ids.toList();
        // Photo-bearing responses are bounded to 20 users per request.
        for (var offset = 0; offset < requested.length; offset += 20) {
          final end = offset + 20 < requested.length
              ? offset + 20
              : requested.length;
          final rows = await client.rpc(
            'get_profile_summaries',
            params: {'p_user_ids': requested.sublist(offset, end)},
          );
          for (final row in rows as List) {
            final value = _profile(Map<String, dynamic>.from(row as Map));
            result[value.user.id] = value;
          }
        }
        return result;
      });
  @override
  String get userId =>
      client.auth.currentUser?.id ?? (throw const FeatureFailure('로그인이 필요해요.'));
  Future<T> _guard<T>(Future<T> Function() action) async {
    userId;
    try {
      return await action();
    } on PostgrestException catch (e) {
      const messages = {
        'rating_closed': '평가 기간이 지났거나 평가할 수 없는 운행이에요.',
        'rating_ineligible': '실제로 함께 탑승한 사용자만 평가할 수 있어요.',
        'rating_invalid': '평가 대상과 점수를 확인해 주세요.',
        'rating_immutable': '이미 제출한 평가는 바꿀 수 없어요.',
        'keyword_limit': '키워드는 최대 5개까지 등록할 수 있어요.',
        'keyword_empty': '키워드를 입력해 주세요.',
        'self_block': '자기 자신을 차단할 수 없어요.',
        'host_only': '방장만 신청자 목록을 볼 수 있어요.',
        'photo_invalid': '사진 형식이나 크기를 확인해 주세요. PNG·64KiB·256px 이하만 저장할 수 있어요.',
        'profile_missing': '프로필이 아직 준비되지 않았어요.',
      };
      if (e.code == '23505') {
        throw const FeatureFailure('이미 등록된 항목이에요. 다시 불러와 주세요.');
      }
      if (e.code == '42501') throw const FeatureFailure('이 작업을 수행할 권한이 없어요.');
      throw FeatureFailure(messages[e.message] ?? '정보를 처리하지 못했어요. 다시 시도해 주세요.');
    } on AuthException {
      throw const FeatureFailure('로그인 상태를 확인해 주세요.');
    }
  }

  UserSummary _user(Map<String, dynamic> data) => UserSummary(
    id: data['id'] as String,
    name: (data['display_name'] ?? data['name']) as String,
    photo: ProfilePhoto.fromResponse(data['photo_base64']),
  );
  RideRecord _ride(Map<String, dynamic> data, {UserSummary? host}) =>
      RideRecord(
        id: data['id'] as String,
        host: host ?? _user(Map<String, dynamic>.from(data['host'] as Map)),
        from: data['origin_name'] as String,
        to: data['destination_name'] as String,
        condition: data['condition_text'] as String? ?? '',
        departureAt: DateTime.parse(data['departure_at'] as String).toUtc(),
        status: data['status'] as String,
        capacity: data['capacity'] as int,
        departedAt: _date(data['departed_at']),
        endedAt: _date(data['ended_at']),
        members: (data['members'] as List? ?? []).map((v) {
          final m = Map<String, dynamic>.from(v as Map);
          return RideMember(
            user: _user(Map<String, dynamic>.from(m['user'] as Map)),
            status: m['status'] as String,
            boardedAt: _date(m['boarded_at']),
            noShow: m['no_show'] as bool? ?? false,
          );
        }).toList(),
      );
  DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();

  ProfileStats _profile(Map<String, dynamic> row) => ProfileStats(
    user: _user(row),
    averageRating: (row['average_rating'] as num?)?.toDouble(),
    participationCount: row['participation_count'] as int? ?? 0,
    noShowCount: row['no_show_count'] as int? ?? 0,
  );

  @override
  Future<ProfileStats> profile(String userId) => _guard(() async {
    final rows = await client.rpc(
      'get_profile_summaries',
      params: {
        'p_user_ids': [userId],
      },
    );
    final values = rows as List;
    if (values.isEmpty) throw const FeatureFailure('프로필을 찾을 수 없어요.');
    return _profile(Map<String, dynamic>.from(values.single as Map));
  });
  @override
  Future<void> saveProfilePhoto(ProfilePhoto? photo) => _guard(() async {
    ProfilePhoto? normalized;
    if (photo != null) {
      try {
        final codec = await ui.instantiateImageCodec(photo.bytes);
        try {
          if (codec.frameCount != 1) {
            throw const FeatureFailure('정적 PNG 사진만 저장할 수 있어요.');
          }
          final frame = await codec.getNextFrame();
          try {
            if (frame.image.width > ProfilePhoto.maxDimension ||
                frame.image.height > ProfilePhoto.maxDimension) {
              throw const FeatureFailure('사진은 가로·세로 256px 이하여야 해요.');
            }
            final encoded = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (encoded == null) {
              throw const FeatureFailure('프로필 사진을 처리하지 못했어요.');
            }
            normalized = ProfilePhoto.fromPng(
              encoded.buffer.asUint8List(
                encoded.offsetInBytes,
                encoded.lengthInBytes,
              ),
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } on FeatureFailure {
        rethrow;
      } catch (_) {
        throw const FeatureFailure('정상적으로 읽을 수 있는 PNG 사진을 선택해 주세요.');
      }
    }
    await client.rpc(
      'set_my_profile_photo',
      params: {
        'p_photo_base64': normalized == null
            ? null
            : base64Encode(normalized.bytes),
      },
    );
  });
  Future<RideFeed> _readRideFeed({String? rideId}) async {
    var query = client
        .from('rides')
        .select(
          'id,host_id,origin_name,destination_name,condition_text,capacity,departure_at,departed_at,ended_at,status',
        );
    if (rideId != null) query = query.eq('id', rideId);
    final rows = await query.order('departure_at').limit(100);
    if (rows.isEmpty) {
      return (rides: <RideRecord>[], profiles: <String, ProfileStats>{});
    }
    final roster = await client.rpc(
      'list_ride_profiles',
      params: {'p_ride_ids': rows.map((r) => r['id']).toList()},
    );
    final members = <String, List<Map<String, dynamic>>>{};
    for (final row in roster as List) {
      final m = Map<String, dynamic>.from(row as Map);
      members.putIfAbsent(m['ride_id'] as String, () => []).add({
        // Only presentation data; never raw boarding/no-show/history rows.
        'status': 'approved',
        'user': {'id': m['user_id'], 'display_name': m['display_name']},
      });
    }
    // F-04: the caller's own pending request, shown as "승인 기다리는 중".
    // RLS (memberships_read_self) returns only the caller's own rows.
    try {
      final mine = await client
          .from('ride_memberships')
          .select('ride_id')
          .eq('user_id', userId)
          .eq('status', 'pending')
          .inFilter('ride_id', rows.map((r) => r['id']).toList());
      for (final m in mine) {
        members.putIfAbsent(m['ride_id'] as String, () => []).add({
          'status': 'pending',
          'user': {'id': userId, 'display_name': '나'},
        });
      }
    } catch (_) {
      // Pending state is a convenience; the feed still loads without it.
    }
    final rowsOfHosts = await client.rpc(
      'get_user_summaries',
      params: {
        'p_user_ids': rows.map((r) => r['host_id'] as String).toSet().toList(),
      },
    );
    final hosts = <String, UserSummary>{};
    for (final row in rowsOfHosts as List) {
      final user = _user(Map<String, dynamic>.from(row as Map));
      hosts[user.id] = user;
    }
    final records = rows
        .map(
          (r) => _ride({
            ...r,
            'members': members[r['id']] ?? [],
          }, host: hosts[r['host_id']]!),
        )
        .toList();
    return (rides: records, profiles: <String, ProfileStats>{});
  }

  @override
  Future<RideFeed> rideFeed() => _guard(() => _readRideFeed());
  @override
  Future<List<RideRecord>> rides() =>
      _guard(() async => (await _readRideFeed()).rides);
  @override
  Future<RideRecord?> ride(String rideId) => _guard(
    () async => (await _readRideFeed(rideId: rideId)).rides.firstOrNull,
  );
  @override
  Future<List<UserSummary>> applicants(String rideId) => _guard(() async {
    final rows = await client.rpc(
      'list_ride_applicants',
      params: {'p_ride_id': rideId},
    );
    return (rows as List)
        .map((v) => _user(Map<String, dynamic>.from(v as Map)))
        .toList();
  });
  @override
  Future<List<RatingTask>> ratingTasks() => _guard(() async {
    final rows = await client.rpc('list_rating_tasks');
    return (rows as List).map((v) {
      final t = Map<String, dynamic>.from(v as Map);
      return RatingTask(
        ride: _ride(Map<String, dynamic>.from(t['ride'] as Map)),
        targets: (t['targets'] as List)
            .map((u) => _user(Map<String, dynamic>.from(u as Map)))
            .toList(),
        submittedUserIds: (t['submitted_user_ids'] as List)
            .cast<String>()
            .toSet(),
      );
    }).toList();
  });
  @override
  Future<void> submitRatings(String rideId, List<RatingInput> inputs) =>
      _guard(() async {
        await client.rpc(
          'submit_ratings',
          params: {
            'p_ride_id': rideId,
            'p_inputs': inputs.map((i) => i.toJson()).toList(),
          },
        );
      });
  @override
  Future<List<Keyword>> keywords() => _guard(() async {
    final rows = await client
        .from('user_keywords')
        .select('id,text,enabled')
        .eq('user_id', userId)
        .order('created_at');
    return rows
        .map(
          (r) => Keyword(
            id: r['id'] as String,
            text: r['text'] as String,
            enabled: r['enabled'] as bool,
          ),
        )
        .toList();
  });
  @override
  Future<bool> keywordAlertsEnabled() => _guard(
    () async =>
        (await client
                .from('notification_preferences')
                .select('keyword_enabled')
                .eq('user_id', userId)
                .maybeSingle())?['keyword_enabled']
            as bool? ??
        true,
  );
  @override
  Future<void> addKeyword(String text) => _guard(() async {
    await client.rpc('add_keyword', params: {'p_text': text});
  });
  @override
  Future<void> removeKeyword(String keywordId) => _guard(() async {
    await client
        .from('user_keywords')
        .delete()
        .eq('user_id', userId)
        .eq('id', keywordId);
  });
  @override
  Future<void> setKeywordEnabled(String keywordId, bool enabled) =>
      _guard(() async {
        final row = await client
            .from('user_keywords')
            .update({'enabled': enabled})
            .eq('user_id', userId)
            .eq('id', keywordId)
            .select('id')
            .maybeSingle();
        if (row == null) {
          throw const FeatureFailure('키워드가 없거나 변경할 수 없어요. 다시 불러와 주세요.');
        }
      });
  @override
  Future<void> setKeywordAlerts(bool enabled) => _guard(() async {
    await client.from('notification_preferences').upsert({
      'user_id': userId,
      'keyword_enabled': enabled,
    });
  });
  @override
  Future<List<UserSummary>> blockedUsers() => _guard(() async {
    final rows = await client.rpc('list_my_blocks');
    return (rows as List)
        .map((u) => _user(Map<String, dynamic>.from(u as Map)))
        .toList();
  });
  @override
  Future<void> block(String targetId) => _guard(() async {
    await client.rpc('block_user', params: {'p_target_id': targetId});
  });
  @override
  Future<void> unblock(String targetId) => _guard(() async {
    await client
        .from('user_blocks')
        .delete()
        .eq('blocker_id', userId)
        .eq('blocked_id', targetId);
  });
  @override
  Future<List<UserSummary>> blockedParticipants(String rideId) =>
      _guard(() async {
        final rows = await client.rpc(
          'blocked_ride_participants',
          params: {'p_ride_id': rideId},
        );
        return (rows as List)
            .map((u) => _user(Map<String, dynamic>.from(u as Map)))
            .toList();
      });
  @override
  Future<List<AppNotice>> notices() => _guard(() async {
    final rows = await client
        .from('keyword_notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);
    return rows
        .map(
          (r) => AppNotice(
            id: r['id'] as String,
            rideId: r['ride_id'] as String,
            title: r['title'] as String,
            body: r['body'] as String,
            createdAt: _date(r['created_at'])!,
            readAt: _date(r['read_at']),
          ),
        )
        .toList();
  });
  @override
  Future<void> markNoticeRead(String noticeId) => _guard(() async {
    await client.rpc(
      'mark_keyword_notice_read',
      params: {'p_notice_id': noticeId},
    );
  });
  @override
  Future<void> registerDeviceToken(String token) => _guard(() async {
    await client.rpc('register_device_token', params: {'p_token': token});
  });
  @override
  Future<void> removeDeviceToken(String token) => _guard(() async {
    await client
        .from('device_tokens')
        .delete()
        .eq('user_id', userId)
        .eq('token', token);
  });
}
