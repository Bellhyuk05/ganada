import 'dart:async';

import 'package:flutter/material.dart';

import '../auth_colors.dart';
import '../auth_config.dart';
import '../auth_service.dart';
import '../widgets/form_widgets.dart';
import '../widgets/step_scaffold.dart';
import 'terms.dart';

enum _NickState { empty, invalid, checking, available, taken, error }

/// 3단계: 닉네임 · 비밀번호 · 약관 동의.
/// 인증 코드 확인으로 이미 로그인된 상태에서 열린다.
class ProfileStep extends StatefulWidget {
  const ProfileStep({super.key, required this.onCompleted});

  /// 프로필 저장이 끝나면 호출. 게이트가 다시 확인해서 앱 본 화면으로 넘긴다.
  final VoidCallback onCompleted;

  @override
  State<ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<ProfileStep> {
  final _nickname = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  Timer? _debounce;
  _NickState _nickState = _NickState.empty;
  String _invalidReason = '';
  bool _obscure = true;
  bool _agreeService = false;
  bool _agreePrivacy = false;
  bool _loading = false;

  static final _nickPattern = RegExp(r'^[가-힣a-zA-Z0-9]+$');

  @override
  void dispose() {
    _debounce?.cancel();
    _nickname.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _lengthOk => _password.text.length >= AuthConfig.passwordMinLength;
  bool get _mixOk => passwordHasLetterAndDigit(_password.text);
  bool get _confirmOk => _confirm.text.isNotEmpty && _confirm.text == _password.text;
  bool get _allAgreed => _agreeService && _agreePrivacy;
  bool get _canSubmit =>
      _nickState == _NickState.available && _lengthOk && _mixOk && _confirmOk && _allAgreed;

  void _onNicknameChanged(String value) {
    _debounce?.cancel();
    final v = value.trim();
    if (v.isEmpty) return setState(() => _nickState = _NickState.empty);
    if (v.length < AuthConfig.nicknameMinLength || v.length > AuthConfig.nicknameMaxLength) {
      _invalidReason = '${AuthConfig.nicknameMinLength}~${AuthConfig.nicknameMaxLength}자로 입력해 주세요.';
      return setState(() => _nickState = _NickState.invalid);
    }
    if (!_nickPattern.hasMatch(v)) {
      _invalidReason = '한글·영문·숫자만 쓸 수 있어요.';
      return setState(() => _nickState = _NickState.invalid);
    }
    setState(() => _nickState = _NickState.checking);
    _debounce = Timer(const Duration(milliseconds: 400), () => _checkNickname(v));
  }

  Future<void> _checkNickname(String v) async {
    try {
      final ok = await AuthService.instance.isNicknameAvailable(v);
      if (!mounted || _nickname.text.trim() != v) return;
      setState(() => _nickState = ok ? _NickState.available : _NickState.taken);
    } catch (_) {
      if (mounted) setState(() => _nickState = _NickState.error);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await AuthService.instance.completeSignup(nickname: _nickname.text, password: _password.text);
      widget.onCompleted();
    } catch (e) {
      if (!mounted) return;
      if (authErrorMessage(e).contains('닉네임')) setState(() => _nickState = _NickState.taken);
      showMessage(context, authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _back() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('가입을 잠시 멈출까요?'),
        content: const Text('같은 학교 메일로 다시 인증하면 이 단계부터 이어서 할 수 있어요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('나가기')),
        ],
      ),
    );
    if (ok == true) await AuthService.instance.signOut();
  }

  Widget _nickHelper() {
    return switch (_nickState) {
      _NickState.available => const HelperText('사용할 수 있는 닉네임이에요', color: AuthColors.success),
      _NickState.taken => const HelperText('이미 사용 중인 닉네임이에요', color: AuthColors.error),
      _NickState.invalid => HelperText(_invalidReason, color: AuthColors.error),
      _NickState.checking => const HelperText('확인하는 중...'),
      _NickState.error => const HelperText('확인하지 못했어요. 인터넷 연결을 확인해 주세요.', color: AuthColors.error),
      _NickState.empty =>
        const HelperText('${AuthConfig.nicknameMinLength}~${AuthConfig.nicknameMaxLength}자, 한글·영문·숫자'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final nickBad = _nickState == _NickState.taken || _nickState == _NickState.invalid;

    return StepScaffold(
      step: 3,
      title: '프로필을 만들어 주세요',
      subtitle: const Text('다른 학생들에게는 닉네임만 보여요.'),
      onBack: _back,
      buttonLabel: '가입 완료',
      loading: _loading,
      onPressed: _canSubmit ? _submit : null,
      children: [
        const FieldLabel('닉네임'),
        AppTextField(
          controller: _nickname,
          hint: '예) 새벽기차',
          maxLength: AuthConfig.nicknameMaxLength,
          textInputAction: TextInputAction.next,
          hasError: nickBad,
          onChanged: _onNicknameChanged,
          suffixIcon: switch (_nickState) {
            _NickState.available => const Icon(Icons.check, color: AuthColors.success),
            _NickState.checking => const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            _ => null,
          },
        ),
        _nickHelper(),
        const SizedBox(height: 24),
        const FieldLabel('비밀번호'),
        AppTextField(
          controller: _password,
          obscure: _obscure,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          suffixIcon: ObscureToggle(obscured: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
          onChanged: (_) => setState(() {}),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 10),
          child: Row(
            children: [
              RuleCheck(label: '${AuthConfig.passwordMinLength}자 이상', ok: _lengthOk),
              const SizedBox(width: 14),
              RuleCheck(label: '영문·숫자 포함', ok: _mixOk),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const FieldLabel('비밀번호 확인'),
        AppTextField(
          controller: _confirm,
          obscure: _obscure,
          textInputAction: TextInputAction.done,
          hasError: _confirm.text.isNotEmpty && !_confirmOk,
          suffixIcon: _confirmOk ? const Icon(Icons.check, color: AuthColors.success) : null,
          onChanged: (_) => setState(() {}),
        ),
        if (_confirm.text.isNotEmpty && !_confirmOk)
          const HelperText('비밀번호가 일치하지 않아요.', color: AuthColors.error),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: AuthColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _AgreeRow(
                label: const Text(
                  '약관 전체 동의',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AuthColors.textStrong),
                ),
                checked: _allAgreed,
                onTap: () => setState(() {
                  final next = !_allAgreed;
                  _agreeService = next;
                  _agreePrivacy = next;
                }),
              ),
              const Divider(height: 1, color: AuthColors.border),
              _AgreeRow(
                label: const _RequiredLabel('서비스 이용약관'),
                checked: _agreeService,
                onTap: () => setState(() => _agreeService = !_agreeService),
                onDetail: () => showTermsSheet(context, TermsType.service),
              ),
              _AgreeRow(
                label: const _RequiredLabel('개인정보 수집·이용'),
                checked: _agreePrivacy,
                onTap: () => setState(() => _agreePrivacy = !_agreePrivacy),
                onDetail: () => showTermsSheet(context, TermsType.privacy),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

bool passwordHasLetterAndDigit(String value) =>
    RegExp(r'[A-Za-z]').hasMatch(value) && RegExp(r'\d').hasMatch(value);

class _RequiredLabel extends StatelessWidget {
  const _RequiredLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(
            text: '[필수]  ',
            style: TextStyle(color: AuthColors.primary, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: text),
        ],
      ),
      style: const TextStyle(fontSize: 15, color: AuthColors.textBody),
    );
  }
}

class _AgreeRow extends StatelessWidget {
  const _AgreeRow({required this.label, required this.checked, required this.onTap, this.onDetail});

  final Widget label;
  final bool checked;
  final VoidCallback onTap;
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? AuthColors.primary : Colors.white,
                border: Border.all(color: checked ? AuthColors.primary : AuthColors.border, width: 1.5),
              ),
              child: const Icon(Icons.check, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(child: label),
            if (onDetail != null)
              IconButton(
                onPressed: onDetail,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right, color: AuthColors.textHint),
              ),
          ],
        ),
      ),
    );
  }
}
