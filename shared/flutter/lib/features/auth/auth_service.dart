import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_config.dart';

/// F-01 Supabase 호출 모음.
///
/// 가입 흐름
///   1단계 signInWithOtp  → 학교 메일로 6자리 코드 발송 (처음이면 계정 생성)
///   2단계 verifyOTP      → 코드 확인, 로그인 세션 생성
///   3단계 updateUser     → 비밀번호 설정
///         f01_complete_signup (RPC) → profiles 행에 닉네임 · 약관 동의 저장
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;
  GoTrueClient get _auth => _client.auth;

  String schoolEmail(String localPart) => '${localPart.trim().toLowerCase()}@${AuthConfig.schoolEmailDomain}';

  bool isSchoolEmail(String email) {
    final lower = email.toLowerCase();
    return AuthConfig.allowedEmailDomains.any((d) => lower.endsWith('@$d'));
  }

  // ── 1 · 2단계: 인증 코드 ─────────────────────────────────

  Future<void> sendSignupCode(String email) => _auth.signInWithOtp(email: email, shouldCreateUser: true);

  /// 성공하면 세션이 생기고, SessionGate → SignupCompletionGate 가 3단계를 띄운다.
  Future<void> verifySignupCode({required String email, required String code}) =>
      _auth.verifyOTP(email: email, token: code, type: OtpType.email);

  // ── 3단계: 프로필 ────────────────────────────────────────

  Future<bool> isNicknameAvailable(String nickname) async {
    final result = await _client.rpc('f01_nickname_available', params: {'p_nickname': nickname.trim()});
    return result == true;
  }

  Future<bool> isSignupCompleted() async {
    final result = await _client.rpc('f01_signup_completed');
    return result == true;
  }

  /// 비밀번호를 먼저 설정하고 프로필을 만든다.
  /// (닉네임 중복으로 프로필 저장이 실패해도 비밀번호는 다시 설정하면 되므로 안전한 순서)
  Future<void> completeSignup({required String nickname, required String password}) async {
    await _auth.updateUser(UserAttributes(password: password));
    await _client.rpc('f01_complete_signup', params: {
      'p_nickname': nickname.trim(),
      'p_terms_version': AuthConfig.termsVersion,
    });
  }

  // ── 로그인 · 비밀번호 재설정 ─────────────────────────────

  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithPassword(email: email, password: password);

  Future<void> sendPasswordResetCode(String email) => _auth.resetPasswordForEmail(email);

  /// 코드 확인과 새 비밀번호 저장을 한 번에 한다.
  /// verifyOTP 가 끝나는 순간 로그인되어 화면이 바뀌므로 두 단계로 나누지 않는다.
  Future<void> resetPassword({required String email, required String code, required String newPassword}) async {
    await _auth.verifyOTP(email: email, token: code, type: OtpType.recovery);
    await _auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() => _auth.signOut();
}

/// 같은 메일로 너무 빨리 다시 요청해서 서버가 거절한 경우.
/// (직전에 보낸 코드는 아직 유효하므로 코드 입력 화면으로 보내면 된다)
bool isResendTooSoon(Object e) {
  if (e is! AuthException) return false;
  if (e.code == 'over_email_send_rate_limit') return true;
  final m = e.message.toLowerCase();
  return m.contains('security purposes') || (m.contains('after') && m.contains('second'));
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

/// Supabase 오류를 사용자에게 보여 줄 한국어 문구로 바꾼다.
String authErrorMessage(Object e) {
  if (e is AuthFailure) return e.message;

  final text = switch (e) {
    AuthException(:final message) => message,
    PostgrestException(:final message) => message,
    _ => e.toString(),
  };

  // supabase/migrations/202610110000_f01_signup.sql 에서 던지는 오류
  if (text.contains('F01_SCHOOL_EMAIL_ONLY') || text.contains('Database error saving new user')) {
    return '${AuthConfig.schoolName} 학교 메일로만 가입할 수 있어요.';
  }
  if (text.contains('F01_NICKNAME_TAKEN')) return '방금 다른 사람이 쓴 닉네임이에요. 다른 닉네임을 골라 주세요.';
  if (text.contains('F01_NICKNAME_INVALID')) return '닉네임은 2~10자의 한글·영문·숫자만 쓸 수 있어요.';
  if (text.contains('F01_TERMS_REQUIRED')) return '필수 약관에 동의해 주세요.';
  if (text.contains('Could not find the function')) return '서버에 F-01 마이그레이션이 아직 적용되지 않았어요.';
  if (text.contains('ClientException') ||
      text.contains('Failed to fetch') ||
      text.contains('SocketException') ||
      text.contains('Failed host lookup')) {
    return '서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.';
  }

  if (e is AuthException) {
    switch (e.code) {
      case 'otp_expired':
        return '코드가 틀렸거나 만료됐어요. 다시 확인해 주세요.';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.';
      case 'invalid_credentials':
        return '이메일 또는 비밀번호가 맞지 않아요.';
      case 'email_address_invalid':
        return '이메일 형식이 올바르지 않아요.';
      case 'weak_password':
        return '비밀번호가 너무 쉬워요. 영문과 숫자를 섞어 8자 이상으로 만들어 주세요.';
      case 'same_password':
        return '이전과 다른 비밀번호를 입력해 주세요.';
      case 'user_banned':
        return '이용이 정지된 계정이에요.';
    }
    if (text.contains('after') && text.contains('seconds')) return '잠시 후 다시 요청해 주세요.';
    return '오류가 발생했어요. ($text)';
  }
  return '오류가 발생했어요. 다시 시도해 주세요.';
}
