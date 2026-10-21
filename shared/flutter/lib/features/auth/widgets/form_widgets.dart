import 'package:flutter/material.dart';

import '../auth_colors.dart';

/// 입력칸 위의 작은 라벨.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AuthColors.textBody),
      ),
    );
  }
}

/// 시안의 둥근 테두리 입력칸.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.hint,
    this.suffixText,
    this.suffixIcon,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.hasError = false,
    this.maxLength,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String? hint;
  final String? suffixText;
  final Widget? suffixIcon;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool hasError;
  final int? maxLength;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return TextField(
      controller: controller,
      obscureText: obscure,
      obscuringCharacter: '●',
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      autocorrect: false,
      enableSuggestions: !obscure,
      maxLength: maxLength,
      autofillHints: autofillHints,
      style: TextStyle(
        fontSize: 17,
        color: AuthColors.textStrong,
        letterSpacing: obscure ? 2 : 0,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AuthColors.textHint, letterSpacing: 0),
        counterText: '',
        suffixText: suffixText,
        suffixStyle: const TextStyle(fontSize: 17, color: AuthColors.textHint),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        enabledBorder: border(hasError ? AuthColors.error : AuthColors.border),
        focusedBorder: border(hasError ? AuthColors.error : AuthColors.primary, 1.5),
      ),
    );
  }
}

/// 입력칸 아래 상태 문구 (초록/빨강/회색).
class HelperText extends StatelessWidget {
  const HelperText(this.text, {super.key, this.color = AuthColors.textSub});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 8),
      child: Text(text, style: TextStyle(fontSize: 13, color: color)),
    );
  }
}

/// "✓ 8자 이상" 같은 조건 표시.
class RuleCheck extends StatelessWidget {
  const RuleCheck({super.key, required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AuthColors.success : AuthColors.textHint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}

/// 연한 배경의 안내 상자.
class InfoBox extends StatelessWidget {
  const InfoBox({super.key, required this.icon, required this.text, this.highlight = true});

  final IconData icon;
  final String text;

  /// true: 연파랑 배경 + 파랑 글씨, false: 회색 배경 + 회색 글씨.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? AuthColors.primary : AuthColors.textSub;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: highlight ? AuthColors.primarySoft : AuthColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 19, color: fg)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14, height: 1.55, color: fg))),
        ],
      ),
    );
  }
}

/// 비밀번호 보기/숨기기 아이콘 버튼.
class ObscureToggle extends StatelessWidget {
  const ObscureToggle({super.key, required this.obscured, required this.onTap});

  final bool obscured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: AuthColors.textHint,
      ),
    );
  }
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
