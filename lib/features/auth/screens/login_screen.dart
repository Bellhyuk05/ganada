import 'package:flutter/material.dart';

import '../auth_colors.dart';
import '../auth_config.dart';
import '../auth_service.dart';
import '../widgets/form_widgets.dart';
import '../widgets/primary_button.dart';
import 'reset_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String get _fullEmail => AuthService.instance.schoolEmail(_email.text);
  bool get _canSubmit => _email.text.trim().isNotEmpty && _password.text.isNotEmpty;

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await AuthService.instance.signIn(email: _fullEmail, password: _password.text);
      // 로그인되면 SessionGate 가 앱 본 화면(또는 3단계)으로 바꾼다.
    } catch (e) {
      if (mounted) showMessage(context, authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      '다시 만나서\n반가워요',
                      style: TextStyle(fontSize: 26, height: 1.35, fontWeight: FontWeight.w800, color: AuthColors.textStrong),
                    ),
                    const SizedBox(height: 36),
                    const FieldLabel('학교 이메일'),
                    AppTextField(
                      controller: _email,
                      hint: '아이디',
                      suffixText: '@${AuthConfig.schoolEmailDomain}',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 24),
                    const FieldLabel('비밀번호'),
                    AppTextField(
                      controller: _password,
                      obscure: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      suffixIcon: ObscureToggle(obscured: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _canSubmit ? _login() : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ResetPasswordScreen(initialLocalPart: _email.text.trim())),
                        ),
                        child: const Text(
                          '비밀번호를 잊으셨나요?',
                          style: TextStyle(fontSize: 14, color: AuthColors.textSub, decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: PrimaryButton(label: '로그인', loading: _loading, onPressed: _canSubmit ? _login : null),
            ),
          ],
        ),
      ),
    );
  }
}
