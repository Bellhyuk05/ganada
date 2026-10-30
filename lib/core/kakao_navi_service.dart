import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SpotItem {
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;

  const SpotItem({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
  });

  factory SpotItem.fromJson(Map<String, dynamic> json) {
    return SpotItem(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? '거점').toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 36.9698,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 127.8715,
    );
  }
}

class RouteInfo {
  final int distanceMeters;       // 총 거리 (미터)
  final int durationSeconds;      // 소요 시간 (초)
  final int taxiFare;             // 카카오 산출 예상 택시비 (원)
  final List<List<double>> path;  // [[위도, 경도], [위도, 경도]...] 경로 점들

  const RouteInfo({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.taxiFare,
    required this.path,
  });

  // km 단위 변환 문자열 (예: "4.2 km")
  String get distanceKmString {
    final km = distanceMeters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  // 분 단위 변환 문자열 (예: "약 12분")
  String get durationMinutesString {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) {
      return '약 $minutes분';
    }
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    return '약 $hours시간 $rem분';
  }
}

class KakaoNaviService {
  // config/development.json의 KAKAO_REST_API_KEY를 읽어옵니다.
  static const String kakaoRestApiKey = String.fromEnvironment(
    'KAKAO_REST_API_KEY',
    defaultValue: 'YOUR_KAKAO_REST_API_KEY',
  );

  static const List<SpotItem> fallbackSpots = [
    SpotItem(
      id: '1',
      name: '교통대 정문',
      category: '캠퍼스',
      latitude: 36.9698,
      longitude: 127.8715,
    ),
    SpotItem(
      id: '2',
      name: '교통대 후문 기숙사',
      category: '캠퍼스',
      latitude: 36.9715,
      longitude: 127.8732,
    ),
    SpotItem(
      id: '3',
      name: '충주역',
      category: '역',
      latitude: 36.9818,
      longitude: 127.9158,
    ),
    SpotItem(
      id: '4',
      name: '충주공용버스터미널',
      category: '터미널',
      latitude: 36.9811,
      longitude: 127.9252,
    ),
    SpotItem(
      id: '5',
      name: '신연수동',
      category: '시내',
      latitude: 36.9856,
      longitude: 127.9348,
    ),
  ];

  static List<SpotItem>? _cachedSpots;

  /// Supabase의 `spots` 테이블에서 거점 목록을 조회하며 실패 시 기본 목록을 반환합니다.
  static Future<List<SpotItem>> fetchSpots() async {
    if (_cachedSpots != null && _cachedSpots!.isNotEmpty) {
      return _cachedSpots!;
    }
    try {
      final response = await Supabase.instance.client
          .from('spots')
          .select()
          .order('id');
      final list = (response as List)
          .map((e) => SpotItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (list.isNotEmpty) {
        _cachedSpots = list;
        return list;
      }
    } catch (e) {
      debugPrint('spots 테이블 조회 폴백 사용: $e');
    }
    _cachedSpots = fallbackSpots;
    return fallbackSpots;
  }

  /// 거점 이름으로 SpotItem 검색
  static Future<SpotItem?> findSpotByName(String name) async {
    final spots = await fetchSpots();
    final trimmed = name.trim();
    for (final s in spots) {
      if (s.name.trim() == trimmed) return s;
    }
    for (final s in spots) {
      if (s.name.contains(trimmed) || trimmed.contains(s.name)) return s;
    }
    return null;
  }

  /// 거리(m)에 따른 동적 줌 레벨 계산
  static int calculateLevel(int distanceMeters) {
    final km = distanceMeters / 1000.0;
    if (km <= 2.0) return 6;        // 단거리 (여백 확보)
    if (km <= 5.0) return 7;        // 2~5km
    if (km <= 10.0) return 8;       // 5~10km (예: 충주역-교통대)
    if (km <= 20.0) return 9;       // 중거리
    return 10;                      // 장거리
  }

  /// 1. 카카오 길찾기 API (거리, 소요시간, 예상 택시비, 경로 좌표)
  static Future<RouteInfo?> getDirections({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    if (kakaoRestApiKey.isNotEmpty &&
        kakaoRestApiKey != 'YOUR_KAKAO_REST_API_KEY') {
      final url = Uri.parse(
        'https://apis-navi.kakaomobility.com/v1/directions?'
            'origin=$startLng,$startLat&'
            'destination=$endLng,$endLat&'
            'priority=RECOMMEND',
      );

      try {
        final response = await http.get(
          url,
          headers: {
            'Authorization': 'KakaoAK $kakaoRestApiKey',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final routes = data['routes'] as List<dynamic>?;
          if (routes != null && routes.isNotEmpty) {
            final firstRoute = routes[0];
            final summary = firstRoute['summary'];
            final distance = summary['distance'] as int? ?? 0;
            final duration = summary['duration'] as int? ?? 0;
            final taxiFare = summary['fare']?['taxi'] as int? ?? 0;

            final List<List<double>> pathCoordinates = [];
            final sections = firstRoute['sections'] as List<dynamic>? ?? [];
            for (final section in sections) {
              final roads = section['roads'] as List<dynamic>? ?? [];
              for (final road in roads) {
                final vertexes = road['vertexes'] as List<dynamic>? ?? [];
                for (int i = 0; i < vertexes.length; i += 2) {
                  final lng = (vertexes[i] as num).toDouble();
                  final lat = (vertexes[i + 1] as num).toDouble();
                  pathCoordinates.add([lat, lng]);
                }
              }
            }

            return RouteInfo(
              distanceMeters: distance,
              durationSeconds: duration,
              taxiFare: taxiFare,
              path: pathCoordinates,
            );
          }
        }
      } catch (e) {
        debugPrint('카카오 내비 API 호출 오류: $e');
      }
    }

    // 카카오 API 키가 없거나 호출 실패 시 하버사인 기반 폴백
    final meters = _haversineMeters(startLat, startLng, endLat, endLng);
    final roadMeters = (meters * 1.35).round();
    final durationSec = math.max(180, (roadMeters / 8.3).round());
    final extraMeters = math.max(0, roadMeters - 1600);
    final estimatedFare = 4800 + ((extraMeters / 131).ceil() * 100);
    return RouteInfo(
      distanceMeters: roadMeters,
      durationSeconds: durationSec,
      taxiFare: estimatedFare,
      path: const [],
    );
  }

  /// 2. 카카오 Static Map 이미지 바이너리 다운로드 (초안의 Uri.https 마커 규격 적용)
  static Future<Uint8List?> fetchStaticMapBytes({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    int distanceMeters = 3000,
    int width = 600,
    int height = 300,
  }) async {
    if (kakaoRestApiKey.isEmpty ||
        kakaoRestApiKey == 'YOUR_KAKAO_REST_API_KEY') {
      return null;
    }

    final centerLat = (startLat + endLat) / 2;
    final centerLng = (startLng + endLng) / 2;
    final level = calculateLevel(distanceMeters);

    final uri = Uri.https(
      'dapi.kakao.com',
      '/v2/maps/staticmap',
      {
        'size': ['${width}x$height'],
        'center': ['$centerLng,$centerLat'],
        'level': ['$level'],
        'markers': [
          'location:$startLng,$startLat',
          'location:$endLng,$endLat',
        ],
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'KakaoAK $kakaoRestApiKey',
        },
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('카카오 정적 지도 다운로드 예외: $e');
    }
    return null;
  }

  static double _haversineMeters(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
            math.cos(lat1 * math.pi / 180.0) *
                math.cos(lat2 * math.pi / 180.0) *
                math.sin(dLon / 2) *
                math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
}