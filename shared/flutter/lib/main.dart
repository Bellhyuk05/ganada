import 'dart:async';

import 'package:flutter/material.dart';
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
import 'features/ride_flow/ride_flow_feature.dart';
import 'ui/gachita_theme.dart';
import 'ui/ride_pages.dart';

// Supabase 연결을 준비한 뒤, 로그인 상태에 맞는 화면으로 앱을 실행
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isLive ||
      AppConfig.supabaseUrl.isEmpty ||
      AppConfig.supabaseKey.isEmpty) {
    runApp(                                                                                 // 실행 설정이 유효하지 않거나 Supabase URL 또는 키가 비어 있으면, 연결 설정 안내 화면을 표시
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
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
    // 팀 기능 연결: F-04 참여 신청·승인, F-05 그룹 채팅, F-06 출발·도착 확인 (원교).
    // 다른 기능은 attachRideFlow(client, TeamFeatureBindings(...))의 두 번째 인자로 이어 붙입니다.
    final teamFeatures = attachRideFlow(Supabase.instance.client);
    runApp(
      SessionGate(                                                                          // 로그인 상태 확인
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

// 화면 종류 정의
enum _Page {
  home,       // 모집, 마감 팟 게시판
  trips,      // 내가 방장이거나 승인 참여자인 팟 목록
  notices,    // 키워드 알림과 동승자 평가 안내
  my,         // 나의 페이지
  detail,     // 팟 상세
  rating,     // 동승자 평가
  keywords,   // 키워드 등록,삭제,관리
  blocks,     // 차단 목록
  settings,   // 키워드 알림 및 기기 푸시 설정
  applicants, // 팟 참여 신청자 목록
  create,     // 팟 만들기
  chat,       // 팟 대화방
  account,    // 계정 관리
}

// 외부에서 필요한 객체나 함수를 전달받습니다.
class GachiTaApp extends StatefulWidget {
  const GachiTaApp({
    super.key,
    required this.repository,                                                   // repository: 실제 데이터 조회와 저장 기능
    this.onRequestJoin,                                                         // onRequestJoin: 참여 신청 처리 함수
    this.teamFeatures = const TeamFeatureBindings(),                            // teamFeatures: 외부 기능 연결 객체
  });
  final CompanionRepository repository;
  final Future<void> Function(String rideId)? onRequestJoin;
  final TeamFeatureBindings teamFeatures;
  @override
  State<GachiTaApp> createState() => _GachiTaAppState();                        // 상태 객체(_GachiTaAppState의 인스턴스)를 생성
}                                                                               // GachiTaApp: 외부에서 받은 설정과 객체 보관
                                                                                // _GachiTaAppState: 현재 화면과 처리 상태 관리
// 화면 이동, 참여 신청, 푸시 상태를 관리하는 앱의 상태 클래스
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
  Future<void> Function(String rideId)? get _joinHandler =>                     // 참여 신청에 사용할 함수를 선택 (widget.onRequestJoin 우선)
      widget.onRequestJoin ?? widget.teamFeatures.onRequestJoin;

  // 상태 객체 초기화
  // 상태 객체 초기화 시 컨트롤러, 푸시 서비스를 연결 -> 초기 데이터 로딩 시작
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

  // 화면 구성을 위한 초기 데이터를 조회
  // 프로필 선택 과정에서 앱이 종료되었다면, 선택한 사진을 다시 불러와 편집 창을 엽니다.
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

  // 컨트롤러의 변경된 상태(데이터 변경)를 화면에 반영
  void _changed() {
    if (!mounted) return;
    _push.moduleReady = _controller.featureReady(CompanionFeature.keywords);    // 키워드 기능의 준비 상태를 푸시 서비스에 전달
    if (_push.moduleReady && !_pushStarting) unawaited(_startPush());
    setState(() {});                                                            // 상태 변경을 알리고, 화면 재구성을 요청
  }

  // 푸시 서비스 시작
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

  // 화면 아래에 잠깐 나타나는 SnackBar를 표시
  void _message(String value) => _messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(value)));

  // 현재 페이지 저장 및 다음 페이지로 이동
  void _go(_Page page) {
    setState(() {
      _history.add(_page);
      _page = page;
    });
  }

  // go에서 저장한 이전 페이지로 이동 (기록이 없으면 home으로 이동)
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

  // 하단 탭 선택 처리
  void _goTab(int index) {
    setState(() {
      _tab = index;
      _history.clear();
      _page = [_Page.home, _Page.trips, _Page.notices, _Page.my][index];
    });
    unawaited(_controller.refresh());
  }

  // 현재 탭의 최상위 화면 여부 확인
  bool get _isRootPage =>
      [_Page.home, _Page.trips, _Page.notices, _Page.my].contains(_page);

  // 선택한 팟의 아이디를 저장하고, 상세 페이지로 이동
  void _openRide(RideRecord ride) {
    _rideId = ride.id;
    _go(_Page.detail);
  }

  // 팟 ID로 팟 열기
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

  // 팟 참여 신청 처리
  Future<void> _requestJoin(RideRecord ride) async {
    final request = _joinHandler;
    if (request == null || _joining) return;
    setState(() => _joining = true);
    try {
      final status = _controller.snapshot?.companionStatus;
      if (status == null || status == CompanionStatus.error) {                  // 조회결과가 null또는 에러인 경우: 중단
        throw FeatureFailure(_controller.companionMessage);
      }
      if (status == CompanionStatus.ready) {
        if (!_controller.featureReady(CompanionFeature.blocking))               { // F-10 차단 기능 점검
          throw FeatureFailure(
            _controller.featureMessage(CompanionFeature.blocking),
          );
        }
        final blocked = await widget.repository                                 // 차단한 참여자 존재 여부 확인
            .blockedParticipants(ride.id)
            .timeout(const Duration(seconds: 20));
        if (!mounted) return;
        if (blocked.isNotEmpty) {                                               // F-10 차단 사용자 존재 시, 팝업을 노출
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
      await request(ride.id).timeout(const Duration(seconds: 20));              // 팟 신청 함수 호출
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

  // 로그아웃
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

  // 현재 선택한 팟 찾기 (조회 결과 기준)
  RideRecord? get _selectedRide => _controller.snapshot?.rides
      .where((ride) => ride.id == _rideId)
      .firstOrNull;

  // 팟 화면의 예외 처리
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

  // 팟 상세 화면 구성
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

  // 외부 화면에 전달할 정보 묶기 (대화방, 신청자 관리 화면 연결 시)
  TeamRideContext _teamContext(RideRecord ride) => TeamRideContext(
    ride: ride,
    userId: widget.repository.userId,
    onBack: _back,
    onRefresh: _controller.refresh,
    onRatings: () => _go(_Page.rating),
  );

  // 팟 생성 함수 호출
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

  // 연결된 공통 동작 실행 (팟id를 받아  실행하는 함수 처리)
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

  // 대화방 화면 선택
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

  // 신청자 화면 선택
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

  // 계정 관리 화면 선택
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

  // 기본 화면의 상태 유지
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

  // 화면 생성 및 내부 작동 정의
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

  // 공통 디자인과 기본 화면 구조
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
        bottomNavigationBar: _isRootPage                                          // 하단 탭
            ? NavigationBar(
                selectedIndex: _tab,
                height: 68,
                backgroundColor: Colors.white,
                indicatorColor: GachiTaTheme.primaryLight,
                onDestinationSelected: _goTab,
                destinations: const [                                             // 하단 탭의 아이콘과 표시 이름 정의
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

  // 자원 정리
  @override
  void dispose() {
    _push.dispose();
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }
}
