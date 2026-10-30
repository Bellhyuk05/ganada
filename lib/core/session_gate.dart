import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/companion/repositories.dart';
import '../features/companion/supabase_repository.dart';
import '../ui/gachita_theme.dart';

/// Existing Supabase Auth accounts only. Signup/school verification belong to F-01.
class SessionGate extends StatelessWidget {
  const SessionGate({
    super.key,
    required this.builder,
    this.authenticationBuilder,
  });
  final Widget Function(CompanionRepository repository) builder;
  final WidgetBuilder? authenticationBuilder;
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: Supabase.instance.client.auth.onAuthStateChange,
    builder: (context, snapshot) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '같이타(GachiTa)',
          theme: GachiTaTheme.data,
          home: authenticationBuilder == null
              ? const _DevelopmentLogin()
              : Builder(builder: authenticationBuilder!),
        );
      }
      return KeyedSubtree(
        key: ValueKey(user.id),
        child: builder(SupabaseCompanionRepository(Supabase.instance.client)),
      );
    },
  );
}

class _DevelopmentLogin extends StatefulWidget {
  const _DevelopmentLogin();
  @override
  State<_DevelopmentLogin> createState() => _DevelopmentLoginState();
}

class _DevelopmentLoginState extends State<_DevelopmentLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = '로그인하지 못했어요. 계정 정보와 연결 상태를 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(
                Icons.local_taxi_rounded,
                size: 54,
                color: GachiTaTheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                '같이타',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: GachiTaTheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '함께 이동할 사람을 만나 보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: GachiTaTheme.muted),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: '이메일',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onSubmitted: (_) => _login(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _login,
                child: Text(_busy ? '로그인 중…' : '로그인'),
              ),
              const SizedBox(height: 20),
              const Text(
                '준비된 계정으로 로그인할 수 있어요.\n회원가입과 학교 인증은 준비 중이에요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: GachiTaTheme.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
