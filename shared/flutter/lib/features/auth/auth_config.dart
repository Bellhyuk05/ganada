/// F-01 회원가입 · 로그인 설정값.
class AuthConfig {
  /// 입력칸에 붙는 학교 메일 도메인 (재학생 메일: 학번@a.ut.ac.kr).
  static const String schoolEmailDomain = 'a.ut.ac.kr';

  /// 가입을 허용하는 도메인 전체 (재학생 a.ut.ac.kr, 교직원 ut.ac.kr).
  /// 바꾸면 supabase/migrations/202610110000_f01_signup.sql 의 정규식도 함께 바꿔야 한다.
  static const List<String> allowedEmailDomains = ['a.ut.ac.kr', 'ut.ac.kr'];

  static const String schoolName = '한국교통대학교';

  /// 약관 버전. 약관 내용이 바뀌면 올려서 재동의를 받는다.
  static const String termsVersion = '2026-10-11';

  /// 인증 코드 유효 시간(초). Supabase 대시보드의 Email OTP Expiration 과 같게 맞춘다.
  static const int codeValidSeconds = 600;

  /// 인증 코드 자릿수. Supabase 대시보드의 Email OTP Length 와 같게 맞춘다.
  static const int codeLength = 6;

  /// 코드 재발송 대기 시간(초).
  /// Supabase 대시보드 Authentication → Emails → SMTP Settings 의 "Minimum interval per user" 와 같게 맞춘다.
  static const int resendCooldownSeconds = 20;

  static const int nicknameMinLength = 2;
  static const int nicknameMaxLength = 10;
  static const int passwordMinLength = 8;
}
