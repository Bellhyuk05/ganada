import 'package:flutter_test/flutter_test.dart';

import 'package:gachita/features/auth/auth_service.dart';
import 'package:gachita/features/auth/screens/profile_step.dart';

void main() {
  test('비밀번호는 영문과 숫자를 모두 포함해야 한다', () {
    expect(passwordHasLetterAndDigit('abcd1234'), isTrue);
    expect(passwordHasLetterAndDigit('abcdefgh'), isFalse);
    expect(passwordHasLetterAndDigit('12345678'), isFalse);
  });

  test('SQL 오류 코드를 한국어 문구로 바꾼다', () {
    expect(authErrorMessage(const AuthFailure('직접 문구')), '직접 문구');
    expect(authErrorMessage(Exception('F01_NICKNAME_TAKEN')), contains('닉네임'));
    expect(authErrorMessage(Exception('F01_SCHOOL_EMAIL_ONLY')), contains('학교 메일'));
  });
}
