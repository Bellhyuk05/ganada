import 'package:flutter/material.dart';

import '../auth_colors.dart';
import '../auth_config.dart';
import '../auth_service.dart';
import '../widgets/code_input.dart';
import '../widgets/form_widgets.dart';
import '../widgets/primary_button.dart';
import 'profile_step.dart' show passwordHasLetterAndDigit;

/// 비밀번호 재설정: 학교 메일로 코드 받기 → 코드 + 새 비밀번호 입력.
/// 링크 방식은 앱으로 돌아오는 딥링크 설정이 필요해서 코드 방식을 쓴다.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.initialLocalPart = ''});

  final String initialLocalPart;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialLocalPart);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _fullEmail => AuthService.instance.schoolEmail(_email.text);
  bool get _passwordOk =>
      _password.text.length >= AuthConfig.passwordMinLength && passwordHasLetterAndDigit(_password.text);
  bool get _canReset => _code.text.length == AuthConfig.codeLength && _passwordOk;

  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await AuthService.instance.sendPasswordResetCode(_fullEmail);
      if (mounted) setState(() => _codeSent = true);
    } catch (e) {
      if (mounted) showMessage(context, authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await AuthService.instance.resetPassword(email: _fullEmail, code: _code.text, newPassword: _password.text);
      // 성공하면 로그인 상태가 되어 SessionGate 가 화면을 바꾼다.
    } catch (e) {
      if (mounted) showMessage(context, authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 30, color: AuthColors.textStrong),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '비밀번호를\n다시 만들어요',
                      style: TextStyle(fontSize: 26, height: 1.35, fontWeight: FontWeight.w800, color: AuthColors.textStrong),
                    ),
                    const SizedBox(height: 36),
                    const FieldLabel('학교 이메일'),
                    AppTextField(
                      controller: _email,
                      hint: '아이디',
                      suffixText: '@${AuthConfig.schoolEmailDomain}',
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() => _codeSent = false),
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: 28),
                      const FieldLabel('메일로 받은 코드'),
                      CodeInput(
                        controller: _code,
                        length: AuthConfig.codeLength,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 28),
                      const FieldLabel('새 비밀번호'),
                      AppTextField(
                        controller: _password,
                        obscure: _obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        suffixIcon: ObscureToggle(obscured: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
                        onChanged: (_) => setState(() {}),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 2, top: 10),
                        child: Row(
                          children: [
                            RuleCheck(
                              label: '${AuthConfig.passwordMinLength}자 이상',
                              ok: _password.text.length >= AuthConfig.passwordMinLength,
                            ),
                            const SizedBox(width: 14),
                            RuleCheck(label: '영문·숫자 포함', ok: passwordHasLetterAndDigit(_password.text)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const InfoBox(
                        icon: Icons.mail_outline,
                        text: '가입된 메일이면 코드가 도착해요. 스팸함도 확인해 주세요.',
                        highlight: false,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: _codeSent
                  ? PrimaryButton(label: '비밀번호 바꾸기', loading: _loading, onPressed: _canReset ? _reset : null)
                  : PrimaryButton(
                      label: '재설정 코드 받기',
                      loading: _loading,
                      onPressed: _email.text.trim().isEmpty ? null : _sendCode,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
