import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../core/team_features.dart';
import '../../ui/gachita_theme.dart';
import '../../ui/ride_pages.dart' show RidePageHeader, rideDateLabel;
import 'ride_flow_repository.dart';
import 'ride_flow_widgets.dart';

/// F-05 그룹 채팅 + F-06 출발·도착 확인 카드 + F-04 나가기·내보내기·팟 취소.
class RideChatPage extends StatefulWidget {
  const RideChatPage({
    super.key,
    required this.repository,
    required this.rideContext,
  });
  final RideFlowRepository repository;
  final TeamRideContext rideContext;
  @override
  State<RideChatPage> createState() => _RideChatPageState();
}

class _RideChatPageState extends State<RideChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <RideChatMessage>[];
  final _ids = <int>{};
  RideFlowState? _state;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  bool _acting = false;
  RealtimeChannel? _channel;
  Timer? _ticker;

  RideFlowRepository get _repo => widget.repository;
  String get _rideId => widget.rideContext.ride.id;
  String get _me => widget.rideContext.userId;
  bool get _isHost => _state?.hostId == _me;

  @override
  void initState() {
    super.initState();
    _channel = _repo.subscribe(_rideId, _onRealtime);
    // Phase changes are time based (출발 시각, 10분, 3시간), so re-check periodically.
    _ticker = Timer.periodic(const Duration(seconds: 20), (_) => _reloadState());
    _loadAll();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    final channel = _channel;
    if (channel != null) _repo.unsubscribe(channel);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await _repo.state(_rideId);
      final messages = await _repo.messages(_rideId);
      if (!mounted) return;
      setState(() {
        _state = state;
        _messages.clear();
        _ids.clear();
        _append(messages);
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) setState(() => _error = rideFlowError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadState() async {
    try {
      final state = await _repo.state(_rideId);
      if (mounted) setState(() => _state = state);
    } catch (_) {
      // Keep the last known state; the header refresh button shows errors.
    }
  }

  Future<void> _reloadMessages() async {
    try {
      final messages = await _repo.messages(_rideId);
      if (!mounted) return;
      setState(() => _append(messages));
      _scrollToEnd();
    } catch (_) {}
  }

  void _append(List<RideChatMessage> incoming) {
    var added = false;
    for (final message in incoming) {
      if (_ids.add(message.id)) {
        _messages.add(message);
        added = true;
      }
    }
    if (added) _messages.sort((a, b) => a.id.compareTo(b.id));
  }

  void _onRealtime(RideChatMessage message) {
    if (!mounted) return;
    setState(() => _append([message]));
    _scrollToEnd();
    if (message.system) {
      // System notices accompany membership / boarding changes.
      _reloadState();
      widget.rideContext.onRefresh();
    }
  }

  /// The message list is reversed (newest at the bottom), so the end is offset 0.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final message = await _repo.send(_rideId, text);
      if (!mounted) return;
      _input.clear();
      setState(() => _append([message]));
      _scrollToEnd();
    } catch (e) {
      _toast(rideFlowError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? done,
    bool closeAfter = false,
  }) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action();
      if (done != null) _toast(done);
      if (closeAfter) {
        await widget.rideContext.onRefresh();
        widget.rideContext.onBack();
        return;
      }
      await Future.wait([_reloadState(), _reloadMessages()]);
      await widget.rideContext.onRefresh();
    } catch (e) {
      _toast(rideFlowError(e));
      await _reloadState();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _kick(RideFlowMember member) async {
    final ok = await confirmRideAction(
      context,
      title: '${member.name}님을 내보낼까요?',
      message: '내보낸 사람은 이 팟에 다시 신청할 수 없어요. 참여 안 함으로는 기록되지 않아요.',
      confirmLabel: '내보내기',
      danger: true,
    );
    if (ok) {
      await _run(() => _repo.kick(_rideId, member.id), done: '내보냈어요.');
    }
  }

  Future<void> _leave() async {
    final ok = await confirmRideAction(
      context,
      title: '채팅방을 나갈까요?',
      message: '나가면 이 팟 참여도 취소돼요. 다시 참여하려면 새로 신청해야 해요.',
      confirmLabel: '나가기',
      danger: true,
    );
    if (ok) {
      await _run(() => _repo.leave(_rideId), done: '팟에서 나왔어요.', closeAfter: true);
    }
  }

  Future<void> _cancelRide() async {
    final ok = await confirmRideAction(
      context,
      title: '팟을 취소할까요?',
      message: '취소하면 되돌릴 수 없고, 참여자 모두에게 채팅방 안내가 표시돼요.',
      confirmLabel: '팟 취소',
      danger: true,
    );
    if (ok) await _run(() => _repo.cancelRide(_rideId), done: '팟을 취소했어요.');
  }

  Future<void> _answerAbsence(RideFlowMember member, bool present) async {
    if (!present) {
      final ok = await confirmRideAction(
        context,
        title: '${member.name}님이 안 오셨나요?',
        message: '참여 안 함으로 기록되고 프로필의 "참여 안 함" 횟수에 반영돼요.',
        confirmLabel: '안 왔어요',
        danger: true,
      );
      if (!ok) return;
    }
    await _run(() => _repo.answerAbsence(_rideId, member.id, present));
  }

  void _openMembers() {
    final state = _state;
    if (state == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            Text(
              '참여자 ${state.occupancy}/${state.capacity}명',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final member in state.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: RideFlowAvatar(name: member.name),
                title: Text(member.id == _me ? '${member.name} (나)' : member.name),
                subtitle: member.isHost ? const Text('방장') : null,
                trailing: _isHost && !member.isHost && state.changesAllowed
                    ? TextButton(
                        onPressed: _acting
                            ? null
                            : () {
                                Navigator.pop(sheetContext);
                                _kick(member);
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: GachiTaTheme.danger,
                        ),
                        child: const Text('내보내기'),
                      )
                    : state.phase == RidePhase.before
                    ? null
                    : RideFlowMemberStatus(member: member),
              ),
            if (state.changesAllowed) ...[
              const Divider(height: 24),
              if (_isHost)
                TextButton.icon(
                  onPressed: _acting
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          _cancelRide();
                        },
                  style: TextButton.styleFrom(foregroundColor: GachiTaTheme.danger),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('팟 취소하기'),
                )
              else
                TextButton.icon(
                  onPressed: _acting
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          _leave();
                        },
                  style: TextButton.styleFrom(foregroundColor: GachiTaTheme.danger),
                  icon: const Icon(Icons.logout),
                  label: const Text('채팅방 나가기'),
                ),
              Text(
                _isHost
                    ? '방장은 채팅방을 나갈 수 없고, 출발 확인 전까지 팟을 취소할 수 있어요.'
                    : '출발 확인이 끝나기 전까지만 나갈 수 있어요.',
                style: const TextStyle(fontSize: 12, color: GachiTaTheme.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final chatOpen =
        state != null && DateTime.now().toUtc().isBefore(state.chatExpiresAt);
    final canSend = chatOpen && !_sending;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: RidePageHeader(
                title: '팟 채팅',
                onBack: widget.rideContext.onBack,
              ),
            ),
            IconButton(
              onPressed: state == null ? null : _openMembers,
              icon: const Icon(Icons.people_outline),
              tooltip: '참여자',
            ),
            IconButton(
              onPressed: _loading ? null : _loadAll,
              icon: const Icon(Icons.refresh),
              tooltip: '다시 불러오기',
            ),
            const SizedBox(width: 8),
          ],
        ),
        _SummaryCard(
          rideContext: widget.rideContext,
          state: state,
          isHost: _isHost,
        ),
        if (_loading || _acting) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: GachiTaTheme.danger),
                  ),
                ),
                TextButton(onPressed: _loadAll, child: const Text('다시 불러오기')),
              ],
            ),
          ),
        // 출발·탑승·도착 안내는 대화 위에 고정 (길어지면 이 영역만 스크롤).
        if (state != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    (MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom) *
                    0.38,
              ),
              child: SingleChildScrollView(child: _flowCard(state)),
            ),
          ),
        // 대화는 아래부터 쌓이고, 새 메시지는 맨 아래에 붙어요.
        Expanded(
          child: _messages.isEmpty && !_loading && _error == null
              ? const Center(
                  child: Text(
                    '아직 대화가 없어요. 만날 장소를 정해 보세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: GachiTaTheme.muted),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[_messages.length - 1 - index];
                    return _MessageBubble(
                      message: message,
                      mine: message.senderId == _me,
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: chatOpen,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: chatOpen ? '메시지를 입력하세요' : '채팅방이 닫혔어요',
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: GachiTaTheme.line),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: canSend ? _send : null,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                tooltip: '보내기',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _flowCard(RideFlowState state) {
    final me = state.member(_me);
    return switch (state.phase) {
      // 출발 전에는 한 줄로만 표시해서 대화 공간을 넓게 둠.
      RidePhase.before => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: GachiTaTheme.primaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, size: 18, color: GachiTaTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${rideFlowTime(state.departureAt)} 출발 시각이 되면 여기에서 탑승을 확인해요.',
                style: const TextStyle(fontSize: 13, color: GachiTaTheme.ink),
              ),
            ),
          ],
        ),
      ),
      RidePhase.boarding => _boardingCard(state, me),
      RidePhase.departed => _FlowCard(
        icon: Icons.local_taxi_outlined,
        title: '도착했나요?',
        children: [
          Text(
            '${rideFlowTime(state.departedAt ?? state.departureAt)} 출발 · 한 명이 도착을 확인하면 운행이 끝나요.',
            style: const TextStyle(fontSize: 12, color: GachiTaTheme.muted),
          ),
          const SizedBox(height: 12),
          if (me != null && me.boarded)
            FilledButton.icon(
              onPressed: _acting
                  ? null
                  : () => _run(
                      () => _repo.confirmArrival(_rideId),
                      done: '도착을 확인했어요.',
                    ),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('도착했어요'),
            )
          else
            const RideFlowNote(text: '탑승을 확인한 참여자가 도착을 확인할 수 있어요.'),
          if (state.autoEndAt != null) ...[
            const SizedBox(height: 10),
            RideFlowNote(
              text:
                  '${rideFlowTime(state.autoEndAt!)}까지 도착 확인이 없으면 자동으로 운행이 끝나요.',
            ),
          ],
        ],
      ),
      RidePhase.ended =>
        state.departedAt == null
            ? const _FlowCard(
                icon: Icons.event_busy_outlined,
                title: '출발 확인 없이 끝난 팟이에요',
                children: [
                  RideFlowNote(text: '아무도 탑승을 확인하지 않아서 참여 안 함은 기록하지 않았어요.'),
                ],
              )
            : _FlowCard(
                icon: Icons.check_circle_outline,
                title: '운행이 끝났어요',
                children: [
                  const RideFlowNote(text: '운행 종료 후 3일 안에 함께 탄 사람을 평가할 수 있어요.'),
                  if (me != null && me.boarded) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: widget.rideContext.onRatings,
                      icon: const Icon(Icons.star_outline),
                      label: const Text('함께 탄 사람 평가하기'),
                    ),
                  ],
                ],
              ),
      RidePhase.cancelled => const _FlowCard(
        icon: Icons.cancel_outlined,
        title: '방장이 취소한 팟이에요',
        children: [RideFlowNote(text: '이 팟은 더 이상 진행되지 않아요.')],
      ),
    };
  }

  Widget _boardingCard(RideFlowState state, RideFlowMember? me) {
    final waiting = state.members.where((m) => m.unresolved).toList();
    final askable = waiting.where((m) => m.id != _me).toList();
    return _FlowCard(
      icon: Icons.directions_car_outlined,
      title: '출발 시간이에요',
      children: [
        const Text(
          '모두 "탑승했어요"를 누르면 출발 처리돼요.',
          style: TextStyle(fontSize: 12, color: GachiTaTheme.muted),
        ),
        const SizedBox(height: 10),
        for (final member in state.members)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                RideFlowAvatar(name: member.name, radius: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    member.isHost ? '${member.name} · 방장' : member.name,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                RideFlowMemberStatus(member: member),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (me == null)
          const RideFlowNote(text: '참여자 정보를 확인하지 못했어요. 다시 불러와 주세요.')
        else if (me.noShow)
          const RideFlowNote(
            text: '다른 참여자가 참여 안 함으로 기록했어요.',
            color: GachiTaTheme.danger,
          )
        else if (!me.boarded)
          FilledButton.icon(
            onPressed: _acting
                ? null
                : () => _run(
                    () => _repo.confirmBoarding(_rideId),
                    done: '탑승을 확인했어요.',
                  ),
            icon: const Icon(Icons.check),
            label: const Text('탑승했어요'),
          )
        else
          for (final member in askable)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: GachiTaTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '아직 확인하지 않은 ${member.name}님이 오셨나요?',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _acting
                              ? null
                              : () => _answerAbsence(member, false),
                          child: const Text('안 왔어요'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _acting
                              ? null
                              : () => _answerAbsence(member, true),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(44, 48),
                          ),
                          child: const Text('왔어요'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        if (waiting.isNotEmpty) ...[
          const SizedBox(height: 8),
          RideFlowNote(
            text:
                '${rideFlowTime(state.absenceDeadline)}까지 확인하지 않은 사람은 참여 안 함으로 기록돼요.',
            color: GachiTaTheme.warning,
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.rideContext,
    required this.state,
    required this.isHost,
  });
  final TeamRideContext rideContext;
  final RideFlowState? state;
  final bool isHost;

  String _deletionText(RideFlowState s) {
    final left = s.chatExpiresAt.difference(DateTime.now().toUtc());
    if (left.isNegative) return '채팅방이 삭제됐어요.';
    if (left.inHours >= 12) {
      return '출발 12시간 후 채팅방이 사라져요. 요금 분담은 미리 끝내 주세요.';
    }
    if (left.inHours >= 1) {
      return '${left.inHours}시간 후 채팅방이 사라져요. 요금 분담은 미리 끝내 주세요.';
    }
    return '${left.inMinutes + 1}분 후 채팅방이 사라져요. 요금 분담은 미리 끝내 주세요.';
  }

  @override
  Widget build(BuildContext context) {
    final ride = rideContext.ride;
    final s = state;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${ride.from} → ${ride.to} · ${rideDateLabel(ride.departureAt)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              s == null ? '참여자 정보를 불러오는 중' : '참여자 ${s.occupancy}/${s.capacity}명',
              style: const TextStyle(fontSize: 12, color: GachiTaTheme.muted),
            ),
            if (s != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _deletionText(s),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9A5A00)),
                ),
              ),
              if (isHost && s.pendingCount > 0) ...[
                const SizedBox(height: 6),
                RideFlowNote(
                  text:
                      '참여 신청 ${s.pendingCount}명이 기다리고 있어요. 팟 상세의 "참여 신청자 확인"에서 승인해 주세요.',
                  color: GachiTaTheme.primary,
                  icon: Icons.person_add_alt_1_outlined,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({
    required this.icon,
    required this.title,
    required this.children,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: GachiTaTheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});
  final RideChatMessage message;
  final bool mine;
  @override
  Widget build(BuildContext context) {
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: GachiTaTheme.line,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              message.body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: GachiTaTheme.muted),
            ),
          ),
        ),
      );
    }
    final time = Text(
      rideFlowTime(message.createdAt),
      style: const TextStyle(fontSize: 10, color: GachiTaTheme.subtle),
    );
    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: mine ? GachiTaTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: GachiTaTheme.line),
        ),
        child: Text(
          message.body,
          style: TextStyle(
            fontSize: 14,
            color: mine ? Colors.white : GachiTaTheme.ink,
            height: 1.35,
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(
                message.senderName ?? '나간 사용자',
                style: const TextStyle(fontSize: 12, color: GachiTaTheme.muted),
              ),
            ),
          Row(
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: mine
                ? [time, const SizedBox(width: 6), bubble]
                : [bubble, const SizedBox(width: 6), time],
          ),
        ],
      ),
    );
  }
}
