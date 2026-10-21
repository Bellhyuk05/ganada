import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/team_features.dart';
import '../companion/models.dart';

/// F-02 동행팟 등록. `TeamFeatureBindings.onCreateRide` 에 연결한다.
/// 서버(create_ride RPC)가 팟 생성과 방장 참여 등록을 한 번에 처리하고 새 팟 ID 를 돌려준다.
class RideCreateRepository {
  RideCreateRepository(this._client);

  final SupabaseClient _client;

  Future<String> create(RideDraft draft) async {
    try {
      final id = await _client.rpc('create_ride', params: {
        'p_category': draft.category.name,
        'p_origin': draft.originName.trim(),
        'p_destination': draft.destinationName.trim(),
        'p_departure_at': draft.departureAt.toUtc().toIso8601String(),
        'p_capacity': draft.capacity,
        'p_condition': draft.conditionText.trim(),
      });
      return id as String;
    } on PostgrestException catch (e) {
      throw FeatureFailure(_message(e.message));
    }
  }

  static String _message(String raw) {
    const messages = {
      'ride_profile_missing': '프로필이 없어요. 회원가입을 먼저 마쳐 주세요.',
      'ride_category_unavailable': '지금은 택시 팟만 만들 수 있어요.',
      'ride_place_required': '출발지와 도착지를 골라 주세요.',
      'ride_place_too_long': '장소 이름은 40자 이하로 입력해 주세요.',
      'ride_same_place': '출발지와 도착지는 달라야 해요.',
      'ride_time_past': '앞으로 출발할 시각을 골라 주세요.',
      'ride_date_range': '출발 날짜는 오늘부터 7일 후까지만 고를 수 있어요.',
      'ride_time_step': '출발 시각은 15분 단위로 골라 주세요.',
      'ride_capacity': '모집 인원은 본인 포함 2~4명이에요.',
      'ride_condition_too_long': '조건은 100자 이하로 입력해 주세요.',
      'ride_host_limit': '모집 중인 내 팟은 3개까지 만들 수 있어요.',
    };
    for (final entry in messages.entries) {
      if (raw.contains(entry.key)) return entry.value;
    }
    if (raw.contains('Could not find the function')) {
      return '서버에 팟 등록 기능(F-02 SQL)이 아직 적용되지 않았어요.';
    }
    return '팟을 등록하지 못했어요. 잠시 후 다시 시도해 주세요.';
  }
}
