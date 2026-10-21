import 'dart:async';

import 'package:flutter/material.dart';

import '../auth_colors.dart';
import '../auth_config.dart';
import '../auth_service.dart';
import '../widgets/code_input.dart';
import '../widgets/form_widgets.dart';
import '../widgets/step_scaffold.dart';

/// 2단계: 메일로 받은 6자리 코드 입력.
/// 코드가 맞으면 로그인 세션이 생기고, 게이트가 3단계(프로필)로 화면을 바꾼다.
class CodeStep extends StatefulWidget {
  const CodeStep({super.key, required this.email});

  final String email;

  @override
  State<CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends State<CodeStep> {
  final _code = TextEditingController();
  Timer? _timer;
  late DateTime _expiresAt;
  late DateTime _resendAt;
  bool _loading = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _resetTimers();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _resetTimers() {
    final now = DateTime.now();
    _expiresAt = now.add(const Duration(seconds: AuthConfig.codeValidSeconds));
    _resendAt = now.add(const Duration(seconds: AuthConfig.resendCooldownSeconds));
  }

  Duration get _remaining {
    final d = _expiresAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  bool get _expired => _remaining == Duration.zero;
  int get _resendWait => _resendAt.difference(DateTime.now()).inSeconds.clamp(0, 999);
  bool get _complete => _code.text.length == AuthConfig.codeLength;

  String _format(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _verify() async {
    if (_loading || !_complete) return;
    if (_expired) return showMessage(context, '코드가 만료됐어요. 코드를 다시 받아 주세요.');
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await AuthService.instance.verifySignupCode(email: widget.email, code: _code.text);
      // 성공하면 로그인 상태가 바뀌어 이 화면은 자동으로 사라진다.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = true);
      showMessage(context, authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      await AuthService.instance.sendSignupCode(widget.email);
      if (!mounted) return;
      setState(() {
        _resetTimers();
        _code.clear();
        _error = false;
      });
      showMessage(context, '새 코드를 보냈어요.');
    } catch (e) {
      if (mounted) showMessage(context, authErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _resendWait == 0;

    return StepScaffold(
      step: 2,
      title: '메일로 받은 코드를\n입력해 주세요',
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: widget.email,
              style: const TextStyle(fontWeight: FontWeight.w700, color: AuthColors.textStrong),
            ),
            const TextSpan(text: '로\n${AuthConfig.codeLength}자리 코드를 보냈어요.'),
          ],
        ),
      ),
      buttonLabel: '확인',
      loading: _loading,
      onPressed: _complete ? _verify : null,
      children: [
        CodeInput(
          controller: _code,
          length: AuthConfig.codeLength,
          hasError: _error,
          onChanged: (_) {
            if (_error) setState(() => _error = false);
            setState(() {});
          },
          onCompleted: (_) => _verify(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text('남은 시간 ', style: TextStyle(fontSize: 14, color: AuthColors.textSub)),
            Text(
              _format(_remaining),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _expired ? AuthColors.error : AuthColors.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: canResend ? _resend : null,
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
              child: Text(
                canResend ? '코드 다시 받기' : '다시 받기 ($_resendWait초)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: canResend ? AuthColors.textBody : AuthColors.textHint,
                  decoration: canResend ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const InfoBox(
          icon: Icons.mail_outline,
          text: '메일이 보이지 않으면 스팸함도 확인해 주세요.',
          highlight: false,
        ),
      ],
    );
  }
}
