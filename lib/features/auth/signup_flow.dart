import 'package:flutter/material.dart';

import 'auth_colors.dart';
import 'auth_service.dart';
import 'screens/email_step.dart';
import 'screens/profile_step.dart';
import 'widgets/primary_button.dart';

/// 로그아웃 상태에서 보여 줄 F-01 첫 화면.
/// 팀 코드의 `TeamFeatureBindings(authenticationBuilder: (_) => const SignupFlow())` 에 연결한다.
class SignupFlow extends StatelessWidget {
  const SignupFlow({super.key});

  @override
  Widget build(BuildContext context) => Theme(data: buildAuthTheme(), child: const EmailStep());
}

/// 로그인은 됐지만 3단계(닉네임·비밀번호·약관)를 끝내지 않은 사용자를 붙잡아 두는 게이트.
///
/// 인증 코드를 확인하는 순간 Supabase 세션이 생겨 SessionGate 가 앱 본 화면으로 넘어가 버리므로,
/// SessionGate 의 로그인된 쪽을 이 위젯으로 감싼다.
///   builder: (repository) => SignupCompletionGate(child: GachiTaApp(...))
class SignupCompletionGate extends StatefulWidget {
  const SignupCompletionGate({super.key, required this.child});

  final Widget child;

  @override
  State<SignupCompletionGate> createState() => _SignupCompletionGateState();
}

class _SignupCompletionGateState extends State<SignupCompletionGate> {
  late Future<bool> _completed;

  @override
  void initState() {
    super.initState();
    _completed = AuthService.instance.isSignupCompleted();
  }

  void _recheck() => setState(() => _completed = AuthService.instance.isSignupCompleted());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _completed,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const _AuthApp(home: _Splash());
        if (snap.hasError) {
          return _AuthApp(
            home: _Message(
              text: '가입 정보를 확인하지 못했어요.\n${authErrorMessage(snap.error!)}',
              primaryLabel: '다시 시도',
              onPrimary: _recheck,
            ),
          );
        }
        if (snap.data != true) return _AuthApp(home: ProfileStep(onCompleted: _recheck));
        return widget.child;
      },
    );
  }
}

class _AuthApp extends StatelessWidget {
  const _AuthApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '같이타',
      debugShowCheckedModeBanner: false,
      theme: buildAuthTheme(),
      home: home,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          '같이타',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AuthColors.textStrong),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.primaryLabel, required this.onPrimary});

  final String text;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.6, color: AuthColors.textBody),
                  ),
                ),
              ),
              PrimaryButton(label: primaryLabel, onPressed: onPrimary),
              TextButton(onPressed: AuthService.instance.signOut, child: const Text('로그아웃')),
            ],
          ),
        ),
      ),
    );
  }
}
