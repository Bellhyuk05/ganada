import 'package:flutter/material.dart';

import '../auth_colors.dart';
import '../auth_config.dart';
import '../auth_service.dart';
import '../widgets/form_widgets.dart';
import '../widgets/step_scaffold.dart';
import 'code_step.dart';
import 'login_screen.dart';

/// 1단계: 학교 이메일 입력 → 6자리 인증 코드 발송.
class EmailStep extends StatefulWidget {
  const EmailStep({super.key});

  @override
  State<EmailStep> createState() => _EmailStepState();
}

class _EmailStepState extends State<EmailStep> {
  final _email = TextEditingController();
  bool _loading = false;

  static final _localPartPattern = RegExp(r'^[a-zA-Z0-9._-]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String get _local => _email.text.trim();
  bool get _emailOk => _localPartPattern.hasMatch(_local);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = AuthService.instance.schoolEmail(_local);
    setState(() => _loading = true);
    try {
      await AuthService.instance.sendSignupCode(email);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => CodeStep(email: email)));
    } catch (e) {
      if (!mounted) return;
      if (isResendTooSoon(e)) {
        // 뒤로 갔다가 바로 다시 누른 경우: 방금 보낸 코드가 아직 유효하므로 그대로 입력 화면으로.
        Navigator.push(context, MaterialPageRoute(builder: (_) => CodeStep(email: email)));
        showMessage(context, '방금 보낸 코드를 입력해 주세요.');
      } else {
        showMessage(context, authErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailError = _local.isNotEmpty && !_emailOk;

    return StepScaffold(
      step: 1,
      title: '학교 이메일로\n시작해 주세요',
      subtitle: const Text('같이타는 ${AuthConfig.schoolName} 학생만 이용할 수 있어요.'),
      buttonLabel: '인증 코드 받기',
      loading: _loading,
      onPressed: _emailOk ? _submit : null,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('이미 계정이 있나요?', style: TextStyle(fontSize: 14, color: AuthColors.textSub)),
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
            child: const Text(
              '로그인',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AuthColors.primary),
            ),
          ),
        ],
      ),
      children: [
        const FieldLabel('학교 이메일'),
        AppTextField(
          controller: _email,
          hint: '아이디',
          suffixText: '@${AuthConfig.schoolEmailDomain}',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.username],
          autofocus: true,
          hasError: emailError,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _emailOk ? _submit() : null,
        ),
        if (emailError) const HelperText('@ 앞부분만 입력해 주세요. (영문·숫자·._-)', color: AuthColors.error),
        const SizedBox(height: 16),
        const InfoBox(
          icon: Icons.school_outlined,
          text: '인증 메일로 재학생인지만 확인해요.\n실명과 학번은 받지 않아요.',
        ),
      ],
    );
  }
}
