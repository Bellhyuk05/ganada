import 'package:flutter/material.dart';

import '../auth_colors.dart';

enum TermsType { service, privacy }

// TODO: 팀에서 확정한 약관 · 개인정보 처리방침 문구로 교체.
const _terms = {
  TermsType.service: (
    '서비스 이용약관',
    '제1조 (목적)\n이 약관은 같이타(이하 "서비스")가 제공하는 택시 동행 모집 서비스의 이용 조건을 정합니다.\n\n'
        '제2조 (가입 자격)\n서비스는 한국교통대학교 학교 이메일 인증을 마친 학생만 이용할 수 있습니다.\n\n'
        '제3조 (이용자의 의무)\n이용자는 약속한 동행에 성실히 참여해야 하며, 노쇼가 기록될 수 있습니다.\n\n'
        '(캡스톤디자인 프로젝트용 임시 문구입니다.)',
  ),
  TermsType.privacy: (
    '개인정보 수집·이용 동의',
    '1. 수집 항목: 학교 이메일, 닉네임, 서비스 이용 기록(참여·노쇼·평가)\n\n'
        '2. 수집 목적: 재학생 확인, 동행 모집 및 채팅 서비스 제공, 신뢰도 표시\n\n'
        '3. 보유 기간: 회원 탈퇴 시까지. 채팅 내용은 출발 시각 12시간 후 삭제됩니다.\n\n'
        '4. 실명과 학번은 수집하지 않습니다.\n\n'
        '(캡스톤디자인 프로젝트용 임시 문구입니다.)',
  ),
};

void showTermsSheet(BuildContext context, TermsType type) {
  final (title, body) = _terms[type]!;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AuthColors.textStrong)),
          const SizedBox(height: 16),
          Text(body, style: const TextStyle(fontSize: 14, height: 1.7, color: AuthColors.textBody)),
        ],
      ),
    ),
  );
}
