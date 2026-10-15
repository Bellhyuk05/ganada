import 'package:flutter/material.dart';

import '../../core/team_features.dart';
import '../../ui/gachita_theme.dart';
import '../../ui/ride_pages.dart' show RidePageHeader;
import 'ride_flow_repository.dart';
import 'ride_flow_widgets.dart';

/// F-04 방장용: 신청자 승인·거절, 참여자 내보내기, 팟 취소.
class RideManagePage extends StatefulWidget {
  const RideManagePage({
    super.key,
    required this.repository,
    required this.rideContext,
  });
  final RideFlowRepository repository;
  final TeamRideContext rideContext;
  @override
  State<RideManagePage> createState() => _RideManagePageState();
}

class _RideManagePageState extends State<RideManagePage> {
  List<RideApplicant>? _applicants;
  RideFlowState? _state;
  String? _error;
  bool _loading = true;
  bool _acting = false;

  RideFlowRepository get _repo => widget.repository;
  String get _rideId => widget.rideContext.ride.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final applicants = await _repo.applicants(_rideId);
      final state = await _repo.state(_rideId);
      if (!mounted) return;
      setState(() {
        _applicants = applicants;
        _state = state;
      });
    } catch (e) {
      if (mounted) setState(() => _error = rideFlowError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await action();
      _toast(done);
    } catch (e) {
      _toast(rideFlowError(e));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    if (!mounted) return;
    await _load();
    await widget.rideContext.onRefresh();
  }

  Future<void> _reject(RideApplicant applicant) async {
    final ok = await confirmRideAction(
      context,
      title: '${applicant.name}님의 신청을 거절할까요?',
      message: '거절한 신청은 목록에서 사라져요.',
      confirmLabel: '거절',
    );
    if (ok) await _run(() => _repo.reject(_rideId, applicant.id), '거절했어요.');
  }

  Future<void> _kick(RideFlowMember member) async {
    final ok = await confirmRideAction(
      context,
      title: '${member.name}님을 내보낼까요?',
      message: '내보낸 사람은 이 팟에 다시 신청할 수 없어요. 참여 안 함으로는 기록되지 않아요.',
      confirmLabel: '내보내기',
      danger: true,
    );
    if (ok) await _run(() => _repo.kick(_rideId, member.id), '내보냈어요.');
  }

  Future<void> _cancelRide() async {
    final ok = await confirmRideAction(
      context,
      title: '팟을 취소할까요?',
      message: '취소하면 되돌릴 수 없고, 참여자 모두에게 채팅방 안내가 표시돼요.',
      confirmLabel: '팟 취소',
      danger: true,
    );
    if (ok) await _run(() => _repo.cancelRide(_rideId), '팟을 취소했어요.');
  }

  String _statusLabel(RideFlowState s) => switch (s.phase) {
    RidePhase.cancelled => '취소된 팟',
    RidePhase.ended => '운행 종료',
    RidePhase.departed => '이동 중',
    RidePhase.boarding => '출발 확인 중',
    RidePhase.before => s.status == 'full' ? '모집 완료' : '모집 중',
  };

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final applicants = _applicants ?? const <RideApplicant>[];
    final canApprove =
        state != null &&
        state.phase == RidePhase.before &&
        state.status == 'recruiting' &&
        state.occupancy < state.capacity;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: RidePageHeader(
                title: '신청자 관리',
                onBack: widget.rideContext.onBack,
              ),
            ),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: '다시 불러오기',
            ),
            const SizedBox(width: 8),
          ],
        ),
        if (_loading || _acting) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: state == null
              ? Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error ?? '정보를 불러오지 못했어요.',
                                textAlign: TextAlign.center,
                              ),
                              TextButton(
                                onPressed: _load,
                                child: const Text('다시 불러오기'),
                              ),
                            ],
                          ),
                        ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: RideFlowNote(
                          text: _error!,
                          color: GachiTaTheme.danger,
                        ),
                      ),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${state.occupancy}/${state.capacity}명',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: GachiTaTheme.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    '정원이 차면 자동으로 모집이 마감돼요.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: GachiTaTheme.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            RideFlowTag(
                              label: _statusLabel(state),
                              color: GachiTaTheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    RideFlowSectionTitle('참여 신청 ${applicants.length}'),
                    if (applicants.isEmpty)
                      const Text(
                        '대기 중인 신청이 없어요.',
                        style: TextStyle(color: GachiTaTheme.muted),
                      ),
                    if (applicants.isNotEmpty && !canApprove)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: RideFlowNote(
                          text: '정원이 찼거나 출발 시각이 지나서 지금은 승인할 수 없어요.',
                          color: GachiTaTheme.warning,
                        ),
                      ),
                    for (final applicant in applicants)
                      _ApplicantCard(
                        applicant: applicant,
                        busy: _acting,
                        canApprove: canApprove,
                        onApprove: () => _run(
                          () => _repo.approve(_rideId, applicant.id),
                          '${applicant.name}님을 승인했어요.',
                        ),
                        onReject: () => _reject(applicant),
                      ),
                    RideFlowSectionTitle('참여 중 ${state.members.length}명'),
                    for (final member in state.members)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: RideFlowAvatar(name: member.name),
                          title: Text(member.name),
                          subtitle: member.isHost ? const Text('방장 (나)') : null,
                          trailing: !member.isHost && state.changesAllowed
                              ? TextButton(
                                  onPressed: _acting ? null : () => _kick(member),
                                  style: TextButton.styleFrom(
                                    foregroundColor: GachiTaTheme.danger,
                                  ),
                                  child: const Text('내보내기'),
                                )
                              : null,
                        ),
                      ),
                    if (state.changesAllowed) ...[
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _acting ? null : _cancelRide,
                        style: TextButton.styleFrom(
                          foregroundColor: GachiTaTheme.danger,
                        ),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('팟 취소하기'),
                      ),
                      const RideFlowNote(
                        text: '출발 확인이 끝나기 전까지만 내보내거나 팟을 취소할 수 있어요.',
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({
    required this.applicant,
    required this.busy,
    required this.canApprove,
    required this.onApprove,
    required this.onReject,
  });
  final RideApplicant applicant;
  final bool busy;
  final bool canApprove;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RideFlowAvatar(name: applicant.name, radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            applicant.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (applicant.blocked) ...[
                          const SizedBox(width: 6),
                          const RideFlowTag(
                            label: '차단한 사용자',
                            color: GachiTaTheme.danger,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      applicant.statsLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: GachiTaTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onReject,
                  child: const Text('거절'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: busy || !canApprove ? null : onApprove,
                  style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
                  child: const Text('승인'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
