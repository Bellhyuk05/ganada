import 'dart:async';

import 'package:flutter/material.dart';

import '../core/team_features.dart';
import '../features/companion/controller.dart';
import '../features/companion/models.dart';
import '../features/companion/screens.dart'
    show ProfileAvatar, CompanionModuleNotice, showCompanionProfile;
import 'gachita_theme.dart';

const _primary = GachiTaTheme.primary;
const _primaryLight = GachiTaTheme.primaryLight;
const _taxi = GachiTaTheme.taxi;
const _ink = GachiTaTheme.ink;
const _muted = GachiTaTheme.muted;
const _subtle = GachiTaTheme.subtle;
const _canvas = GachiTaTheme.canvas;
const _line = GachiTaTheme.line;
const _warning = GachiTaTheme.warning;
const _danger = GachiTaTheme.danger;
const _success = Color(0xFF1DB36B);

String rideDateLabel(DateTime value) {
  final date = value.toLocal(), now = DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final label = day == today
      ? '오늘'
      : day == DateTime(now.year, now.month, now.day + 1)
      ? '내일'
      : '${date.month}/${date.day}';
  return '$label ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

// Presentation reads server records; it never creates replacement ride data.
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
  int get people => record.participants.length;
  int get capacity => record.capacity;
  bool get full => record.status != 'recruiting' || people >= capacity;
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
      ?action,
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

class _FeedFilters extends InheritedWidget {
  const _FeedFilters({required this.pick, required super.child});
  final void Function(BuildContext, String) pick;
  static _FeedFilters of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FeedFilters>()!;
  @override
  bool updateShouldNotify(_FeedFilters oldWidget) => true;
}

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
  String _sort = '출발 임박순', _origin = '', _destination = '', _query = '';
  DateTime? _day;
  TimeOfDay? _time;
  int _seats = 0;
  Set<String>? _nearbyIds;
  bool _searching = false;
  bool get _filtered =>
      _origin.isNotEmpty ||
      _destination.isNotEmpty ||
      _query.isNotEmpty ||
      _day != null ||
      _time != null ||
      _seats > 0 ||
      _nearbyIds != null;
  void _reset() => setState(() {
    _origin = '';
    _destination = '';
    _query = '';
    _day = null;
    _time = null;
    _seats = 0;
    _nearbyIds = null;
  });
  Future<void> _pick(BuildContext context, String label) async {
    if (label == '반경') {
      if (widget.onSearchNearby == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치 검색 기능이 연결되면 반경 검색을 사용할 수 있어요.')),
        );
        return;
      }
      if (_searching) return;
      setState(() => _searching = true);
      try {
        final result = await widget.onSearchNearby!(context);
        if (mounted && result != null) setState(() => _nearbyIds = result);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('위치 검색 결과를 불러오지 못했어요.')));
        }
      } finally {
        if (mounted) setState(() => _searching = false);
      }
      return;
    }
    if (label == '시간') {
      final picked = await showTimePicker(
        context: context,
        initialTime: _time ?? TimeOfDay.now(),
      );
      if (mounted && picked != null) setState(() => _time = picked);
      return;
    }
    if (label == '출발지' || label == '도착지' || label == '검색') {
      final rows = widget.controller.snapshot?.rides ?? <RideRecord>[];
      final places =
          rows
              .expand((r) => [r.from, r.to])
              .where((v) => v.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      final current = label == '출발지'
          ? _origin
          : label == '도착지'
          ? _destination
          : _query;
      final picked = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _PlaceInputSheet(
          places: places,
          initialValue: current,
          title: '$label 선택',
          allowClear: true,
        ),
      );
      if (mounted && picked != null) {
        setState(() {
          if (label == '출발지') {
            _origin = picked;
          } else if (label == '도착지') {
            _destination = picked;
          } else {
            _query = picked;
          }
        });
      }
      return;
    }
    final options = label == '남은 자리'
        ? ['제한 없음', '1자리 이상', '2자리 이상', '3자리']
        : ['제한 없음', '오늘', '내일'];
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _FilterSheet(title: label, options: options),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (label == '남은 자리') {
        _seats = options.indexOf(picked);
      } else {
        final now = DateTime.now();
        _day = picked == '제한 없음'
            ? null
            : DateTime(now.year, now.month, now.day + (picked == '내일' ? 1 : 0));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot;
    final rows = (snapshot?.rides ?? <RideRecord>[]).where((ride) {
      if (!['recruiting', 'full'].contains(ride.status)) return false;
      final date = ride.departureAt.toLocal();
      return (_origin.isEmpty ||
              ride.from.toLowerCase().contains(_origin.toLowerCase())) &&
          (_destination.isEmpty ||
              ride.to.toLowerCase().contains(_destination.toLowerCase())) &&
          (_query.isEmpty ||
              '${ride.from} ${ride.to} ${ride.condition}'
                  .toLowerCase()
                  .contains(_query.toLowerCase())) &&
          (_day == null || DateTime(date.year, date.month, date.day) == _day) &&
          (_time == null ||
              date.hour * 60 + date.minute >=
                  _time!.hour * 60 + _time!.minute) &&
          (ride.capacity - ride.participants.length >= _seats) &&
          (_nearbyIds == null || _nearbyIds!.contains(ride.id));
    }).toList()..sort((a, b) => a.departureAt.compareTo(b.departureAt));
    final child = rows.isEmpty && _filtered
        ? _NoResultsPage(
            onBack: _reset,
            onKeywords: widget.onKeywords,
            onCreate: widget.onCreate,
          )
        : _FeedFilters(
            pick: _pick,
            child: _HomePage(
              rides: rows
                  .map(
                    (r) => _RideView(
                      r,
                      widget.controller,
                      widget.controller.repository.userId,
                    ),
                  )
                  .toList(),
              sortOrder: _sort,
              onSortChanged: (v) => setState(() => _sort = v),
              onOpenRide: (v) => widget.onOpenRide(v.record),
              onOpenNotifications: widget.onNotifications,
            ),
          );
    return _LiveFrame(
      controller: widget.controller,
      title: '같이타',
      rideQuery: true,
      child: child,
    );
  }
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({required this.title, required this.options});
  final String title;
  final List<String> options;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title 선택', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map(
                  (label) => ChoiceChip(
                    label: Text(label),
                    selected: false,
                    onSelected: (_) => Navigator.pop(context, label),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    ),
  );
}

class _PlaceInputSheet extends StatefulWidget {
  const _PlaceInputSheet({
    required this.places,
    required this.initialValue,
    this.title = '장소 선택',
    this.allowClear = false,
  });
  final List<String> places;
  final String initialValue, title;
  final bool allowClear;
  @override
  State<_PlaceInputSheet> createState() => _PlaceInputSheetState();
}

class _PlaceInputSheetState extends State<_PlaceInputSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialValue,
  );
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _apply() {
    final value = _text.text.trim();
    if (value.isNotEmpty || widget.allowClear) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        28 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _apply(),
              decoration: const InputDecoration(hintText: '장소 이름을 입력하세요'),
            ),
            const SizedBox(height: 12),
            if (widget.places.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.places
                    .map(
                      (label) => ChoiceChip(
                        label: Text(label),
                        selected: false,
                        onSelected: (_) => Navigator.pop(context, label),
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.allowClear)
                  TextButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('조건 지우기'),
                  ),
                const Spacer(),
                FilledButton(onPressed: _apply, child: const Text('적용')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

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

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.rides,
    required this.sortOrder,
    required this.onSortChanged,
    required this.onOpenRide,
    required this.onOpenNotifications,
  });

  final List<_RideView> rides;
  final String sortOrder;
  final ValueChanged<String> onSortChanged;
  final ValueChanged<_RideView> onOpenRide;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    final openRides = rides.where((ride) => !ride.full).toList();
    final closedRides = rides.where((ride) => ride.full).toList();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                const Text(
                  '같이타',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _primary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onOpenNotifications,
                  icon: const Icon(
                    Icons.notifications_none_rounded,
                    color: _ink,
                  ),
                  tooltip: '알림 보기',
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(label: '오늘', icon: Icons.calendar_today_outlined),
                _FilterChip(label: '시간', icon: Icons.schedule_outlined),
                _FilterChip(label: '출발지', icon: Icons.trip_origin),
                _FilterChip(label: '도착지', icon: Icons.place_outlined),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ActionChip(
                    tooltip: '장소 검색',
                    onPressed: () =>
                        _FeedFilters.of(context).pick(context, '검색'),
                    avatar: const Icon(Icons.search, size: 16, color: _muted),
                    label: const Text('검색'),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: _line),
                    shape: const StadiumBorder(),
                    labelStyle: const TextStyle(color: _ink, fontSize: 13),
                  ),
                ),
                _FilterChip(label: '반경', icon: Icons.radar_outlined),
                _FilterChip(label: '남은 자리', icon: Icons.people_outline),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Text(
                  '함께 갈 팟 ${rides.length}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const Spacer(),
                _SortToggle(value: sortOrder, onChanged: onSortChanged),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          sliver: SliverList.separated(
            itemCount: openRides.length + closedRides.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final ride = index < openRides.length
                  ? openRides[index]
                  : closedRides[index - openRides.length];
              return _RideCard(ride: ride, onTap: () => onOpenRide(ride));
            },
          ),
        ),
        if (rides.isEmpty)
          const SliverToBoxAdapter(
            child: SizedBox(
              height: 180,
              child: _EmptyPage(message: '아직 등록된 팟이 없어요.'),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 72)),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: ActionChip(
      onPressed: () => _FeedFilters.of(context).pick(context, label),
      avatar: Icon(icon, size: 16, color: _muted),
      label: Text(label),
      backgroundColor: Colors.white,
      side: const BorderSide(color: _line),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: _ink, fontSize: 13),
    ),
  );
}

class _SortToggle extends StatelessWidget {
  const _SortToggle({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => const [
      PopupMenuItem(value: '출발 임박순', child: Text('출발 임박순')),
      PopupMenuItem(value: '가까운순', enabled: false, child: Text('가까운순')),
    ],
    child: Row(
      children: [
        Text(value, style: const TextStyle(fontSize: 12, color: _muted)),
        const Icon(Icons.keyboard_arrow_down, size: 18, color: _muted),
      ],
    ),
  );
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.ride, required this.onTap});
  final _RideView ride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ride.full;
    return Opacity(
      opacity: muted ? 0.58 : 1,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.when,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          ride.until,
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                      ),
                    ),
                    if (ride.full || ride.inProgress)
                      _StatusPill(
                        label: ride.record.status == 'completed'
                            ? '이동 완료'
                            : ride.inProgress
                            ? '이동 중'
                            : ride.record.status == 'cancelled'
                            ? '취소됨'
                            : '모집 완료',
                        color: _muted,
                        background: _line,
                      )
                    else if (ride.capacity - ride.people == 1)
                      const _StatusPill(
                        label: '마감 임박',
                        color: _warning,
                        background: Color(0xFFFFF4E5),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${ride.from}  →  ${ride.to}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                    ),
                    Text(
                      '${ride.people}/${ride.capacity}명',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 12,
                      backgroundColor: _primaryLight,
                      child: Icon(Icons.person, size: 15, color: _primary),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      ride.host,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(Icons.star_rounded, size: 14, color: _taxi),
                    Text(
                      ride.ratingLabel,
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                    if (ride.condition.isNotEmpty) ...[
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          ride.condition,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.background,
  });
  final String label;
  final Color color;
  final Color background;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class _RideDetailPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final blockedName = ride.participants
        .where((user) => blockedUsers.contains(user.id))
        .firstOrNull;
    return Column(
      children: [
        _PageHeader(title: '팟 상세', onBack: onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                ride.when,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                ride.until,
                style: const TextStyle(fontSize: 13, color: _muted),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RouteLine(from: ride.from, to: ride.to),
                      const Divider(height: 28),
                      Row(
                        children: [
                          const _InfoValue(label: '카테고리', value: '정보 없음'),
                          _InfoValue(
                            label: '남은 자리',
                            value: '${ride.people}/${ride.capacity}명',
                          ),
                          const _InfoValue(label: '1인 예상', value: '정보 없음'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (ride.condition.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '함께 타기 전에',
                          style: TextStyle(fontSize: 12, color: _muted),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ride.condition,
                          style: const TextStyle(fontSize: 14, color: _ink),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '방장',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                      const SizedBox(height: 10),
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
                                InkWell(
                                  onTap: () => showCompanionProfile(
                                    context,
                                    ride.controller,
                                    ride.record.host.id,
                                  ),
                                  child: Text(
                                    ride.host,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  ride.profileLabel,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '현재 참여자 ${ride.participants.length}명',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        children: ride.participants
                            .map(
                              (user) => Chip(
                                avatar: const CircleAvatar(
                                  child: Icon(Icons.person, size: 14),
                                ),
                                label: Text(user.name),
                                backgroundColor: blockedUsers.contains(user.id)
                                    ? const Color(0xFFFFF4E5)
                                    : _canvas,
                                side: BorderSide.none,
                              ),
                            )
                            .toList(),
                      ),
                      if (blockedName != null) ...[
                        const SizedBox(height: 6),
                        const Row(
                          children: [
                            Icon(Icons.info_outline, size: 17, color: _warning),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '참여자 중 내가 차단한 사용자가 있어요',
                                style: TextStyle(fontSize: 12, color: _warning),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (onApplicants != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onApplicants,
                  icon: const Icon(Icons.people_outline),
                  label: const Text('참여 신청자 확인'),
                ),
              ],
              if (joinUnavailable && !ride.isMine && !ride.full)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    '참여 신청 기능이 연결되면 신청할 수 있어요.',
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
                ),
              const SizedBox(height: 88),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Row(
            children: [
              if (joinRequested)
                Expanded(
                  child: OutlinedButton(
                    onPressed: null,
                    child: const Text('승인 기다리는 중'),
                  ),
                )
              else if (ride.full ||
                  ride.isMine ||
                  !['recruiting'].contains(ride.record.status))
                Expanded(
                  child: OutlinedButton(
                    onPressed: null,
                    child: Text(ride.isMine ? '참여 중인 팟' : '모집이 끝났어요'),
                  ),
                )
              else
                Expanded(
                  child: FilledButton(
                    onPressed: onRequestJoin,
                    child: const Text('참여 신청하기'),
                  ),
                ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onOpenChat,
                icon: const Icon(Icons.chat_bubble_outline),
                tooltip: '팟 채팅',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({required this.from, required this.to});
  final String from;
  final String to;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        children: [
          const Icon(Icons.radio_button_checked, size: 17, color: _primary),
          Container(width: 1.5, height: 22, color: _line),
          const Icon(Icons.location_on, size: 17, color: _taxi),
        ],
      ),
      const SizedBox(width: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            from,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Text(
            to,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ],
  );
}

class _InfoValue extends StatelessWidget {
  const _InfoValue({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
      ],
    ),
  );
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
  String? _from;
  String? _to;
  DateTime? _day;
  TimeOfDay? _time;
  bool _busy = false;
  String? _error;
  String get _when {
    final now = DateTime.now(), day = _day;
    final today = DateTime(now.year, now.month, now.day);
    final dayLabel = day == null
        ? ''
        : day == today
        ? '오늘'
        : day == today.add(const Duration(days: 1))
        ? '내일'
        : '${day.month}/${day.day}';
    final timeLabel = _time == null
        ? ''
        : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';
    return '$dayLabel $timeLabel';
  }

  bool get _valid =>
      _from != null &&
      _to != null &&
      _from != _to &&
      _day != null &&
      _time != null;

  int _people = 2;

  List<String> get _dateOptions => List.generate(8, (index) {
    if (index == 0) return '오늘';
    if (index == 1) return '내일';
    final date = DateTime.now().add(Duration(days: index));
    return '${date.month}/${date.day}';
  });

  @override
  void dispose() {
    _condition.dispose();
    super.dispose();
  }

  Future<void> _choosePlace(bool departure) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PlaceInputSheet(
        places: widget.places,
        initialValue: (departure ? _from : _to) ?? '',
      ),
    );
    if (mounted && value != null) {
      setState(() => departure ? _from = value : _to = value);
    }
  }

  Future<void> _submit() async {
    if (!_valid || _busy || widget.onSubmit == null) return;
    final departure = DateTime(
      _day!.year,
      _day!.month,
      _day!.day,
      _time!.hour,
      _time!.minute,
    );
    if (!departure.isAfter(DateTime.now())) {
      setState(() => _error = '앞으로 출발할 날짜와 시간을 선택해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit!(
        RideDraft(
          category: RideCategory.taxi,
          originName: _from!,
          destinationName: _to!,
          departureAt: departure,
          capacity: _people,
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
  Widget build(BuildContext context) => Column(
    children: [
      _PageHeader(title: '팟 만들기', onBack: widget.onBack),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text('함께 이동할 사람을 모아 보세요.', style: TextStyle(color: _muted)),
            const SizedBox(height: 18),
            _FieldLabel(title: '카테고리'),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('택시'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: ChoiceChip(
                    label: Text('카풀 · 준비 중'),
                    selected: false,
                    onSelected: null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _FieldLabel(title: '출발지'),
            _PlaceButton(
              value: _from ?? '출발 장소를 골라 주세요',
              onTap: _busy ? null : () => _choosePlace(true),
            ),
            const SizedBox(height: 10),
            _FieldLabel(title: '도착지'),
            _PlaceButton(
              value: _to ?? '도착 장소를 골라 주세요',
              onTap: _busy ? null : () => _choosePlace(false),
            ),
            const SizedBox(height: 14),
            _FieldLabel(title: '출발 날짜'),
            Wrap(
              spacing: 7,
              children: _dateOptions
                  .map(
                    (value) => ChoiceChip(
                      label: Text(value),
                      selected: _when.split(' ').first == value,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              final index = _dateOptions.indexOf(value),
                                  now = DateTime.now();
                              _day = DateTime(
                                now.year,
                                now.month,
                                now.day + index,
                              );
                            }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            _FieldLabel(title: '출발 시각'),
            Wrap(
              spacing: 7,
              children: ['18:00', '18:15', '18:30', '18:45']
                  .map(
                    (value) => ChoiceChip(
                      label: Text(value),
                      selected: _when.endsWith(value),
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              final parts = value.split(':');
                              _time = TimeOfDay(
                                hour: int.parse(parts[0]),
                                minute: int.parse(parts[1]),
                              );
                            }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            _FieldLabel(title: '모집 인원 · 나 포함'),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2명')),
                ButtonSegment(value: 3, label: Text('3명')),
                ButtonSegment(value: 4, label: Text('4명')),
              ],
              selected: {_people},
              onSelectionChanged: _busy
                  ? null
                  : (values) => setState(() => _people = values.first),
            ),
            const SizedBox(height: 14),
            _FieldLabel(title: '조건 · 선택'),
            TextField(
              controller: _condition,
              enabled: !_busy,
              maxLength: 100,
              decoration: const InputDecoration(
                hintText: '예: 캐리어 있어요',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: _line),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: _danger)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _valid && !_busy && widget.onSubmit != null
                  ? _submit
                  : null,
              child: Text(_busy ? '등록 중…' : '팟 올리기'),
            ),
            const SizedBox(height: 6),
            if (widget.onSubmit == null)
              const Text(
                '실제 등록 기능이 연결되면 팟을 올릴 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: _muted),
              ),
          ],
        ),
      ),
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _ink,
      ),
    ),
  );
}

class _PlaceButton extends StatelessWidget {
  const _PlaceButton({required this.value, this.onTap});
  final String value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      minimumSize: const Size.fromHeight(50),
      foregroundColor: _ink,
      backgroundColor: Colors.white,
    ),
    child: Row(
      children: [
        Expanded(child: Text(value)),
        const Icon(Icons.keyboard_arrow_down, color: _muted),
      ],
    ),
  );
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
                '참여자 ${ride.people}명  ·  1인 예상 요금 정보 없음',
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
                        child: Text(arrived ? '도착했어요' : '도착했어요'),
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
            IconButton.filled(
              onPressed: null,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    ],
  );
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
              ?selector,
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
      _PageHeader(title: '팟 찾기', onBack: onBack),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off_rounded, size: 48, color: _subtle),
              const SizedBox(height: 14),
              const Text(
                '아직 조건에 맞는 팟이 없어요',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '키워드 알림을 켜 두면 새 팟을 알려드려요.',
                style: TextStyle(fontSize: 13, color: _muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onKeywords,
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('키워드 알림 받기'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('직접 팟 만들기'),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
