import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_config.dart';
import 'core/push_service.dart';
import 'core/session_gate.dart';
import 'core/team_features.dart';
import 'features/companion/controller.dart';
import 'features/companion/models.dart';
import 'features/companion/profile_photo_editor.dart';
import 'features/companion/repositories.dart';
import 'features/companion/screens.dart';
import 'ui/gachita_theme.dart';
import 'ui/ride_pages.dart';

/// 팀 기준 초안의 rides 테이블에 동행팟을 생성하고 생성된 ID를 반환합니다.
Future<String> _handleCreateRide(RideDraft draft) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;
  if (uid == null) {
    throw const FeatureFailure('로그인이 필요해요.');
  }

  try {
    final inserted = await client
        .from('rides')
        .insert({
      'host_id': uid,
      'origin_name': draft.originName.trim(),
      'destination_name': draft.destinationName.trim(),
      'condition_text': draft.conditionText.trim(),
      'capacity': draft.capacity,
      'departure_at': draft.departureAt.toUtc().toIso8601String(),
      'status': 'recruiting',
    })
        .select('id')
        .single();

    final rideId = inserted['id'].toString();

    // 방장(호스트)을 승인된 멤버로 함께 등록 시도 (RPC 또는 테이블 트리거가 없을 경우 대비)
    try {
      await client.from('ride_members').upsert({
        'ride_id': rideId,
        'user_id': uid,
        'status': 'approved',
      });
    } catch (_) {
      // 서버 트리거가 이미 처리했거나 테이블 구조가 다른 경우 무시
    }

    return rideId;
  } on PostgrestException catch (e) {
    throw FeatureFailure('동행팟 등록에 실패했어요: ${e.message}');
  }
}

/// 팀 기준 초안의 동행팟 참여 신청을 처리합니다.
Future<void> _handleRequestJoin(String rideId) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;
  if (uid == null) {
    throw const FeatureFailure('로그인이 필요해요.');
  }

  try {
    // 1순위: RPC 함수가 정의되어 있다면 호출
    await client.rpc('request_join_ride', params: {'p_ride_id': rideId});
    return;
  } catch (_) {
    // 2순위: ride_members 테이블에 직접 insert
    try {
      await client.from('ride_members').insert({
        'ride_id': rideId,
        'user_id': uid,
        'status': 'approved',
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const FeatureFailure('이미 참여 신청했거나 참여 중인 팟이에요.');
      }
      throw FeatureFailure('참여 신청을 처리하지 못했어요: ${e.message}');
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko', null);

  if (!AppConfig.isLive ||
      AppConfig.supabaseUrl.isEmpty ||
      AppConfig.supabaseKey.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Supabase 연결 설정이 필요합니다. README의 적용 가이드를 확인하세요.'),
            ),
          ),
        ),
      ),
    );
    return;
  }

  const teamFeatures = TeamFeatureBindings(
    onCreateRide: _handleCreateRide,
    onRequestJoin: _handleRequestJoin,
  );

  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
    runApp(
      SessionGate(
        authenticationBuilder: teamFeatures.authenticationBuilder,
        builder: (repository) =>
            GachiTaApp(repository: repository, teamFeatures: teamFeatures),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('연결을 준비하지 못했어요. 설정과 네트워크를 확인해 주세요.')),
        ),
      ),
    );
  }
}

enum _Page {
  home,
  trips,
  notices,
  my,
  detail,
  rating,
  keywords,
  blocks,
  settings,
  applicants,
  create,
  chat,
  account,
}

class GachiTaApp extends StatefulWidget {
  const GachiTaApp({
    super.key,
    required this.repository,
    this.onRequestJoin,
    this.teamFeatures = const TeamFeatureBindings(),
  });
  final CompanionRepository repository;
  final Future<void> Function(String rideId)? onRequestJoin;
  final TeamFeatureBindings teamFeatures;
  @override
  State<GachiTaApp> createState() => _GachiTaAppState();
}

class _GachiTaAppState extends State<GachiTaApp> {
  late final CompanionController _controller;
  late final PushService _push;
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  _Page _page = _Page.home;
  final List<_Page> _history = [];
  int _tab = 0;
  String? _rideId;
  bool _joining = false;
  bool _pushStarting = false;
  bool _teamBusy = false;
  Future<void> Function(String rideId)? get _joinHandler =>
      widget.onRequestJoin ?? widget.teamFeatures.onRequestJoin;

  @override
  void initState() {
    super.initState();
    _controller = CompanionController(widget.repository);
    _push = PushService(
      widget.repository,
      onInboxChanged: _controller.refresh,
      onOpenRide: _openRideId,
    );
    _controller.addListener(_changed);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _controller.refresh();
    if (!mounted || !_controller.companionReady) return;
    try {
      final recovered = await GalleryProfilePhotoSource().recover();
      if (recovered != null && mounted && _controller.companionReady) {
        await showProfilePhotoEditor(
          _navigator.currentContext!,
          _controller,
          recoveredBytes: recovered,
        );
      }
    } catch (_) {
      if (mounted) _message('선택했던 사진을 복구하지 못했어요. MY에서 다시 선택해 주세요.');
    }
  }

  void _changed() {
    if (!mounted) return;
    _push.moduleReady = _controller.featureReady(CompanionFeature.keywords);
    if (_push.moduleReady && !_pushStarting) unawaited(_startPush());
    setState(() {});
  }

  Future<void> _startPush() async {
    _pushStarting = true;
    try {
      await _push.start();
    } catch (_) {
      if (mounted) _message('기기 푸시 등록을 완료하지 못했어요. 알림 설정에서 다시 시도해 주세요.');
    } finally {
      _pushStarting = false;
    }
  }

  void _message(String value) => _messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(value)));

  void _go(_Page page) {
    setState(() {
      _history.add(_page);
      _page = page;
    });
  }

  void _back() => setState(() {
    _page = _history.isEmpty ? _Page.home : _history.removeLast();
    final rootIndex = [
      _Page.home,
      _Page.trips,
      _Page.notices,
      _Page.my,
    ].indexOf(_page);
    if (rootIndex >= 0) _tab = rootIndex;
  });

  void _goTab(int index) {
    setState(() {
      _tab = index;
      _history.clear();
      _page = [_Page.home, _Page.trips, _Page.notices, _Page.my][index];
    });
    unawaited(_controller.refresh());
  }

  bool get _isRootPage =>
      [_Page.home, _Page.trips, _Page.notices, _Page.my].contains(_page);

  void _openRide(RideRecord ride) {
    _rideId = ride.id;
    _go(_Page.detail);
  }

  Future<void> _openRideId(String id) async {
    await _controller.refresh();
    if (!mounted) return;
    final ride = _controller.snapshot?.rides
        .where((r) => r.id == id)
        .firstOrNull;
    if (ride == null) {
      _message(_controller.snapshot?.rideError ?? '이 팟은 삭제되었거나 더 이상 볼 수 없어요.');
      return;
    }
    _openRide(ride);
  }

  Future<void> _requestJoin(RideRecord ride) async {
    final request = _joinHandler;
    if (request == null || _joining) return;
    setState(() => _joining = true);
    try {
      final status = _controller.snapshot?.companionStatus;
      if (status == null || status == CompanionStatus.error) {
        throw FeatureFailure(_controller.companionMessage);
      }
      if (status == CompanionStatus.ready) {
        if (!_controller.featureReady(CompanionFeature.blocking)) {
          throw FeatureFailure(
            _controller.featureMessage(CompanionFeature.blocking),
          );
        }
        final blocked = await widget.repository
            .blockedParticipants(ride.id)
            .timeout(const Duration(seconds: 20));
        if (!mounted) return;
        if (blocked.isNotEmpty) {
          final proceed = await showDialog<bool>(
            context: _navigator.currentContext!,
            builder: (context) => AlertDialog(
              title: const Text('차단한 사용자가 참여 중인 팟이에요'),
              content: const Text('그래도 신청할까요?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('신청하기'),
                ),
              ],
            ),
          );
          if (proceed != true) return;
        }
      }
      await request(ride.id).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _message('참여 신청을 보냈어요.');
      await _controller.refresh();
    } catch (e) {
      if (mounted) {
        _message(
          e is FeatureFailure ? e.message : '신청 결과를 확인하지 못했어요. 최신 상태를 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _logout() async {
    try {
      await _push.disconnect().timeout(const Duration(seconds: 20));
    } catch (_) {
      _push.dispose();
    }
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      if (mounted) _message('로그아웃을 완료하지 못했어요. 다시 시도해 주세요.');
    }
  }

  Widget _feed({required bool mine}) => mine
      ? GachiTaTripsPage(
    controller: _controller,
    userId: widget.repository.userId,
    onOpenRide: _openRide,
    onRatings: () => _go(_Page.rating),
  )
      : GachiTaHomePage(
    controller: _controller,
    onOpenRide: _openRide,
    onNotifications: () => _goTab(2),
    onKeywords: () => _go(_Page.keywords),
    onCreate: () => _go(_Page.create),
    onSearchNearby: widget.teamFeatures.onSearchNearby,
  );

  RideRecord? get _selectedRide => _controller.snapshot?.rides
      .where((ride) => ride.id == _rideId)
      .firstOrNull;

  Widget _unavailableRide() => Column(
    children: [
      RidePageHeader(title: '팟', onBack: _back),
      Expanded(
        child: Center(
          child: RideEmptyState(
            message:
            _controller.snapshot?.rideError ??
                _controller.error ??
                (_controller.loading
                    ? '팟 정보를 불러오는 중이에요.'
                    : '이 팟은 삭제되었거나 더 이상 볼 수 없어요.'),
            action: TextButton(
              onPressed: _controller.loading ? null : _controller.refresh,
              child: const Text('다시 불러오기'),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _detail() {
    final ride = _selectedRide;
    if (ride == null) return _unavailableRide();
    return GachiTaRideDetailPage(
      controller: _controller,
      ride: ride,
      userId: widget.repository.userId,
      onBack: _back,
      onChat: () => _go(_Page.chat),
      joining: _joining,
      joinUnavailable: _joinHandler == null,
      onRequestJoin:
      _joinHandler == null ||
          _joining ||
          _controller.loading ||
          _controller.busy
          ? null
          : () => _requestJoin(ride),
      onApplicants: ride.host.id == widget.repository.userId
          ? () => _go(_Page.applicants)
          : null,
    );
  }

  TeamRideContext _teamContext(RideRecord ride) => TeamRideContext(
    ride: ride,
    userId: widget.repository.userId,
    onBack: _back,
    onRefresh: _controller.refresh,
    onRatings: () => _go(_Page.rating),
  );

  Future<void> _createRide(RideDraft draft) async {
    final create = widget.teamFeatures.onCreateRide;
    if (create == null || _teamBusy) return;
    setState(() => _teamBusy = true);
    try {
      final id = await create(draft).timeout(const Duration(seconds: 20));
      if (id.trim().isEmpty) {
        throw const FeatureFailure(
          '등록 결과의 팟 ID를 확인하지 못했어요. 다시 등록하기 전에 목록을 확인해 주세요.',
        );
      }
      await _controller.refresh();
      if (!mounted) return;
      setState(() {
        _rideId = id;
        _page = _Page.detail;
      });
      _message('팟을 등록했어요.');
    } finally {
      if (mounted) setState(() => _teamBusy = false);
    }
  }

  Future<void> _runTeamAction(
      Future<void> Function(String)? action,
      String rideId,
      ) async {
    if (action == null || _teamBusy) return;
    setState(() => _teamBusy = true);
    try {
      await action(rideId).timeout(const Duration(seconds: 20));
      await _controller.refresh();
    } catch (error) {
      if (mounted) {
        _message(
          error is FeatureFailure
              ? error.message
              : '처리 결과를 확인하지 못했어요. 다시 요청하기 전에 새로고침해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _teamBusy = false);
    }
  }

  Widget _chat() {
    final ride = _selectedRide;
    if (ride == null) return _unavailableRide();
    final canEnter =
        ride.host.id == widget.repository.userId ||
            ride.members.any(
                  (member) =>
              member.user.id == widget.repository.userId &&
                  member.status == 'approved',
            );
    if (!canEnter) return _unavailableRide();
    final builder = widget.teamFeatures.chatBuilder;
    if (builder != null) {
      return Builder(
        builder: (context) => builder(context, _teamContext(ride)),
      );
    }
    return GachiTaChatShell(
      controller: _controller,
      ride: ride,
      userId: widget.repository.userId,
      onBack: _back,
      onRatings: () => _go(_Page.rating),
      busy: _teamBusy,
      onBoarding: widget.teamFeatures.onConfirmBoarding == null
          ? null
          : () =>
          _runTeamAction(widget.teamFeatures.onConfirmBoarding, ride.id),
      onArrival: widget.teamFeatures.onConfirmArrival == null
          ? null
          : () => _runTeamAction(widget.teamFeatures.onConfirmArrival, ride.id),
    );
  }

  Widget _applicants() {
    final ride = _selectedRide;
    if (ride == null) return _unavailableRide();
    final builder = widget.teamFeatures.applicantsBuilder;
    if (builder != null) {
      return Builder(
        builder: (context) => builder(context, _teamContext(ride)),
      );
    }
    return CompanionApplicantsPage(
      controller: _controller,
      rideId: ride.id,
      onBack: _back,
    );
  }

  Widget _account() => Column(
    children: [
      RidePageHeader(title: '계정 관리', onBack: _back),
      Expanded(
        child: widget.teamFeatures.accountBuilder == null
            ? const Center(child: RideEmptyState(message: '계정 관리는 아직 준비 중이에요.'))
            : Builder(builder: widget.teamFeatures.accountBuilder!),
      ),
    ],
  );

  Widget _body() => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: !_isRootPage,
        child: TickerMode(
          enabled: _isRootPage,
          child: IndexedStack(
            index: _tab,
            children: [
              for (final page in [
                _Page.home,
                _Page.trips,
                _Page.notices,
                _Page.my,
              ])
                _pageContent(page),
            ],
          ),
        ),
      ),
      if (!_isRootPage) _pageContent(_page),
    ],
  );

  Widget _pageContent(_Page page) {
    return switch (page) {
      _Page.home => _feed(mine: false),
      _Page.trips => _feed(mine: true),
      _Page.detail => _detail(),
      _Page.notices => GachiTaNoticesPage(
        controller: _controller,
        onOpenRide: _openRideId,
        onRatings: () => _go(_Page.rating),
      ),
      _Page.my => GachiTaMyPage(
        controller: _controller,
        onKeywords: () => _go(_Page.keywords),
        onBlocks: () => _go(_Page.blocks),
        onSettings: () => _go(_Page.settings),
        onRatings: () => _go(_Page.rating),
        onLogout: _logout,
        onAccount: () => _go(_Page.account),
      ),
      _Page.rating => GachiTaRatingPage(controller: _controller, onBack: _back),
      _Page.keywords => GachiTaKeywordPage(
        controller: _controller,
        onBack: _back,
      ),
      _Page.blocks => GachiTaBlocksPage(controller: _controller, onBack: _back),
      _Page.settings => GachiTaSettingsPage(
        controller: _controller,
        onBack: _back,
        enablePush: _push.enable,
      ),
      _Page.applicants => _applicants(),
      _Page.create => GachiTaCreateRidePage(
        onBack: _back,
        places: (_controller.snapshot?.rides ?? <RideRecord>[])
            .expand((ride) => [ride.from, ride.to])
            .where((place) => place.trim().isNotEmpty)
            .toSet()
            .toList(),
        onSubmit: widget.teamFeatures.onCreateRide == null ? null : _createRide,
      ),
      _Page.chat => _chat(),
      _Page.account => _account(),
    };
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    scaffoldMessengerKey: _messenger,
    debugShowCheckedModeBanner: false,
    title: '같이타(GachiTa)',
    theme: GachiTaTheme.data,
    home: PopScope<Object?>(
      canPop: _isRootPage,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(child: _body()),
        floatingActionButton: _page == _Page.home
            ? FloatingActionButton.extended(
          onPressed: () => _go(_Page.create),
          backgroundColor: GachiTaTheme.primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('팟 만들기'),
        )
            : null,
        bottomNavigationBar: _isRootPage
            ? NavigationBar(
          selectedIndex: _tab,
          height: 68,
          backgroundColor: Colors.white,
          indicatorColor: GachiTaTheme.primaryLight,
          onDestinationSelected: _goTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.luggage_outlined),
              selectedIcon: Icon(Icons.luggage),
              label: '내 팟',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_none),
              selectedIcon: Icon(Icons.notifications),
              label: '알림',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'MY',
            ),
          ],
        )
            : null,
      ),
    ),
  );

  @override
  void dispose() {
    _push.dispose();
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }
}