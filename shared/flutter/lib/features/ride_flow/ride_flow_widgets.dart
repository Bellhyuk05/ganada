import 'package:flutter/material.dart';

import '../../ui/gachita_theme.dart';
import '../companion/models.dart';
import 'ride_flow_repository.dart';

const rideFlowSuccess = Color(0xFF1DB36B);

String rideFlowTime(DateTime value) {
  final t = value.toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String rideFlowError(Object error) => error is FeatureFailure
    ? error.message
    : '연결 상태를 확인하고 다시 시도해 주세요.';

/// Confirmation for actions that cannot be undone (kick, leave, cancel, no-show).
Future<bool> confirmRideAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: GachiTaTheme.danger,
                  minimumSize: const Size(64, 44),
                )
              : FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

class RideFlowAvatar extends StatelessWidget {
  const RideFlowAvatar({super.key, required this.name, this.radius = 18});
  final String name;
  final double radius;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: GachiTaTheme.primaryLight,
    child: Text(
      name.isEmpty ? '?' : name.characters.first,
      style: TextStyle(
        fontSize: radius * 0.8,
        fontWeight: FontWeight.w700,
        color: GachiTaTheme.primary,
      ),
    ),
  );
}

class RideFlowTag extends StatelessWidget {
  const RideFlowTag({super.key, required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

/// Boarding state of one participant once the departure time has come.
class RideFlowMemberStatus extends StatelessWidget {
  const RideFlowMemberStatus({super.key, required this.member});
  final RideFlowMember member;
  @override
  Widget build(BuildContext context) {
    if (member.noShow) {
      return const RideFlowTag(label: '참여 안 함', color: GachiTaTheme.danger);
    }
    if (member.boardedAt != null) {
      return const RideFlowTag(label: '탑승', color: rideFlowSuccess);
    }
    return const RideFlowTag(label: '대기 중', color: GachiTaTheme.muted);
  }
}

class RideFlowSectionTitle extends StatelessWidget {
  const RideFlowSectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: GachiTaTheme.ink,
      ),
    ),
  );
}

class RideFlowNote extends StatelessWidget {
  const RideFlowNote({
    super.key,
    required this.text,
    this.color = GachiTaTheme.muted,
    this.icon = Icons.info_outline,
  });
  final String text;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: color, height: 1.35),
        ),
      ),
    ],
  );
}
