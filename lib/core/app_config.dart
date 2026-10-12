/// 팀 공유본 lib/core/app_config.dart 와 같은 키 이름을 쓴다.
/// 실행: flutter run --dart-define-from-file=config/development.json
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
}
