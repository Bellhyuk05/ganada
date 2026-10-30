import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/kakao_navi_service.dart';
import '../core/team_features.dart';
import '../features/companion/controller.dart';
import '../features/companion/models.dart';
import '../features/companion/screens.dart'
    show ProfileAvatar, CompanionModuleNotice, showCompanionProfile;
import 'gachita_theme.dart';

const _primary = Color(0xFF4A6BFF);
const _primaryLight = Color(0xFFF3F6FF);
const _taxi = GachiTaTheme.taxi;
const _ink = GachiTaTheme.ink;
const _muted = GachiTaTheme.muted;
const _subtle = GachiTaTheme.subtle;
const _canvas = GachiTaTheme.canvas;
const _line = GachiTaTheme.line;
const _warning = Color(0xFFFF4848);
const _danger = GachiTaTheme.danger;
const _success = Color(0xFF1DB36B);

String rideDateLabel(DateTime value) {
  final date = value.toLocal();
  return DateFormat('M월 d일(E) HH:mm', 'ko').format(date);
}

class _RideView {
  const _RideView(this.record, this.controller, this.userId);
  final RideRecord record;
  final CompanionController controller;
  final String userId;
  String get id => record.id;
  String get from => record.from;
  String get to => record.to;
  String get host => record.host.name;
  String get condition => record.condition;
  String get when => rideDateLabel(record.departureAt);
  int get people =>
      record.participants.isEmpty ? 1 : record.participants.length;
  int get capacity => record.capacity;
  bool get full => record.status != 'recruiting' || people >= capacity;
  bool get isAlmostFull => (capacity - people) == 1 && !full;
  bool get inProgress =>
      record.departedAt != null &&
          record.endedAt == null &&
          ['recruiting', 'full'].contains(record.status);
  bool get isMine =>
      record.host.id == userId ||
          record.participants.any((m) => m.user.id == userId);
  List<UserSummary> get participants =>
      record.participants.map((m) => m.user).toList();
  ProfileStats? get stats => controller.featureReady(CompanionFeature.profile)
      ? controller.snapshot?.hostStats[record.host.id]
      : null;
  String get ratingLabel => stats?.ratingLabel ?? '정보 없음';
  String get profileLabel => stats == null
      ? '프로필 정보 없음'
      : '★ ${stats!.ratingLabel} · 총 참여 ${stats!.participationCount}회 · 참여 안 함 ${stats!.noShowCount}회';
  String get until {
    if (record.status == 'completed') return '이동 완료';
    if (record.status == 'cancelled') return '취소된 팟';
    if (inProgress) return '이동 중';
    if (full) return '모집 완료';
    final duration = record.departureAt.difference(DateTime.now());
    if (duration.isNegative) return '출발 예정 시각 지남';
    if (duration.inMinutes < 1) return '곧 출발';
    if (duration.inHours < 1) return '출발까지 ${duration.inMinutes}분';
    if (duration.inDays < 1) return '출발까지 ${duration.inHours}시간';
    return '출발까지 ${duration.inDays}일';
  }
}

class _NoticeView {
  const _NoticeView({
    required this.title,
    required this.message,
    this.isRating = false,
    this.onOpen,
  });
  final String title, message;
  final bool isRating;
  final VoidCallback? onOpen;
}

class RidePageHeader extends StatelessWidget {
  const RidePageHeader({super.key, required this.title, this.onBack});
  final String title;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) =>
      _PageHeader(title: title, onBack: onBack);
}

class RideEmptyState extends StatelessWidget {
  const RideEmptyState({
    super.key,
    required this.message,
    this.detail,
    this.action,
  });
  final String message;
  final String? detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _EmptyPage(message: message),
      if (detail != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(detail!, textAlign: TextAlign.center),
        ),
      if (action != null) action!,
    ],
  );
}

class _LiveFrame extends StatelessWidget {
  const _LiveFrame({
    required this.controller,
    required this.child,
    required this.title,
    this.onBack,
    this.feature,
    this.rideQuery = false,
  });
  final CompanionController controller;
  final Widget child;
  final String title;
  final VoidCallback? onBack;
  final CompanionFeature? feature;
  final bool rideQuery;
  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final error = controller.error ?? (rideQuery ? snapshot?.rideError : null);
    if (snapshot == null || (rideQuery && snapshot.rideError != null)) {
      return Column(
        children: [
          _PageHeader(title: title, onBack: onBack),
          Expanded(
            child: Center(
              child: controller.loading && snapshot == null
                  ? const CircularProgressIndicator()
                  : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      error ?? '정보를 불러오지 못했어요.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: controller.loading
                        ? null
                        : controller.refresh,
                    child: const Text('다시 불러오기'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (feature != null && !controller.featureReady(feature!)) {
      return Column(
        children: [
          _PageHeader(title: title, onBack: onBack),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                CompanionModuleNotice(
                  controller: controller,
                  feature: feature!,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        if (controller.loading) const LinearProgressIndicator(minHeight: 2),
        if (error != null)
          Material(
            color: const Color(0xFFFFF4E5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: _danger, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: controller.loading ? null : controller.refresh,
                    child: const Text('다시 불러오기'),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: child),
      ],
    );
  }
}

// ============================================================================
// [커스텀 복원] 메인 홈 화면
// ============================================================================
class GachiTaHomePage extends StatefulWidget {
  const GachiTaHomePage({
    super.key,
    required this.controller,
    required this.onOpenRide,
    required this.onNotifications,
    required this.onKeywords,
    required this.onCreate,
    this.onSearchNearby,
  });
  final CompanionController controller;
  final ValueChanged<RideRecord> onOpenRide;
  final VoidCallback onNotifications, onKeywords, onCreate;
  final Future<Set<String>?> Function(BuildContext)? onSearchNearby;
  @override
  State<GachiTaHomePage> createState() => _GachiTaHomePageState();
}

class _GachiTaHomePageState extends State<GachiTaHomePage> {
  List<SpotItem> _spots = [];

  // 거점 필터 조건
  SpotItem? _filterDepartureSpot;
  SpotItem? _filterDestinationSpot;

  // 상단 빠른 필터 조건
  bool _filterOnlyToday = false;
  bool _filterOnlyImminent = false;
  DateTime? _filterSelectedDate;

  @override
  void initState() {
    super.initState();
    _loadSpots();
  }

  Future<void> _loadSpots() async {
    final spots = await KakaoNaviService.fetchSpots();
    if (mounted) {
      setState(() => _spots = spots);
    }
  }

  void _reset() => setState(() {
    _filterOnlyToday = false;
    _filterOnlyImminent = false;
    _filterSelectedDate = null;
    _filterDepartureSpot = null;
    _filterDestinationSpot = null;
  });

  /// 출발지와 도착지 필터 맞바꾸기
  void _swapFilterSpots() {
    setState(() {
      final temp = _filterDepartureSpot;
      _filterDepartureSpot = _filterDestinationSpot;
      _filterDestinationSpot = temp;
    });
  }

  void _openSpotFilterModal(bool isDeparture) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isDeparture ? '출발지 필터' : '도착지 필터',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (isDeparture) {
                          _filterDepartureSpot = null;
                        } else {
                          _filterDestinationSpot = null;
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('초기화'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: _spots.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final spot = _spots[index];

                    final isAlreadySelectedAsOpposite = isDeparture
                        ? (_filterDestinationSpot != null && _filterDestinationSpot!.id == spot.id)
                        : (_filterDepartureSpot != null && _filterDepartureSpot!.id == spot.id);

                    return ListTile(
                      enabled: !isAlreadySelectedAsOpposite,
                      title: Text(
                        spot.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isAlreadySelectedAsOpposite
                              ? Colors.grey.shade400
                              : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        isAlreadySelectedAsOpposite
                            ? (isDeparture
                            ? '도착지로 설정되어 있어 선택할 수 없습니다'
                            : '출발지로 설정되어 있어 선택할 수 없습니다')
                            : spot.category,
                        style: TextStyle(
                          fontSize: 12,
                          color: isAlreadySelectedAsOpposite
                              ? Colors.red.shade300
                              : Colors.grey.shade600,
                        ),
                      ),
                      trailing: isAlreadySelectedAsOpposite
                          ? const Icon(Icons.block, size: 18, color: Colors.grey)
                          : null,
                      onTap: isAlreadySelectedAsOpposite
                          ? null
                          : () {
                        setState(() {
                          if (isDeparture) {
                            _filterDepartureSpot = spot;
                          } else {
                            _filterDestinationSpot = spot;
                          }
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openDateFilterModal() {
    final now = DateTime.now();
    final dates = List.generate(7, (i) => DateTime(now.year, now.month, now.day + i));

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '날짜 선택 (오늘 ~ 7일)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _filterSelectedDate = null;
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('전체 보기'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: dates.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final d = dates[index];
                    final dateLabel = index == 0
                        ? '오늘 (${DateFormat('M/d(E)', 'ko').format(d)})'
                        : index == 1
                        ? '내일 (${DateFormat('M/d(E)', 'ko').format(d)})'
                        : DateFormat('M월 d일 (E)', 'ko').format(d);

                    final isSelected = _filterSelectedDate != null &&
                        _filterSelectedDate!.year == d.year &&
                        _filterSelectedDate!.month == d.month &&
                        _filterSelectedDate!.day == d.day;

                    return ListTile(
                      title: Text(
                        dateLabel,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? _primary : Colors.black87,
                        ),
                      ),
                      trailing: isSelected ? const Icon(Icons.check, color: _primary) : null,
                      onTap: () {
                        setState(() {
                          _filterSelectedDate = d;
                          _filterOnlyToday = false;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
    bool showChevron = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF4FF) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? _primary : const Color(0xFFE2E6EE),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: isSelected ? _primary : Colors.grey.shade700,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? _primary : Colors.grey.shade800,
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: isSelected ? _primary : Colors.grey.shade600,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot;
    final now = DateTime.now();

    var rows = (snapshot?.rides ?? <RideRecord>[]).where((ride) {
      if (!['recruiting', 'full'].contains(ride.status)) return false;
      return true;
    }).toList();

    if (_filterDepartureSpot != null) {
      rows = rows.where((r) => r.from.toLowerCase().contains(_filterDepartureSpot!.name.toLowerCase())).toList();
    }
    if (_filterDestinationSpot != null) {
      rows = rows.where((r) => r.to.toLowerCase().contains(_filterDestinationSpot!.name.toLowerCase())).toList();
    }

    if (_filterOnlyToday) {
      rows = rows.where((r) {
        final postDt = r.departureAt.toLocal();
        final isSameDay = postDt.year == now.year &&
            postDt.month == now.month &&
            postDt.day == now.day;
        return isSameDay && postDt.isAfter(now);
      }).toList();
    } else if (_filterSelectedDate != null) {
      final sel = _filterSelectedDate!;
      rows = rows.where((r) {
        final postDt = r.departureAt.toLocal();
        return postDt.year == sel.year &&
            postDt.month == sel.month &&
            postDt.day == sel.day;
      }).toList();
    } else {
      rows = rows.where((r) => r.departureAt.toLocal().isAfter(now)).toList();
    }

    if (_filterOnlyImminent) {
      rows = rows.where((r) {
        final currentCount = r.participants.isEmpty ? 1 : r.participants.length;
        final remaining = r.capacity - currentCount;
        return remaining == 1;
      }).toList();
    }

    rows.sort((a, b) => a.departureAt.compareTo(b.departureAt));

    String dateChipLabel = '날짜';
    if (_filterSelectedDate != null) {
      dateChipLabel = DateFormat('M/d(E)', 'ko').format(_filterSelectedDate!);
    }

    final isFiltered = _filterOnlyToday ||
        _filterOnlyImminent ||
        _filterSelectedDate != null ||
        _filterDepartureSpot != null ||
        _filterDestinationSpot != null;

    final canSwap = _filterDepartureSpot != null || _filterDestinationSpot != null;

    return _LiveFrame(
      controller: widget.controller,
      title: '동행팟 찾기',
      rideQuery: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '같이타',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _primary,
                    letterSpacing: -0.5,
                  ),
                ),
                IconButton(
                  onPressed: widget.onNotifications,
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    color: Colors.black87,
                    size: 26,
                  ),
                  tooltip: '알림 보기',
                ),
              ],
            ),
          ),
          Container(
            color: const Color(0xFFF8F9FA),
            padding: const EdgeInsets.only(left: 16, top: 12, bottom: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    label: '오늘',
                    icon: Icons.calendar_today_outlined,
                    isSelected: _filterOnlyToday,
                    onTap: () {
                      setState(() {
                        _filterOnlyToday = !_filterOnlyToday;
                        if (_filterOnlyToday) {
                          _filterSelectedDate = null;
                        }
                      });
                    },
                  ),
                  _buildFilterChip(
                    label: '마감임박',
                    icon: Icons.local_fire_department_outlined,
                    isSelected: _filterOnlyImminent,
                    onTap: () {
                      setState(() {
                        _filterOnlyImminent = !_filterOnlyImminent;
                      });
                    },
                  ),
                  _buildFilterChip(
                    label: dateChipLabel,
                    icon: Icons.date_range_outlined,
                    isSelected: _filterSelectedDate != null,
                    showChevron: true,
                    onTap: () {
                      if (_filterSelectedDate != null) {
                        setState(() {
                          _filterSelectedDate = null;
                        });
                      } else {
                        _openDateFilterModal();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: const Color(0xFFF8F9FA),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      side: BorderSide(
                        color: _filterDepartureSpot != null ? _primary : const Color(0xFFE2E6EE),
                        width: _filterDepartureSpot != null ? 1.5 : 1.0,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: _filterDepartureSpot != null ? const Color(0xFFEFF4FF) : Colors.white,
                      elevation: 0,
                    ),
                    onPressed: () => _openSpotFilterModal(true),
                    icon: Icon(
                      Icons.location_on,
                      size: 16,
                      color: _filterDepartureSpot != null ? _primary : Colors.grey.shade600,
                    ),
                    label: Text(
                      _filterDepartureSpot?.name ?? '출발지 전체',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _filterDepartureSpot != null ? _primary : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: canSwap ? _swapFilterSpots : null,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: canSwap
                              ? _primary.withValues(alpha: 0.5)
                              : const Color(0xFFE2E6EE),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.swap_horiz,
                        size: 18,
                        color: canSwap ? _primary : Colors.grey.shade400,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      side: BorderSide(
                        color: _filterDestinationSpot != null ? _primary : const Color(0xFFE2E6EE),
                        width: _filterDestinationSpot != null ? 1.5 : 1.0,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: _filterDestinationSpot != null ? const Color(0xFFEFF4FF) : Colors.white,
                      elevation: 0,
                    ),
                    onPressed: () => _openSpotFilterModal(false),
                    icon: Icon(
                      Icons.flag,
                      size: 16,
                      color: _filterDestinationSpot != null ? _primary : Colors.grey.shade600,
                    ),
                    label: Text(
                      _filterDestinationSpot?.name ?? '도착지 전체',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _filterDestinationSpot != null ? _primary : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.controller.refresh,
              child: rows.isEmpty && isFiltered
                  ? _NoResultsPage(
                onBack: _reset,
                onKeywords: widget.onKeywords,
                onCreate: widget.onCreate,
              )
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                itemCount: rows.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final view = _RideView(
                    rows[index],
                    widget.controller,
                    widget.controller.repository.userId,
                  );
                  return _RideCard(
                    ride: view,
                    onTap: () => widget.onOpenRide(view.record),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// [커스텀 복원] 개별 팟 카드 위젯
// ============================================================================
class _RideCard extends StatefulWidget {
  const _RideCard({required this.ride, required this.onTap});
  final _RideView ride;
  final VoidCallback onTap;

  @override
  State<_RideCard> createState() => _RideCardState();
}

class _RideCardState extends State<_RideCard> {
  int? _fullFare;

  @override
  void initState() {
    super.initState();
    _fetchFare();
  }

  @override
  void didUpdateWidget(covariant _RideCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ride.id != widget.ride.id) {
      _fetchFare();
    }
  }

  Future<void> _fetchFare() async {
    try {
      final fromSpot = await KakaoNaviService.findSpotByName(widget.ride.from);
      final toSpot = await KakaoNaviService.findSpotByName(widget.ride.to);
      if (fromSpot != null && toSpot != null) {
        final info = await KakaoNaviService.getDirections(
          startLat: fromSpot.latitude,
          startLng: fromSpot.longitude,
          endLat: toSpot.latitude,
          endLng: toSpot.longitude,
        );
        if (mounted && info != null && info.taxiFare > 0 && widget.ride.capacity > 0) {
          final perPerson = (info.taxiFare / widget.ride.capacity).round();
          setState(() {
            _fullFare = ((perPerson + 50) ~/ 100) * 100;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F6FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '택시',
                        style: TextStyle(
                          color: _primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (ride.isAlmostFull) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECEC),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '마감임박',
                          style: TextStyle(
                            color: _warning,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: Colors.grey),
                    const SizedBox(width: 2),
                    Text(
                      '${ride.people}/${ride.capacity}명',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${ride.from}  ➔  ${ride.to}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.schedule, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  ride.when,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '방장 ${ride.host}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (_fullFare != null && _fullFare! > 0)
                  Row(
                    children: [
                      Text(
                        '완전 모집 시 ',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                      Text(
                        '약 ${NumberFormat('#,###').format(_fullFare!)}원',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _primary,
                        ),
                      ),
                    ],
                  )
                else
                  const Text(
                    '완전 모집 시 계산 중…',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// [커스텀 복원] 동행팟 상세 화면
// ============================================================================
class GachiTaRideDetailPage extends StatelessWidget {
  const GachiTaRideDetailPage({
    super.key,
    required this.controller,
    required this.ride,
    required this.userId,
    required this.onBack,
    this.onChat,
    this.onRequestJoin,
    this.onApplicants,
    this.joining = false,
    this.joinUnavailable = false,
  });
  final CompanionController controller;
  final RideRecord ride;
  final String userId;
  final VoidCallback onBack;
  final VoidCallback? onChat, onRequestJoin, onApplicants;
  final bool joining, joinUnavailable;
  @override
  Widget build(BuildContext context) {
    final view = _RideView(ride, controller, userId);
    final requested = ride.members.any(
          (m) => m.user.id == userId && m.status == 'pending',
    );
    return _RideDetailPage(
      ride: view,
      joinRequested: requested,
      blockedUsers: controller.featureReady(CompanionFeature.blocking)
          ? controller.snapshot!.blockedIds
          : {},
      onBack: onBack,
      onRequestJoin: joining ? null : onRequestJoin,
      onOpenChat: view.isMine ? onChat : null,
      onApplicants: onApplicants,
      joinUnavailable: joinUnavailable,
    );
  }
}

class _RideDetailPage extends StatefulWidget {
  const _RideDetailPage({
    required this.ride,
    required this.joinRequested,
    required this.blockedUsers,
    required this.onBack,
    required this.onRequestJoin,
    required this.onOpenChat,
    this.onApplicants,
    this.joinUnavailable = false,
  });

  final _RideView ride;
  final bool joinRequested;
  final Set<String> blockedUsers;
  final VoidCallback onBack;
  final VoidCallback? onRequestJoin;
  final VoidCallback? onOpenChat;
  final VoidCallback? onApplicants;
  final bool joinUnavailable;

  @override
  State<_RideDetailPage> createState() => _RideDetailPageState();
}

class _RideDetailPageState extends State<_RideDetailPage> {
  SpotItem? _fromSpot;
  SpotItem? _toSpot;
  RouteInfo? _routeInfo;
  Uint8List? _mapBytes;
  bool _isLoadingRoute = true;

  @override
  void initState() {
    super.initState();
    _fetchRouteAndMap();
  }

  @override
  void didUpdateWidget(covariant _RideDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ride.id != widget.ride.id ||
        oldWidget.ride.from != widget.ride.from ||
        oldWidget.ride.to != widget.ride.to) {
      _fetchRouteAndMap();
    }
  }

  Future<void> _fetchRouteAndMap() async {
    setState(() => _isLoadingRoute = true);
    try {
      final fromSpot = await KakaoNaviService.findSpotByName(widget.ride.from);
      final toSpot = await KakaoNaviService.findSpotByName(widget.ride.to);
      RouteInfo? route;
      Uint8List? mapBytes;

      if (fromSpot != null && toSpot != null) {
        route = await KakaoNaviService.getDirections(
          startLat: fromSpot.latitude,
          startLng: fromSpot.longitude,
          endLat: toSpot.latitude,
          endLng: toSpot.longitude,
        );

        mapBytes = await KakaoNaviService.fetchStaticMapBytes(
          startLat: fromSpot.latitude,
          startLng: fromSpot.longitude,
          endLat: toSpot.latitude,
          endLng: toSpot.longitude,
          distanceMeters: route?.distanceMeters ?? 3000,
        );
      }
      if (mounted) {
        setState(() {
          _fromSpot = fromSpot;
          _toSpot = toSpot;
          _routeInfo = route;
          _mapBytes = mapBytes;
          _isLoadingRoute = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  String _getRemainingTimeText(DateTime departureDatetime) {
    final now = DateTime.now();
    final diff = departureDatetime.difference(now);

    if (diff.isNegative) {
      return '이미 출발 시간이 지났습니다';
    } else if (diff.inMinutes < 60) {
      return '출발까지 ${diff.inMinutes}분 남음';
    } else if (diff.inHours < 24) {
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      return '출발까지 $hours시간 ${mins > 0 ? '$mins분 ' : ''}남음';
    } else {
      final days = diff.inDays;
      final hours = diff.inHours % 24;
      return '출발까지 $days일 ${hours > 0 ? '$hours시간 ' : ''}남음';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final isFull = ride.full;
    final totalFare = _routeInfo?.taxiFare ?? 0;
    final calculatedPerPersonFare = (ride.capacity > 0 && totalFare > 0)
        ? (((totalFare / ride.capacity).round() + 50) ~/ 100) * 100
        : 0;

    final formattedTime = ride.when;
    final memoText = ride.condition;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '동행팟 상세',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: widget.onBack,
        ),
        actions: [
          if (ride.isMine && widget.onOpenChat != null)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline, color: _primary),
              tooltip: '팟 채팅',
              onPressed: widget.onOpenChat,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: _primaryLight,
                  child: Icon(Icons.person, color: _primary, size: 28),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => showCompanionProfile(
                        context,
                        ride.controller,
                        ride.record.host.id,
                      ),
                      child: Text(
                        ride.host,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          ride.ratingLabel,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '택시 동행',
                    style: TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: _primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _getRemainingTimeText(ride.record.departureAt.toLocal()),
                    style: const TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (memoText.isNotEmpty) ...[
              const Text(
                '요청사항 / 메모',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  memoText,
                  style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
                ),
              ),
              const SizedBox(height: 20),
            ],

            const Text(
              '이동 경로',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 12),

            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                height: 180,
                color: const Color(0xFFF0F3F8),
                child: _isLoadingRoute
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _mapBytes != null
                    ? Image.memory(
                  _mapBytes!,
                  fit: BoxFit.cover,
                )
                    : const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined, color: Colors.grey, size: 36),
                      SizedBox(height: 6),
                      Text('지도를 불러올 수 없습니다', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: _isLoadingRoute
                  ? const Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
                  : Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.straighten, size: 16, color: _primary),
                      const SizedBox(width: 6),
                      Text(
                        '이동거리: ${_routeInfo?.distanceKmString ?? "정보 없음"}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  Container(width: 1, height: 16, color: Colors.grey.shade300),
                  Row(
                    children: [
                      const Icon(Icons.directions_car, size: 16, color: _primary),
                      const SizedBox(width: 6),
                      Text(
                        '소요시간: ${_routeInfo?.durationMinutesString ?? "정보 없음"}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.radio_button_checked, color: _primary, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        ride.from,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    height: 20,
                    alignment: Alignment.centerLeft,
                    child: Container(width: 2, color: Colors.grey.shade300),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.flag, color: Colors.amber, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        ride.to,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text('출발 일시', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(formattedTime, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.people_outline, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text('모집 현황', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('${ride.people} / ${ride.capacity}명', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _primaryLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD6E2FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.payments_outlined, color: _primary, size: 20),
                      SizedBox(width: 8),
                      Text(
                        '현재 인원 기준 요금 분담 안내',
                        style: TextStyle(color: _primary, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('1인당 예상 금액', style: TextStyle(color: Colors.black87, fontSize: 14)),
                      Text(
                        calculatedPerPersonFare > 0
                            ? '약 ${NumberFormat('#,###').format(calculatedPerPersonFare)}원'
                            : '탑승 후 정산',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '참고용 금액이며, 실제 결제는 각자 진행합니다',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (widget.onApplicants != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: widget.onApplicants,
                icon: const Icon(Icons.people_outline),
                label: const Text('참여 신청자 확인'),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: SizedBox(
            height: 52,
            child: widget.joinRequested
                ? const OutlinedButton(
              onPressed: null,
              child: Text('승인 기다리는 중'),
            )
                : (ride.isMine || isFull)
                ? OutlinedButton(
              onPressed: null,
              child: Text(ride.isMine ? '내가 개설한 팟' : '모집 완료된 팟입니다'),
            )
                : ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: widget.onRequestJoin,
              child: const Text(
                '동행 참여하기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// [통합] 동행팟 만들기 화면
// ============================================================================
class GachiTaCreateRidePage extends StatelessWidget {
  const GachiTaCreateRidePage({
    super.key,
    required this.onBack,
    this.onSubmit,
    this.places = const [],
  });
  final VoidCallback onBack;
  final Future<void> Function(RideDraft)? onSubmit;
  final List<String> places;
  @override
  Widget build(BuildContext context) =>
      _CreateRidePage(onBack: onBack, onSubmit: onSubmit, places: places);
}

class _CreateRidePage extends StatefulWidget {
  const _CreateRidePage({
    this.places = const [],
    required this.onBack,
    this.onSubmit,
  });
  final List<String> places;
  final VoidCallback onBack;
  final Future<void> Function(RideDraft)? onSubmit;
  @override
  State<_CreateRidePage> createState() => _CreateRidePageState();
}

class _CreateRidePageState extends State<_CreateRidePage> {
  final TextEditingController _condition = TextEditingController();

  List<SpotItem> _spots = [];
  SpotItem? _departureSpot;
  SpotItem? _arrivalSpot;
  bool _isLoadingSpots = true;

  RouteInfo? _calculatedRoute;
  bool _isCalculatingFare = false;

  late List<DateTime> _dates;
  late DateTime _selectedDate;

  final List<String> _timeSlots = [];
  String? _selectedTime;

  int _maxCapacity = 4;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initDates();
    _initTimeSlots();
    _ensureValidTimeForSelectedDate();
    _fetchSpots();
  }

  @override
  void dispose() {
    _condition.dispose();
    super.dispose();
  }

  void _initDates() {
    final now = DateTime.now();
    _dates = List.generate(7, (i) => DateTime(now.year, now.month, now.day + i));
    _selectedDate = _dates.first;
  }

  void _initTimeSlots() {
    for (int hour = 6; hour <= 23; hour++) {
      for (int min = 0; min < 60; min += 15) {
        final hStr = hour.toString().padLeft(2, '0');
        final mStr = min.toString().padLeft(2, '0');
        _timeSlots.add('$hStr:$mStr');
      }
    }
  }

  bool _isTimePassed(String timeSlot) {
    final now = DateTime.now();
    final isToday =
        _selectedDate.year == now.year &&
            _selectedDate.month == now.month &&
            _selectedDate.day == now.day;

    if (!isToday) return false;

    final parts = timeSlot.split(':');
    final hour = int.parse(parts[0]);
    final min = int.parse(parts[1]);

    final slotTime = DateTime(now.year, now.month, now.day, hour, min);
    return slotTime.isBefore(now);
  }

  void _ensureValidTimeForSelectedDate() {
    for (final slot in _timeSlots) {
      if (!_isTimePassed(slot)) {
        setState(() {
          _selectedTime = slot;
        });
        return;
      }
    }
    _selectedTime = null;
  }

  Future<void> _fetchSpots() async {
    final loaded = await KakaoNaviService.fetchSpots();
    if (mounted) {
      setState(() {
        _spots = loaded;
        _isLoadingSpots = false;
      });
    }
  }

  Future<void> _calculateKakaoFare() async {
    if (_departureSpot == null || _arrivalSpot == null) return;
    if (_departureSpot!.id == _arrivalSpot!.id) {
      setState(() => _calculatedRoute = null);
      return;
    }

    setState(() => _isCalculatingFare = true);
    try {
      final route = await KakaoNaviService.getDirections(
        startLat: _departureSpot!.latitude,
        startLng: _departureSpot!.longitude,
        endLat: _arrivalSpot!.latitude,
        endLng: _arrivalSpot!.longitude,
      );
      if (mounted) {
        setState(() {
          _calculatedRoute = route;
          _isCalculatingFare = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isCalculatingFare = false);
      }
    }
  }

  void _swapSpots() {
    setState(() {
      final temp = _departureSpot;
      _departureSpot = _arrivalSpot;
      _arrivalSpot = temp;
    });
    _calculateKakaoFare();
  }

  void _selectSpotModal(bool isDeparture) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isDeparture ? '출발지 선택' : '도착지 선택',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: _spots.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final spot = _spots[index];
                    final isAlreadySelectedAsOpposite = isDeparture
                        ? (_arrivalSpot != null && _arrivalSpot!.id == spot.id)
                        : (_departureSpot != null &&
                        _departureSpot!.id == spot.id);

                    return ListTile(
                      enabled: !isAlreadySelectedAsOpposite,
                      title: Text(
                        spot.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isAlreadySelectedAsOpposite
                              ? Colors.grey.shade400
                              : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        isAlreadySelectedAsOpposite
                            ? (isDeparture ? '도착지로 선택됨' : '출발지로 선택됨')
                            : spot.category,
                        style: TextStyle(
                          color: isAlreadySelectedAsOpposite
                              ? Colors.red.shade300
                              : Colors.grey.shade600,
                        ),
                      ),
                      trailing: isAlreadySelectedAsOpposite
                          ? const Icon(
                        Icons.block,
                        size: 18,
                        color: Colors.grey,
                      )
                          : null,
                      onTap: isAlreadySelectedAsOpposite
                          ? null
                          : () {
                        setState(() {
                          if (isDeparture) {
                            _departureSpot = spot;
                          } else {
                            _arrivalSpot = spot;
                          }
                        });
                        Navigator.pop(ctx);
                        _calculateKakaoFare();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_departureSpot == null || _arrivalSpot == null) {
      setState(() => _error = '출발지와 도착지를 모두 선택해 주세요.');
      return;
    }
    if (_departureSpot!.id == _arrivalSpot!.id) {
      setState(() => _error = '출발지와 도착지는 달라야 합니다.');
      return;
    }
    if (_selectedTime == null) {
      setState(() => _error = '출발 시간을 선택해 주세요.');
      return;
    }
    if (_isTimePassed(_selectedTime!)) {
      setState(() => _error = '이미 지난 출발 시간입니다. 다른 시간을 선택해 주세요.');
      return;
    }
    if (_busy || widget.onSubmit == null) return;

    final timeParts = _selectedTime!.split(':');
    final departure = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.onSubmit!(
        RideDraft(
          category: RideCategory.taxi,
          originName: _departureSpot!.name,
          destinationName: _arrivalSpot!.name,
          departureAt: departure,
          capacity: _maxCapacity,
          conditionText: _condition.text.trim(),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
              () => _error = error is FeatureFailure
              ? error.message
              : '등록 결과를 확인하지 못했어요. 다시 등록하기 전에 팟 목록을 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingSpots) {
      return Column(
        children: [
          _PageHeader(title: '동행팟 만들기', onBack: widget.onBack),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    final totalFare = _calculatedRoute?.taxiFare ?? 0;
    final farePerPerson = (totalFare > 0 && _maxCapacity > 0)
        ? (((totalFare / _maxCapacity).round() + 50) ~/ 100) * 100
        : 0;

    return Column(
      children: [
        _PageHeader(title: '동행팟 만들기', onBack: widget.onBack),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '카테고리',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(
                            color: _primary,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: _primaryLight,
                        ),
                        onPressed: () {},
                        icon: const Icon(
                          Icons.local_taxi,
                          color: _primary,
                        ),
                        label: const Text(
                          '택시 ✓',
                          style: TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              color: Colors.grey.shade400,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '카풀 준비 중',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                const Text(
                  '어디서 출발하나요?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      Column(
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.radio_button_checked,
                              color: _primary,
                            ),
                            title: Text(
                              _departureSpot?.name ?? '출발지\n장소를 선택해 주세요',
                              style: TextStyle(
                                fontSize: 15,
                                color: _departureSpot != null
                                    ? Colors.black87
                                    : Colors.grey.shade500,
                                fontWeight: _departureSpot != null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: Colors.grey,
                            ),
                            onTap: _busy ? null : () => _selectSpotModal(true),
                          ),
                          Divider(
                            height: 1,
                            indent: 56,
                            endIndent: 50,
                            color: Colors.grey.shade200,
                          ),
                          ListTile(
                            leading: const Icon(
                              Icons.radio_button_checked,
                              color: Colors.amber,
                            ),
                            title: Text(
                              _arrivalSpot?.name ?? '도착지\n장소를 선택해 주세요',
                              style: TextStyle(
                                fontSize: 15,
                                color: _arrivalSpot != null
                                    ? Colors.black87
                                    : Colors.grey.shade500,
                                fontWeight: _arrivalSpot != null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: Colors.grey,
                            ),
                            onTap: _busy ? null : () => _selectSpotModal(false),
                          ),
                        ],
                      ),
                      Positioned(
                        right: 16,
                        child: InkWell(
                          onTap: _busy ? null : _swapSpots,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: Colors.grey.shade300),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.swap_vert,
                              size: 20,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                const Text(
                  '언제 출발하나요?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _dates.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final d = _dates[index];
                      final isSelected =
                          d.day == _selectedDate.day &&
                              d.month == _selectedDate.month;
                      final dayLabel = index == 0
                          ? '오늘'
                          : (index == 1
                          ? '내일'
                          : DateFormat('E', 'ko').format(d));

                      return GestureDetector(
                        onTap: _busy
                            ? null
                            : () {
                          setState(() {
                            _selectedDate = d;
                          });
                          _ensureValidTimeForSelectedDate();
                        },
                        child: Container(
                          width: 54,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _primaryLight
                                : Colors.white,
                            border: Border.all(
                              color: isSelected
                                  ? _primary
                                  : Colors.grey.shade200,
                              width: isSelected ? 1.5 : 1,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dayLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? _primary
                                      : Colors.grey.shade600,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${d.day}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? _primary
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  '출발 시각',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 2.2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _timeSlots.length,
                  itemBuilder: (context, index) {
                    final time = _timeSlots[index];
                    final isSelected = _selectedTime == time;
                    final isPassed = _isTimePassed(time);

                    return GestureDetector(
                      onTap: (isPassed || _busy)
                          ? null
                          : () => setState(() => _selectedTime = time),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isPassed
                              ? Colors.grey.shade200
                              : (isSelected
                              ? _primary
                              : Colors.grey.shade50),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isPassed
                                ? Colors.grey.shade300
                                : (isSelected
                                ? _primary
                                : Colors.transparent),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          time,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isPassed
                                ? Colors.grey.shade400
                                : (isSelected
                                ? Colors.white
                                : Colors.grey.shade700),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _primaryLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD6E2FF)),
                  ),
                  child: (_departureSpot == null || _arrivalSpot == null)
                      ? Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: _primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '출발지와 도착지를 선택하면 예상 요금이 표시됩니다.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  )
                      : _isCalculatingFare
                      ? const Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                      : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.local_taxi,
                                size: 16,
                                color: _primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '카카오 예상 택시비 약 ${NumberFormat('#,###').format(totalFare)}원',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '거리: ${_calculatedRoute?.distanceKmString ?? "-"} · 시간: ${_calculatedRoute?.durationMinutesString ?? "-"}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '완전 모집($_maxCapacity명) 시',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            farePerPerson > 0
                                ? '약 ${NumberFormat('#,###').format(farePerPerson)}원'
                                : '정산 대기',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '몇 명이 함께 타나요?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '나를 포함한 전체 인원이에요',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9098A9),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [2, 3, 4].map((capacity) {
                    final isSelected = _maxCapacity == capacity;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _busy
                              ? null
                              : () {
                            setState(() {
                              _maxCapacity = capacity;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _primaryLight
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? _primary
                                    : const Color(0xFFE2E6EE),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$capacity명',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isSelected
                                    ? _primary
                                    : const Color(0xFF4A5568),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),

                const Text(
                  '추가 요청사항',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _condition,
                  enabled: !_busy,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '예: 9시 21분에 대원 기숙사 앞에서 만나요!',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: _danger)),
                ],
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _busy || widget.onSubmit == null
                        ? null
                        : _submit,
                    child: _busy
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                        : const Text(
                      '팟 만들기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// [기타 화면들] 내 팟, 팟 채팅, 평가, MY, 키워드, 차단, 설정 화면 복원
// ============================================================================
class GachiTaTripsPage extends StatelessWidget {
  const GachiTaTripsPage({
    super.key,
    required this.controller,
    required this.userId,
    required this.onOpenRide,
    required this.onRatings,
  });
  final CompanionController controller;
  final String userId;
  final ValueChanged<RideRecord> onOpenRide;
  final VoidCallback onRatings;
  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final rows = (snapshot?.rides ?? <RideRecord>[])
        .where(
          (r) =>
      r.host.id == userId ||
          r.participants.any((m) => m.user.id == userId),
    )
        .toList();
    return _LiveFrame(
      controller: controller,
      title: '내 팟',
      rideQuery: true,
      child: _TripsPage(
        rides: rows.map((r) => _RideView(r, controller, userId)).toList(),
        onOpenChat: (v) => onOpenRide(v.record),
        onOpenRating: onRatings,
        ratingTasks: controller.featureReady(CompanionFeature.profile)
            ? snapshot!.ratingTasks
            .where((t) => t.ride.ratingOpen(DateTime.now()))
            .toList()
            : const [],
      ),
    );
  }
}

class _TripsPage extends StatelessWidget {
  const _TripsPage({
    required this.rides,
    required this.onOpenChat,
    required this.onOpenRating,
    required this.ratingTasks,
  });
  final List<_RideView> rides;
  final ValueChanged<_RideView> onOpenChat;
  final VoidCallback onOpenRating;
  final List<RatingTask> ratingTasks;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _PageHeader(title: '내 팟'),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '참여 중',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (rides.isEmpty)
              const SizedBox(
                height: 180,
                child: _EmptyPage(message: '참여 중인 팟이 없어요.'),
              ),
            for (final ride in rides)
              _RideCard(ride: ride, onTap: () => onOpenChat(ride)),
            const SizedBox(height: 20),
            if (ratingTasks.any((task) => task.pending.isNotEmpty))
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: _primaryLight,
                    child: Icon(Icons.star_outline, color: _primary),
                  ),
                  title: const Text(
                    '함께 탄 사람을 평가해 주세요',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '평가할 사용자 ${ratingTasks.fold<int>(0, (n, t) => n + t.pending.length)}명',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenRating,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class GachiTaChatShell extends StatelessWidget {
  const GachiTaChatShell({
    super.key,
    required this.controller,
    required this.ride,
    required this.userId,
    required this.onBack,
    required this.onRatings,
    this.onBoarding,
    this.onArrival,
    this.busy = false,
  });
  final CompanionController controller;
  final RideRecord ride;
  final String userId;
  final VoidCallback onBack, onRatings;
  final VoidCallback? onBoarding, onArrival;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final own = ride.participants.where((m) => m.user.id == userId).firstOrNull;
    final departed = own?.boardedAt != null, arrived = ride.endedAt != null;
    final boardingAllowed =
        own != null &&
            !own.noShow &&
            ['recruiting', 'full'].contains(ride.status);
    return _ChatPage(
      ride: _RideView(ride, controller, userId),
      departed: departed,
      arrived: arrived,
      onBack: onBack,
      onDepart: busy || !boardingAllowed ? null : onBoarding,
      onArrive: busy || !departed ? null : onArrival,
      onRate: onRatings,
    );
  }
}

class _ChatPage extends StatelessWidget {
  const _ChatPage({
    required this.ride,
    required this.departed,
    required this.arrived,
    required this.onBack,
    required this.onDepart,
    required this.onArrive,
    required this.onRate,
  });
  final _RideView ride;
  final bool departed;
  final bool arrived;
  final VoidCallback onBack;
  final VoidCallback? onDepart;
  final VoidCallback? onArrive;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _PageHeader(title: '팟 채팅', onBack: onBack),
      Card(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Text(
                '${ride.from} → ${ride.to} · ${ride.when}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                '참여자 ${ride.people}명  ·  정원 ${ride.capacity}명',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '팀의 채팅 서비스가 연결되면 메시지를 주고받을 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Color(0xFF9A5A00)),
                ),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _EmptyPage(message: '채팅 기능이 아직 연결되지 않았어요.'),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      departed ? '출발 확인 완료' : '출발 시간이에요',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '실제 탑승 확인 결과를 표시해요. 버튼은 운행 확인 기능 연결 후 사용할 수 있어요.',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: departed ? null : onDepart,
                      icon: const Icon(Icons.check),
                      label: Text(departed ? '탑승 확인했어요' : '탑승했어요'),
                    ),
                  ],
                ),
              ),
            ),
            if (departed) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        arrived ? '도착 확인 완료' : '도착했나요?',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: arrived ? null : onArrive,
                        child: const Text('도착했어요'),
                      ),
                      if (arrived)
                        TextButton.icon(
                          onPressed: onRate,
                          icon: const Icon(Icons.star_outline),
                          label: const Text('함께 탄 사람 평가하기'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                enabled: false,
                decoration: InputDecoration(
                  hintText: '메시지를 입력하세요',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: _line),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const IconButton.filled(
              onPressed: null,
              icon: Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    ],
  );
}

class GachiTaRatingPage extends StatefulWidget {
  const GachiTaRatingPage({
    super.key,
    required this.controller,
    required this.onBack,
  });
  final CompanionController controller;
  final VoidCallback onBack;
  @override
  State<GachiTaRatingPage> createState() => _GachiTaRatingPageState();
}

class _GachiTaRatingPageState extends State<GachiTaRatingPage> {
  String? _rideId;
  final Map<String, Map<String, double>> _scores = {};
  final Map<String, Set<String>> _blocks = {}, _confirmed = {};
  late final Timer _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _submit(RatingTask task, List<UserSummary> users) async {
    final c = widget.controller;
    if (!task.ride.ratingOpen(DateTime.now()) || c.busy || c.loading) return;
    final scores = _scores[task.ride.id] ?? {};
    if (users.isEmpty || users.any((u) => !scores.containsKey(u.id))) return;
    final inputs = users
        .map(
          (u) => RatingInput(
        targetId: u.id,
        halfUnits: (scores[u.id]! * 2).round(),
        block:
        c.featureReady(CompanionFeature.blocking) &&
            (_blocks[task.ride.id]?.contains(u.id) ?? false),
      ),
    )
        .toList();
    final success = await c.perform(
          () => c.repository.submitRatings(task.ride.id, inputs),
    );
    if (!mounted || !success) return;
    setState(() {
      _confirmed
          .putIfAbsent(task.ride.id, () => {})
          .addAll(users.map((u) => u.id));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('평가를 보냈어요. 프로필 수치는 하루 1회 갱신돼요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        tasks = c.snapshot?.ratingTasks ?? <RatingTask>[];
    final task =
        tasks.where((t) => t.ride.id == _rideId).firstOrNull ??
            tasks.firstOrNull;
    if (task == null) {
      return _LiveFrame(
        controller: c,
        title: '함께 탄 사람 평가',
        onBack: widget.onBack,
        feature: CompanionFeature.profile,
        child: Column(
          children: [
            _PageHeader(title: '함께 탄 사람 평가', onBack: widget.onBack),
            const Expanded(child: _EmptyPage(message: '평가할 운행이 없어요.')),
          ],
        ),
      );
    }
    final scores = _scores.putIfAbsent(task.ride.id, () => {});
    final blocks = _blocks.putIfAbsent(task.ride.id, () => {});
    final users = task.pending
        .where((u) => !(_confirmed[task.ride.id]?.contains(u.id) ?? false))
        .toList();
    final enabled =
        !c.busy && !c.loading && task.ride.ratingOpen(DateTime.now());
    final deadline = task.ride.ratingDeadline;
    return _LiveFrame(
      controller: c,
      title: '함께 탄 사람 평가',
      onBack: widget.onBack,
      feature: CompanionFeature.profile,
      child: _RatingPage(
        users: users,
        scores: scores,
        blockedUsers: {...blocks, ...?c.snapshot?.blockedIds},
        submitted: task.targets.isNotEmpty && users.isEmpty,
        heading: '${rideDateLabel(task.ride.departureAt)} 함께 탄 사람들을 평가해 주세요',
        deadlineText: !task.ride.ratingOpen(DateTime.now())
            ? '평가 기간이 종료됐어요.'
            : deadline == null
            ? '평가 기한 정보 없음'
            : '평가 기한 ${rideDateLabel(deadline)} · 0.5점 단위로 선택할 수 있어요',
        selector: tasks.length < 2
            ? null
            : DropdownButton<String>(
          isExpanded: true,
          value: task.ride.id,
          items: tasks
              .map(
                (t) => DropdownMenuItem(
              value: t.ride.id,
              child: Text(
                '${rideDateLabel(t.ride.departureAt)} · ${t.ride.from} → ${t.ride.to}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
              .toList(),
          onChanged: c.busy ? null : (id) => setState(() => _rideId = id),
        ),
        onBack: widget.onBack,
        onScoreChanged: enabled
            ? (id, score) => setState(() => scores[id] = score)
            : null,
        onBlockChanged: enabled && c.featureReady(CompanionFeature.blocking)
            ? (id, value) => setState(() {
          if (value) {
            blocks.add(id);
          } else {
            blocks.remove(id);
          }
        })
            : null,
        alreadyBlocked: c.snapshot?.blockedIds ?? {},
        onSubmit: enabled ? () => _submit(task, users) : null,
      ),
    );
  }
}

class _RatingPage extends StatelessWidget {
  const _RatingPage({
    required this.users,
    required this.heading,
    required this.deadlineText,
    required this.selector,
    required this.alreadyBlocked,
    required this.scores,
    required this.blockedUsers,
    required this.submitted,
    required this.onBack,
    required this.onScoreChanged,
    required this.onBlockChanged,
    required this.onSubmit,
  });
  final List<UserSummary> users;
  final String heading, deadlineText;
  final Widget? selector;
  final Set<String> alreadyBlocked;
  final Map<String, double> scores;
  final Set<String> blockedUsers;
  final bool submitted;
  final VoidCallback onBack;
  final void Function(String, double)? onScoreChanged;
  final void Function(String, bool)? onBlockChanged;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final allRated =
        users.isNotEmpty && users.every((u) => scores.containsKey(u.id));
    return Column(
      children: [
        _PageHeader(title: '함께 탄 사람 평가', onBack: onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              if (selector != null) selector!,
              Text(
                heading,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                deadlineText,
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              const SizedBox(height: 14),
              if (users.isEmpty && !submitted)
                const _EmptyPage(message: '함께 탑승한 평가 대상이 없어요.'),
              if (submitted)
                const _InfoBanner(
                  icon: Icons.check_circle_outline,
                  text: '평가를 보냈어요. 한 사람에게 한 번만 평가할 수 있어요.',
                  color: _success,
                )
              else
                for (final user in users)
                  _RatingCard(
                    name: user.name,
                    score: scores[user.id] ?? 0,
                    blocked: blockedUsers.contains(user.id),
                    onScoreChanged: onScoreChanged == null
                        ? null
                        : (score) => onScoreChanged!(user.id, score),
                    onBlockChanged:
                    onBlockChanged == null ||
                        alreadyBlocked.contains(user.id)
                        ? null
                        : (value) => onBlockChanged!(user.id, value),
                  ),
              const SizedBox(height: 8),
              const Text(
                '평가는 한 번만 보낼 수 있고, 프로필 수치는 하루 1회 갱신돼요.',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: submitted || !allRated ? null : onSubmit,
              child: Text(submitted ? '평가를 보냈어요' : '평가 보내기'),
            ),
          ),
        ),
      ],
    );
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({
    required this.name,
    required this.score,
    required this.blocked,
    required this.onScoreChanged,
    required this.onBlockChanged,
  });
  final String name;
  final double score;
  final bool blocked;
  final ValueChanged<double>? onScoreChanged;
  final ValueChanged<bool>? onBlockChanged;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: _primaryLight,
                child: Icon(Icons.person, color: _primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Text(
                      '함께 탄 사용자',
                      style: TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
              Text(
                score == 0 ? '선택해 주세요' : score.toStringAsFixed(1),
                style: const TextStyle(
                  color: _primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _HalfStarPicker(score: score, onChanged: onScoreChanged),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: blocked,
            onChanged: onBlockChanged == null
                ? null
                : (value) => onBlockChanged!(value ?? false),
            title: const Text('이 사용자 차단하기', style: TextStyle(fontSize: 13)),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ),
    ),
  );
}

class _HalfStarPicker extends StatelessWidget {
  const _HalfStarPicker({required this.score, required this.onChanged});
  final double score;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(5, (index) {
      final full = score >= index + 1;
      final half = !full && score >= index + 0.5;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onChanged == null
            ? null
            : (details) {
          final halfTap = details.localPosition.dx < 21;
          onChanged!(index + (halfTap ? 0.5 : 1.0));
        },
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            full
                ? Icons.star_rounded
                : half
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded,
            color: _taxi,
            size: 32,
          ),
        ),
      );
    }),
  );
}

class GachiTaMyPage extends StatelessWidget {
  const GachiTaMyPage({
    super.key,
    required this.controller,
    required this.onKeywords,
    required this.onBlocks,
    required this.onSettings,
    required this.onRatings,
    required this.onLogout,
    this.onAccount,
  });
  final CompanionController controller;
  final VoidCallback onKeywords, onBlocks, onSettings, onRatings;
  final VoidCallback? onAccount;
  final Future<void> Function() onLogout;
  @override
  Widget build(BuildContext context) {
    final s = controller.snapshot;
    return _LiveFrame(
      controller: controller,
      title: 'MY',
      child: _MyPage(
        controller: controller,
        onLogout: onLogout,
        account: s?.account,
        stats: controller.featureReady(CompanionFeature.profile)
            ? s?.profile
            : null,
        keywords: controller.featureReady(CompanionFeature.keywords)
            ? s!.keywords.map((k) => k.text).toList()
            : null,
        blockedCount: controller.featureReady(CompanionFeature.blocking)
            ? s!.blockedUsers.length
            : null,
        onKeywords: onKeywords,
        onBlockedUsers: onBlocks,
        onNotificationSettings: onSettings,
      ),
    );
  }
}

class _MyPage extends StatelessWidget {
  const _MyPage({
    required this.controller,
    required this.onLogout,
    required this.account,
    required this.stats,
    required this.keywords,
    required this.blockedCount,
    required this.onKeywords,
    required this.onBlockedUsers,
    required this.onNotificationSettings,
  });
  final CompanionController controller;
  final Future<void> Function() onLogout;
  final UserSummary? account;
  final ProfileStats? stats;
  final List<String>? keywords;
  final int? blockedCount;
  final VoidCallback onKeywords;
  final VoidCallback onBlockedUsers;
  final VoidCallback onNotificationSettings;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _PageHeader(title: 'MY'),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            Card(
              child: InkWell(
                onTap: account == null
                    ? null
                    : () => showCompanionProfile(
                  context,
                  controller,
                  account!.id,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          account == null
                              ? const CircleAvatar(
                            radius: 25,
                            backgroundColor: _primaryLight,
                            child: Icon(
                              Icons.person,
                              color: _primary,
                              size: 27,
                            ),
                          )
                              : ProfileAvatar(
                            controller: controller,
                            user: account!,
                            radius: 25,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account?.name ?? '프로필 준비 필요',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '내 프로필',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: _subtle),
                        ],
                      ),
                      const Divider(height: 30),
                      Row(
                        children: [
                          Expanded(
                            child: _ProfileStat(
                              label: '별점',
                              value: stats?.ratingLabel ?? '정보 없음',
                            ),
                          ),
                          Expanded(
                            child: _ProfileStat(
                              label: '총 참여',
                              value: stats == null
                                  ? '정보 없음'
                                  : '${stats!.participationCount}회',
                            ),
                          ),
                          Expanded(
                            child: _ProfileStat(
                              label: '참여 안 함',
                              value: stats == null
                                  ? '정보 없음'
                                  : '${stats!.noShowCount}회',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  _MenuRow(
                    icon: Icons.sell_outlined,
                    title: '키워드 알림',
                    subtitle: keywords == null
                        ? '정보 없음'
                        : keywords!.isEmpty
                        ? '등록한 키워드가 없어요'
                        : keywords!.join(' · '),
                    onTap: onKeywords,
                  ),
                  const Divider(height: 1, indent: 54),
                  _MenuRow(
                    icon: Icons.block_outlined,
                    title: '차단한 사용자',
                    subtitle: blockedCount == null ? '정보 없음' : '$blockedCount명',
                    onTap: onBlockedUsers,
                  ),
                  const Divider(height: 1, indent: 54),
                  _MenuRow(
                    icon: Icons.tune,
                    title: '알림 설정',
                    onTap: onNotificationSettings,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: _MenuRow(
                icon: Icons.logout,
                title: '로그아웃',
                titleColor: _danger,
                onTap: () {
                  onLogout();
                },
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
      const SizedBox(height: 6),
      Text(
        value,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: _ink,
        ),
      ),
    ],
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.titleColor = _ink,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color titleColor;
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: Icon(icon, color: titleColor, size: 21),
    title: Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: titleColor,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: const TextStyle(fontSize: 11, color: _muted)),
    trailing: const Icon(Icons.chevron_right, color: _subtle),
  );
}

class GachiTaKeywordPage extends StatelessWidget {
  const GachiTaKeywordPage({
    super.key,
    required this.controller,
    required this.onBack,
  });
  final CompanionController controller;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final keywords = controller.snapshot?.keywords ?? <Keyword>[];
    return _LiveFrame(
      controller: controller,
      title: '키워드 알림',
      onBack: onBack,
      feature: CompanionFeature.keywords,
      child: _KeywordPage(
        keywords: keywords,
        enabled: controller.snapshot?.keywordAlertsEnabled ?? false,
        busy: controller.busy || controller.loading,
        onBack: onBack,
        onAdd: (text) => controller.perform(
              () => controller.repository.addKeyword(text),
          feature: CompanionFeature.keywords,
        ),
        onRemove: (id) => controller.perform(
              () => controller.repository.removeKeyword(id),
          feature: CompanionFeature.keywords,
        ),
        onKeywordToggle: (id, value) => controller.perform(
              () => controller.repository.setKeywordEnabled(id, value),
          feature: CompanionFeature.keywords,
        ),
        onToggle: (value) => controller.perform(
              () => controller.repository.setKeywordAlerts(value),
          feature: CompanionFeature.keywords,
        ),
      ),
    );
  }
}

class _KeywordPage extends StatefulWidget {
  const _KeywordPage({
    required this.keywords,
    required this.enabled,
    required this.onBack,
    required this.onToggle,
    required this.onAdd,
    required this.onRemove,
    required this.onKeywordToggle,
    this.busy = false,
  });
  final List<Keyword> keywords;
  final bool busy;
  final bool enabled;
  final VoidCallback onBack;
  final ValueChanged<bool> onToggle;
  final Future<bool> Function(String) onAdd;
  final ValueChanged<String> onRemove;
  final void Function(String, bool) onKeywordToggle;
  @override
  State<_KeywordPage> createState() => _KeywordPageState();
}

class _KeywordPageState extends State<_KeywordPage> {
  final TextEditingController _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (widget.busy) return;
    final submitted = _controller.text;
    final success = await widget.onAdd(submitted);
    if (!mounted) return;
    if (!success) return;
    if (_controller.text == submitted) _controller.clear();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _PageHeader(title: '키워드 알림', onBack: widget.onBack),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '찾는 팟을 빠르게 알려드려요',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              '사용 중인 키워드가 포함된 새 팟이 올라오면 알려드려요.',
              style: TextStyle(fontSize: 13, color: _muted),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '키워드 등록',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${widget.keywords.length}/5',
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !widget.busy,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                    decoration: const InputDecoration(
                      hintText: '예: 충주역, 기숙사',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(color: _line),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: !widget.busy && widget.keywords.length < 5
                      ? _add
                      : null,
                  child: const Text('추가'),
                ),
              ],
            ),
            const SizedBox(height: 7),
            const Text(
              '사용을 중지한 키워드를 포함해 최대 5개까지 등록할 수 있어요.',
              style: TextStyle(fontSize: 11, color: _muted),
            ),
            const SizedBox(height: 22),
            const Text(
              '등록된 키워드',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (widget.keywords.isEmpty)
              const Text('등록한 키워드가 없어요.')
            else
              Column(
                children: widget.keywords
                    .map(
                      (keyword) => Card(
                    child: Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            title: Text(keyword.text),
                            subtitle: Text(
                              keyword.enabled ? '사용 중' : '사용 중지',
                            ),
                            value: keyword.enabled,
                            activeThumbColor: _primary,
                            onChanged: widget.busy
                                ? null
                                : (value) => widget.onKeywordToggle(
                              keyword.id,
                              value,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '키워드 삭제',
                          color: _primary,
                          onPressed: widget.busy
                              ? null
                              : () => widget.onRemove(keyword.id),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                )
                    .toList(),
              ),
            const SizedBox(height: 22),
            Card(
              child: SwitchListTile(
                value: widget.enabled,
                activeThumbColor: _primary,
                onChanged: widget.busy ? null : widget.onToggle,
                title: const Text(
                  '키워드 알림 전체 받기',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  '전체 알림과 개별 키워드가 모두 켜져 있어야 알림을 받아요.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class GachiTaBlocksPage extends StatelessWidget {
  const GachiTaBlocksPage({
    super.key,
    required this.controller,
    required this.onBack,
  });
  final CompanionController controller;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => _LiveFrame(
    controller: controller,
    title: '차단한 사용자',
    onBack: onBack,
    feature: CompanionFeature.blocking,
    child: _BlockedUsersPage(
      blockedUsers: controller.snapshot?.blockedUsers ?? <UserSummary>[],
      onBack: onBack,
      onUnblock: controller.busy || controller.loading
          ? null
          : (user) => controller.perform(
            () => controller.repository.unblock(user.id),
        feature: CompanionFeature.blocking,
      ),
    ),
  );
}

class _BlockedUsersPage extends StatelessWidget {
  const _BlockedUsersPage({
    required this.blockedUsers,
    required this.onBack,
    required this.onUnblock,
  });
  final List<UserSummary> blockedUsers;
  final VoidCallback onBack;
  final ValueChanged<UserSummary>? onUnblock;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      _PageHeader(title: '차단한 사용자', onBack: onBack),
      Expanded(
        child: blockedUsers.isEmpty
            ? const _EmptyPage(message: '차단한 사용자가 없어요.')
            : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '차단한 사실은 상대에게 알려지지 않아요.',
              style: TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 10),
            for (final name in blockedUsers)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: _canvas,
                    child: Icon(Icons.person_outline, color: _muted),
                  ),
                  title: Text(name.name),
                  trailing: TextButton(
                    onPressed: onUnblock == null
                        ? null
                        : () => onUnblock!(name),
                    child: const Text('차단 해제'),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class GachiTaNoticesPage extends StatelessWidget {
  const GachiTaNoticesPage({
    super.key,
    required this.controller,
    required this.onOpenRide,
    required this.onRatings,
  });
  final CompanionController controller;
  final Future<void> Function(String) onOpenRide;
  final VoidCallback onRatings;
  @override
  Widget build(BuildContext context) {
    final s = controller.snapshot;
    final notices = <_NoticeView>[
      if (controller.featureReady(CompanionFeature.profile))
        for (final task in s!.ratingTasks.where(
              (t) => t.pending.isNotEmpty && t.ride.ratingOpen(DateTime.now()),
        ))
          _NoticeView(
            title: '함께 탄 사람을 평가해 주세요',
            message:
            '${rideDateLabel(task.ride.departureAt)} · ${task.ride.from} → ${task.ride.to}',
            isRating: true,
          ),
      for (final notice in s?.notices ?? <AppNotice>[])
        _NoticeView(
          title: notice.title,
          message: notice.body,
          onOpen: controller.busy || controller.loading
              ? null
              : () async {
            final success = await controller.perform(
                  () => controller.repository.markNoticeRead(notice.id),
              feature: CompanionFeature.keywords,
            );
            if (success) await onOpenRide(notice.rideId);
          },
        ),
    ];
    return _LiveFrame(
      controller: controller,
      title: '알림',
      feature: CompanionFeature.keywords,
      child: _NotificationsPage(notices: notices, onOpenRating: onRatings),
    );
  }
}

class _NotificationsPage extends StatelessWidget {
  const _NotificationsPage({required this.notices, required this.onOpenRating});
  final List<_NoticeView> notices;
  final VoidCallback onOpenRating;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _PageHeader(title: '알림'),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (notices.isEmpty)
              const SizedBox(
                height: 180,
                child: _EmptyPage(message: '아직 도착한 알림이 없어요.'),
              ),
            for (final notice in notices)
              Card(
                margin: const EdgeInsets.only(bottom: 9),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: notice.isRating
                        ? const Color(0xFFFFF4E5)
                        : _primaryLight,
                    child: Icon(
                      notice.isRating
                          ? Icons.star_rounded
                          : Icons.notifications_active_outlined,
                      color: notice.isRating ? _taxi : _primary,
                    ),
                  ),
                  title: Text(
                    notice.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    notice.message,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: notice.isRating ? onOpenRating : notice.onOpen,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class GachiTaSettingsPage extends StatelessWidget {
  const GachiTaSettingsPage({
    super.key,
    required this.controller,
    required this.onBack,
    required this.enablePush,
  });
  final CompanionController controller;
  final VoidCallback onBack;
  final Future<void> Function() enablePush;
  @override
  Widget build(BuildContext context) => _LiveFrame(
    controller: controller,
    title: '알림 설정',
    onBack: onBack,
    feature: CompanionFeature.keywords,
    child: _NotificationSettingsPage(
      chatEnabled: null,
      keywordEnabled: controller.snapshot?.keywordAlertsEnabled ?? false,
      onBack: onBack,
      onChatChanged: null,
      busy: controller.busy || controller.loading,
      onKeywordChanged: (v) => controller.perform(
            () => controller.repository.setKeywordAlerts(v),
        feature: CompanionFeature.keywords,
      ),
      enablePush: () async {
        await controller.perform(
          enablePush,
          allowUserInteraction: true,
          feature: CompanionFeature.keywords,
        );
      },
    ),
  );
}

class _NotificationSettingsPage extends StatelessWidget {
  const _NotificationSettingsPage({
    required this.chatEnabled,
    required this.keywordEnabled,
    required this.onBack,
    required this.onChatChanged,
    required this.onKeywordChanged,
    required this.enablePush,
    this.busy = false,
  });
  final bool? chatEnabled;
  final bool keywordEnabled;
  final bool busy;
  final VoidCallback onBack;
  final Future<void> Function() enablePush;
  final ValueChanged<bool>? onChatChanged;
  final ValueChanged<bool> onKeywordChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      _PageHeader(title: '알림 설정', onBack: onBack),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    value: chatEnabled ?? false,
                    onChanged: busy ? null : onChatChanged,
                    activeThumbColor: _primary,
                    title: const Text('채팅 알림'),
                    subtitle: Text(
                      chatEnabled == null
                          ? '채팅 서비스 연결 후 사용할 수 있어요.'
                          : '새 메시지를 알려드려요.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    value: keywordEnabled,
                    onChanged: busy ? null : onKeywordChanged,
                    activeThumbColor: _primary,
                    title: const Text('키워드 알림'),
                    subtitle: const Text(
                      '조건에 맞는 새 팟을 알려드려요.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy
                  ? null
                  : () {
                enablePush();
              },
              child: const Text('이 기기에서 푸시 알림 활성화'),
            ),
            const SizedBox(height: 12),
            const _InfoBanner(
              icon: Icons.lock_outline,
              text: '출발·도착 확인 알림은 운행 확인 기능 연결 후 사용할 수 있어요.',
              color: _warning,
            ),
          ],
        ),
      ),
    ],
  );
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, this.onBack});
  final String title;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 20, 8),
    child: Row(
      children: [
        if (onBack != null)
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
        if (onBack == null) const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: color, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _EmptyPage extends StatelessWidget {
  const _EmptyPage({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, color: _subtle, size: 42),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
        ],
      ),
    ),
  );
}

class _NoResultsPage extends StatelessWidget {
  const _NoResultsPage({
    required this.onBack,
    required this.onKeywords,
    required this.onCreate,
  });

  final VoidCallback onBack;
  final VoidCallback onKeywords;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 80),
      const Center(
        child: Text(
          '조건에 맞는 동행팟이 없습니다.\n직접 팟을 만들어보세요!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 15, height: 1.5),
        ),
      ),
      const SizedBox(height: 20),
      Center(
        child: TextButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.refresh),
          label: const Text('필터 초기화'),
        ),
      ),
    ],
  );
}