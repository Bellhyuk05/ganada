import 'package:flutter/material.dart';

import '../auth_colors.dart';
import 'primary_button.dart';

/// 회원가입 단계 화면 공통 틀: 뒤로가기 · n/3 · 진행 막대 · 제목 · 하단 버튼.
class StepScaffold extends StatelessWidget {
  const StepScaffold({
    super.key,
    required this.step,
    required this.title,
    this.subtitle,
    required this.children,
    required this.buttonLabel,
    required this.onPressed,
    this.loading = false,
    this.onBack,
    this.footer,
    this.totalSteps = 3,
  });

  final int step;
  final int totalSteps;
  final String title;
  final Widget? subtitle;
  final List<Widget> children;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool loading;
  final VoidCallback? onBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
              child: Row(
                children: [
                  if (onBack != null || Navigator.canPop(context))
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 30, color: AuthColors.textStrong),
                      onPressed: onBack ?? () => Navigator.maybePop(context),
                    )
                  else
                    const SizedBox(height: 48),
                  const Spacer(),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$step',
                          style: const TextStyle(color: AuthColors.primary, fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: ' / $totalSteps',
                          style: const TextStyle(color: AuthColors.textHint, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Row(
                children: [
                  for (var i = 1; i <= totalSteps; i++) ...[
                    if (i > 1) const SizedBox(width: 6),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 3,
                        decoration: BoxDecoration(
                          color: i <= step ? AuthColors.primary : AuthColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                        color: AuthColors.textStrong,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 10),
                      DefaultTextStyle.merge(
                        style: const TextStyle(fontSize: 15, height: 1.5, color: AuthColors.textSub),
                        child: subtitle!,
                      ),
                    ],
                    const SizedBox(height: 32),
                    ...children,
                  ],
                ),
              ),
            ),
            if (footer != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: footer),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: PrimaryButton(label: buttonLabel, onPressed: onPressed, loading: loading),
            ),
          ],
        ),
      ),
    );
  }
}
