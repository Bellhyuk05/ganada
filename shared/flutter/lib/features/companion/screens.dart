import 'dart:async';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'models.dart';
import 'profile_photo_editor.dart';

String localTime(DateTime value) {
  final d = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.month}/${d.day} ${two(d.hour)}:${two(d.minute)}';
}

Future<void> showCompanionProfile(
  BuildContext context,
  CompanionController controller,
  String userId,
) => showDialog<void>(
  context: context,
  builder: (_) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => controller.companionReady
        ? CompanionProfileDialog(controller: controller, userId: userId)
        : AlertDialog(
            title: const Text('프로필'),
            content: CompanionModuleNotice(controller: controller),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
  ),
);

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.controller,
    required this.user,
    this.radius = 20,
    this.loadPhoto = true,
  });
  final CompanionController controller;
  final UserSummary user;
  final double radius;
  final bool loadPhoto;

  Widget _image(ProfilePhoto? photo) => ClipOval(
    child: SizedBox.square(
      dimension: radius * 2,
      child: ColoredBox(
        color: const Color(0xFFEEF1FF),
        child: photo == null
            ? Icon(Icons.person, size: radius, color: const Color(0xFF3B5BFD))
            : Image.memory(
                photo.bytes,
                fit: BoxFit.cover,
                cacheWidth: ProfilePhoto.maxDimension,
                cacheHeight: ProfilePhoto.maxDimension,
                errorBuilder: (_, _, _) => Icon(Icons.person, size: radius),
              ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (user.photo != null || !loadPhoto || !controller.companionReady) {
      return _image(user.photo);
    }
    return FutureBuilder<ProfileStats>(
      future: controller.visibleProfile(user.id),
      builder: (_, snapshot) => _image(
        snapshot.connectionState == ConnectionState.done && !snapshot.hasError
            ? snapshot.data?.user.photo
            : null,
      ),
    );
  }
}

class ProfileIdentity extends StatelessWidget {
  const ProfileIdentity({
    super.key,
    required this.controller,
    required this.user,
    this.radius = 20,
    this.onTap,
  });
  final CompanionController controller;
  final UserSummary user;
  final double radius;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap ?? () => showCompanionProfile(context, controller, user.id),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProfileAvatar(controller: controller, user: user, radius: radius),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

class CompanionModuleNotice extends StatelessWidget {
  const CompanionModuleNotice({
    super.key,
    required this.controller,
    this.feature = CompanionFeature.profile,
  });
  final CompanionController controller;
  final CompanionFeature feature;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(height: 12),
        Text(controller.featureMessage(feature), textAlign: TextAlign.center),
        TextButton(
          onPressed: controller.loading ? null : controller.refresh,
          child: const Text('다시 불러오기'),
        ),
      ],
    ),
  );
}

class FeatureFrame extends StatelessWidget {
  const FeatureFrame({
    super.key,
    required this.controller,
    required this.title,
    this.onBack,
    this.requiresCompanion = false,
    this.feature = CompanionFeature.profile,
    required this.child,
  });
  final CompanionController controller;
  final String title;
  final VoidCallback? onBack;
  final bool requiresCompanion;
  final CompanionFeature feature;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (onBack != null)
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: '뒤로',
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: controller.loading || controller.busy
                  ? null
                  : controller.refresh,
              icon: const Icon(Icons.refresh),
              tooltip: '다시 불러오기',
            ),
          ],
        ),
      ),
      if (controller.loading || controller.busy)
        const LinearProgressIndicator(),
      if (controller.error != null)
        MaterialBanner(
          content: Text(controller.error!),
          actions: [
            TextButton(
              onPressed: controller.loading || controller.busy
                  ? null
                  : controller.refresh,
              child: const Text('다시 불러오기'),
            ),
          ],
        ),
      Expanded(
        child: controller.snapshot == null
            ? Center(
                child: controller.loading
                    ? const CircularProgressIndicator()
                    : const Text('정보를 불러오지 못했어요. 다시 불러와 주세요.'),
              )
            : requiresCompanion && !controller.featureReady(feature)
            ? Center(
                child: CompanionModuleNotice(
                  controller: controller,
                  feature: feature,
                ),
              )
            : child,
      ),
    ],
  );
}

class CompanionRatingPage extends StatefulWidget {
  const CompanionRatingPage({
    super.key,
    required this.controller,
    required this.onBack,
  });
  final CompanionController controller;
  final VoidCallback onBack;
  @override
  State<CompanionRatingPage> createState() => _CompanionRatingPageState();
}

class _CompanionRatingPageState extends State<CompanionRatingPage> {
  String? _rideId;
  final Map<String, Map<String, int>> _scores = {};
  final Map<String, Set<String>> _blocks = {};
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

  Future<void> _submit(RatingTask task) async {
    final scores = _scores[task.ride.id] ?? {};
    final inputs = task.pending
        .where((u) => scores.containsKey(u.id))
        .map(
          (u) => RatingInput(
            targetId: u.id,
            halfUnits: scores[u.id]!,
            block:
                widget.controller.featureReady(CompanionFeature.blocking) &&
                (_blocks[task.ride.id]?.contains(u.id) ?? false),
          ),
        )
        .toList();
    final ok = await widget.controller.perform(
      () => widget.controller.repository.submitRatings(task.ride.id, inputs),
    );
    if (!mounted || !ok) return;
    setState(() {
      for (final input in inputs) {
        scores.remove(input.targetId);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('평가를 보냈어요. 프로필 수치는 하루 1회 갱신돼요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final tasks = c.snapshot?.ratingTasks ?? [];
    final task =
        tasks.where((t) => t.ride.id == _rideId).firstOrNull ??
        tasks.firstOrNull;
    final enabled =
        !c.busy &&
        !c.loading &&
        task != null &&
        task.ride.ratingOpen(DateTime.now().toUtc());
    final scores = task == null
        ? <String, int>{}
        : _scores.putIfAbsent(task.ride.id, () => {});
    final blocks = task == null
        ? <String>{}
        : _blocks.putIfAbsent(task.ride.id, () => {});
    return FeatureFrame(
      controller: c,
      title: '함께 탄 사용자 평가',
      requiresCompanion: true,
      onBack: widget.onBack,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (tasks.isEmpty)
            const Text('평가할 운행이 없어요.')
          else ...[
            DropdownButton<String>(
              isExpanded: true,
              value: task!.ride.id,
              items: tasks
                  .map(
                    (t) => DropdownMenuItem(
                      value: t.ride.id,
                      child: Text(
                        '${localTime(t.ride.departureAt)} · ${t.ride.from} → ${t.ride.to}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: c.busy ? null : (id) => setState(() => _rideId = id),
            ),
            Text(
              '평가 기한 ${localTime(task.ride.ratingDeadline!)} · 노쇼는 평가 대상에서 제외돼요.',
            ),
            const SizedBox(height: 12),
            if (!task.ride.ratingOpen(DateTime.now().toUtc()))
              const Text('평가 기간이 종료됐어요.'),
            if (task.targets.isEmpty) const Text('함께 탑승한 평가 대상이 없어요.'),
            if (task.targets.isNotEmpty && task.pending.isEmpty)
              const Text('모든 평가를 제출했어요.'),
            for (final user in task.targets)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProfileIdentity(controller: c, user: user),
                      if (task.submittedUserIds.contains(user.id))
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('제출 완료 · 수정할 수 없어요.'),
                        )
                      else ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: List.generate(
                            10,
                            (i) => ChoiceChip(
                              label: Text(((i + 1) / 2).toStringAsFixed(1)),
                              selected: scores[user.id] == i + 1,
                              onSelected: enabled
                                  ? (_) =>
                                        setState(() => scores[user.id] = i + 1)
                                  : null,
                            ),
                          ),
                        ),
                        if (c.snapshot!.blockedIds.contains(user.id))
                          const Text('이미 차단한 사용자예요.')
                        else
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('이 사용자 차단하기'),
                            value: blocks.contains(user.id),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged:
                                enabled &&
                                    c.featureReady(CompanionFeature.blocking)
                                ? (v) => setState(() {
                                    if (v == true) {
                                      blocks.add(user.id);
                                    } else {
                                      blocks.remove(user.id);
                                    }
                                  })
                                : null,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  enabled && task.pending.any((u) => scores.containsKey(u.id))
                  ? () => _submit(task)
                  : null,
              child: const Text('선택한 평가 보내기'),
            ),
            const SizedBox(height: 8),
            const Text('0.5~5.0점 · 운행마다 한 사용자에게 1회 · 제출 후 수정 불가'),
          ],
        ],
      ),
    );
  }
}

class CompanionKeywordPage extends StatefulWidget {
  const CompanionKeywordPage({
    super.key,
    required this.controller,
    required this.onBack,
  });
  final CompanionController controller;
  final VoidCallback onBack;
  @override
  State<CompanionKeywordPage> createState() => _CompanionKeywordPageState();
}

class _CompanionKeywordPageState extends State<CompanionKeywordPage> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final submitted = _text.text;
    final ok = await widget.controller.perform(
      () => widget.controller.repository.addKeyword(submitted),
      feature: CompanionFeature.keywords,
    );
    if (mounted && ok && _text.text == submitted) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.snapshot;
    final enabled = !c.busy && !c.loading;
    return FeatureFrame(
      controller: c,
      title: '키워드 알림',
      requiresCompanion: true,
      feature: CompanionFeature.keywords,
      onBack: widget.onBack,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('출발지·도착지·조건에 키워드가 포함된 새 팟을 알려드려요.'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '키워드 등록 ${s?.keywords.length ?? 0}/5',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextField(
                    controller: _text,
                    enabled: enabled,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => enabled && (s?.keywords.length ?? 0) < 5
                        ? _add()
                        : null,
                    decoration: const InputDecoration(hintText: '예: 충주역, 기숙사'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: enabled && (s?.keywords.length ?? 0) < 5
                        ? _add
                        : null,
                    child: const Text('추가'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: (s?.keywords.isEmpty ?? true)
                  ? const Text('등록한 키워드가 없어요.')
                  : Column(
                      children: s!.keywords
                          .map(
                            (k) => Row(
                              children: [
                                Expanded(
                                  child: SwitchListTile(
                                    title: Text(k.text),
                                    subtitle: Text(
                                      k.enabled ? '사용 중' : '사용 중지',
                                    ),
                                    value: k.enabled,
                                    onChanged: enabled
                                        ? (value) => c.perform(
                                            () => c.repository
                                                .setKeywordEnabled(k.id, value),
                                            feature: CompanionFeature.keywords,
                                          )
                                        : null,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '키워드 삭제',
                                  icon: const Icon(Icons.close),
                                  onPressed: enabled
                                      ? () => c.perform(
                                          () =>
                                              c.repository.removeKeyword(k.id),
                                          feature: CompanionFeature.keywords,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
            ),
          ),
          Card(
            child: SwitchListTile(
              title: const Text('키워드 알림 전체 받기'),
              value: s?.keywordAlertsEnabled ?? false,
              onChanged: enabled
                  ? (v) => c.perform(
                      () => c.repository.setKeywordAlerts(v),
                      feature: CompanionFeature.keywords,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '사용 중인 키워드만 알림에 적용돼요. 전체 알림을 끄면 모두 중지돼요. 사용을 중지한 키워드도 최대 5개 제한에 포함돼요.',
          ),
        ],
      ),
    );
  }
}

class CompanionBlocksPage extends StatelessWidget {
  const CompanionBlocksPage({
    super.key,
    required this.controller,
    required this.onBack,
  });
  final CompanionController controller;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => FeatureFrame(
    controller: controller,
    title: '차단한 사용자',
    requiresCompanion: true,
    feature: CompanionFeature.blocking,
    onBack: onBack,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('차단한 사실은 상대에게 알려지지 않아요.'),
        const SizedBox(height: 12),
        if (controller.snapshot?.blockedUsers.isEmpty ?? true)
          const Text('차단한 사용자가 없어요.'),
        for (final user in controller.snapshot?.blockedUsers ?? <UserSummary>[])
          Card(
            child: ListTile(
              title: ProfileIdentity(controller: controller, user: user),
              trailing: TextButton(
                onPressed: controller.busy || controller.loading
                    ? null
                    : () => controller.perform(
                        () => controller.repository.unblock(user.id),
                        feature: CompanionFeature.blocking,
                      ),
                child: const Text('차단 해제'),
              ),
            ),
          ),
      ],
    ),
  );
}

class CompanionMyPage extends StatelessWidget {
  const CompanionMyPage({
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
  final Future<void> Function() onLogout;
  final VoidCallback? onAccount;
  @override
  Widget build(BuildContext context) {
    final s = controller.snapshot;
    return FeatureFrame(
      controller: controller,
      title: 'MY',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (s?.accountError != null)
            Text(s!.accountError!)
          else if (s?.account == null)
            const Text('로그인 계정의 프로필이 아직 준비되지 않았어요. 팀 계정 등록을 확인해 주세요.')
          else
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: ProfileAvatar(
                  controller: controller,
                  user: s!.account!,
                  radius: 26,
                ),
                title: Text(
                  s.account!.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text('내 프로필'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    showCompanionProfile(context, controller, s.account!.id),
              ),
            ),
          if (s?.profile != null && controller.companionReady)
            ProfileStatsCard(controller: controller, stats: s!.profile!)
          else
            CompanionModuleNotice(controller: controller),
          OutlinedButton.icon(
            onPressed:
                !controller.companionReady ||
                    controller.busy ||
                    controller.loading
                ? null
                : () => showProfilePhotoEditor(context, controller),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('프로필 사진 편집'),
          ),
          Card(
            child: Column(
              children: [
                if (onAccount != null)
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: const Text('계정 관리'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onAccount,
                  ),
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: const Text('운행 평가'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onRatings,
                ),
                ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: const Text('키워드 알림'),
                  subtitle: Text(
                    s?.featureReady(CompanionFeature.keywords) == true
                        ? (s!.keywords.isEmpty
                              ? '등록한 키워드가 없어요'
                              : s.keywords.map((k) => k.text).join(' · '))
                        : '키워드 정보를 확인해 주세요',
                  ),
                  onTap: onKeywords,
                ),
                ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('차단한 사용자'),
                  subtitle: Text(
                    s?.featureReady(CompanionFeature.blocking) == true
                        ? '${s!.blockedUsers.length}명'
                        : '차단 정보를 확인해 주세요',
                  ),
                  onTap: onBlocks,
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('알림 설정'),
                  onTap: onSettings,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: controller.busy ? null : onLogout,
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
  }
}

class ProfileStatsCard extends StatelessWidget {
  const ProfileStatsCard({
    super.key,
    required this.controller,
    required this.stats,
    this.openOnTap = true,
  });
  final CompanionController controller;
  final ProfileStats stats;
  final bool openOnTap;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (openOnTap)
            ProfileIdentity(
              controller: controller,
              user: stats.user,
              radius: 32,
            )
          else
            Column(
              children: [
                ProfileAvatar(
                  controller: controller,
                  user: stats.user,
                  radius: 44,
                  loadPhoto: false,
                ),
                const SizedBox(height: 12),
                Text(
                  stats.user.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          const Divider(height: 28),
          Row(
            children: [
              _Stat('별점', stats.ratingLabel),
              _Stat('누적 참여', '${stats.participationCount}회'),
              _Stat('노쇼', '${stats.noShowCount}회'),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        Text(label),
      ],
    ),
  );
}

class CompanionNoticesPage extends StatelessWidget {
  const CompanionNoticesPage({
    super.key,
    required this.controller,
    required this.onOpenRide,
    required this.onRatings,
  });
  final CompanionController controller;
  final Future<void> Function(String) onOpenRide;
  final VoidCallback onRatings;
  @override
  Widget build(BuildContext context) => FeatureFrame(
    controller: controller,
    title: '알림',
    requiresCompanion: true,
    feature: CompanionFeature.keywords,
    child: RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('함께 탄 사용자 평가하기'),
              onTap: onRatings,
            ),
          ),
          if (controller.snapshot?.notices.isEmpty ?? true)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('아직 도착한 키워드 알림이 없어요.'),
            ),
          for (final notice in controller.snapshot?.notices ?? <AppNotice>[])
            Card(
              child: ListTile(
                leading: Icon(
                  notice.readAt == null
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none,
                ),
                title: Text(notice.title),
                subtitle: Text(
                  '${notice.body}\n${localTime(notice.createdAt)}',
                ),
                onTap: controller.busy || controller.loading
                    ? null
                    : () async {
                        final ok = await controller.perform(
                          () => controller.repository.markNoticeRead(notice.id),
                          feature: CompanionFeature.keywords,
                        );
                        if (ok) await onOpenRide(notice.rideId);
                      },
              ),
            ),
        ],
      ),
    ),
  );
}

class CompanionSettingsPage extends StatelessWidget {
  const CompanionSettingsPage({
    super.key,
    required this.controller,
    required this.onBack,
    required this.enablePush,
  });
  final CompanionController controller;
  final VoidCallback onBack;
  final Future<void> Function() enablePush;
  @override
  Widget build(BuildContext context) => FeatureFrame(
    controller: controller,
    title: '알림 설정',
    requiresCompanion: true,
    feature: CompanionFeature.keywords,
    onBack: onBack,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: SwitchListTile(
            title: const Text('키워드 알림'),
            subtitle: const Text('새 팟의 앱 내 알림과 기기 푸시'),
            value: controller.snapshot?.keywordAlertsEnabled ?? false,
            onChanged: controller.busy || controller.loading
                ? null
                : (v) => controller.perform(
                    () => controller.repository.setKeywordAlerts(v),
                    feature: CompanionFeature.keywords,
                  ),
          ),
        ),
        FilledButton(
          onPressed: controller.busy || controller.loading
              ? null
              : () => controller.perform(
                  enablePush,
                  allowUserInteraction: true,
                  feature: CompanionFeature.keywords,
                ),
          child: const Text('이 기기에서 푸시 알림 활성화'),
        ),
      ],
    ),
  );
}

class CompanionApplicantsPage extends StatefulWidget {
  const CompanionApplicantsPage({
    super.key,
    required this.controller,
    required this.rideId,
    required this.onBack,
  });
  final CompanionController controller;
  final String rideId;
  final VoidCallback onBack;
  @override
  State<CompanionApplicantsPage> createState() =>
      _CompanionApplicantsPageState();
}

class _CompanionApplicantsPageState extends State<CompanionApplicantsPage> {
  late Future<List<UserSummary>> _future;
  Future<List<UserSummary>> _readApplicants() => widget.controller.repository
      .applicants(widget.rideId)
      .timeout(const Duration(seconds: 20));
  @override
  void initState() {
    super.initState();
    _future = _readApplicants();
  }

  @override
  Widget build(BuildContext context) => FeatureFrame(
    controller: widget.controller,
    title: '참여 신청자',
    onBack: widget.onBack,
    child: FutureBuilder<List<UserSummary>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.error is FeatureFailure
                      ? (snapshot.error as FeatureFailure).message
                      : '신청자 정보를 불러오지 못했어요.',
                ),
                TextButton(
                  onPressed: () => setState(() => _future = _readApplicants()),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          );
        }
        final users = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!widget.controller.featureReady(CompanionFeature.blocking))
              CompanionModuleNotice(
                controller: widget.controller,
                feature: CompanionFeature.blocking,
              ),
            if (users.isEmpty) const Text('대기 중인 신청자가 없어요.'),
            for (final user in users)
              Card(
                child: ListTile(
                  title: ProfileIdentity(
                    controller: widget.controller,
                    user: user,
                  ),
                  trailing:
                      widget.controller.featureReady(
                            CompanionFeature.blocking,
                          ) &&
                          widget.controller.snapshot!.blockedIds.contains(
                            user.id,
                          )
                      ? const Chip(
                          label: Text('차단한 사용자'),
                          avatar: Icon(Icons.block, size: 16),
                        )
                      : null,
                ),
              ),
            TextButton(
              onPressed: () => setState(() => _future = _readApplicants()),
              child: const Text('신청자 새로고침'),
            ),
          ],
        );
      },
    ),
  );
}

class CompanionProfileDialog extends StatefulWidget {
  const CompanionProfileDialog({
    super.key,
    required this.controller,
    required this.userId,
  });
  final CompanionController controller;
  final String userId;
  @override
  State<CompanionProfileDialog> createState() => _CompanionProfileDialogState();
}

class _CompanionProfileDialogState extends State<CompanionProfileDialog> {
  late Future<ProfileStats> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    // Re-check permission on every opening and retry; don't trust avatar cache.
    _future = widget.controller.repository
        .profile(widget.userId)
        .timeout(const Duration(seconds: 20));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('프로필'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: FutureBuilder<ProfileStats>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.error is FeatureFailure
                        ? (snapshot.error as FeatureFailure).message
                        : '프로필을 불러오지 못했어요.',
                  ),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('다시 시도'),
                  ),
                ],
              );
            }
            return ProfileStatsCard(
              controller: widget.controller,
              stats: snapshot.data!,
              openOnTap: false,
            );
          },
        ),
      ),
    ),
    actions: [
      if (widget.userId == widget.controller.repository.userId)
        TextButton(
          onPressed:
              !widget.controller.companionReady ||
                  widget.controller.busy ||
                  widget.controller.loading
              ? null
              : () async {
                  final saved = await showProfilePhotoEditor(
                    context,
                    widget.controller,
                  );
                  if (saved == true && mounted) setState(_load);
                },
          child: const Text('사진 편집'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
  );
}
