import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_config.dart';
import 'features/auth/auth_colors.dart';
import 'features/auth/auth_service.dart';
import 'features/auth/signup_flow.dart';

/// F-01 단독 테스트용 실행 파일.
/// 팀 공유본에 합칠 때는 lib/features/auth 폴더만 옮기고, 연결 방법은 docs/F01_팀연동가이드.md 를 따른다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.supabaseUrl.isEmpty || AppConfig.supabaseKey.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Supabase 연결 설정이 필요합니다.\nconfig/development.json 을 채우고\n--dart-define-from-file 로 실행하세요.'),
            ),
          ),
        ),
      ),
    );
    return;
  }
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
  runApp(const _DevSessionGate());
}

/// 팀 코드의 SessionGate 와 같은 구조: 로그아웃이면 가입 화면, 로그인이면 (가입 완료 확인 후) 앱.
class _DevSessionGate extends StatelessWidget {
  const _DevSessionGate();

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, _) {
          final user = Supabase.instance.client.auth.currentUser;
          if (user == null) {
            return MaterialApp(
              title: '같이타',
              debugShowCheckedModeBanner: false,
              theme: buildAuthTheme(),
              home: const SignupFlow(),
            );
          }
          return KeyedSubtree(
            key: ValueKey(user.id),
            child: SignupCompletionGate(
              child: MaterialApp(
                title: '같이타',
                debugShowCheckedModeBanner: false,
                theme: buildAuthTheme(),
                home: _DevHome(email: user.email ?? ''),
              ),
            ),
          );
        },
      );
}

class _DevHome extends StatelessWidget {
  const _DevHome({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('같이타', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [TextButton(onPressed: AuthService.instance.signOut, child: const Text('로그아웃'))],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_taxi_outlined, size: 56, color: AuthColors.primary),
            const SizedBox(height: 16),
            const Text('가입 완료!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(email, style: const TextStyle(color: AuthColors.textSub)),
            const SizedBox(height: 4),
            const Text('(팀 공유본에서는 이 자리에 GachiTaApp 이 들어가요)', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
