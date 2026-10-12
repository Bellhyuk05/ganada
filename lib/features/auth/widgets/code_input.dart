import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_colors.dart';

/// 시안의 6칸 인증 코드 입력.
/// 실제 입력은 보이지 않는 TextField 하나가 받아서 붙여넣기 · 자동완성(oneTimeCode)이 그대로 동작한다.
class CodeInput extends StatefulWidget {
  const CodeInput({
    super.key,
    required this.controller,
    required this.length,
    this.onCompleted,
    this.onChanged,
    this.hasError = false,
  });

  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final bool hasError;

  @override
  State<CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<CodeInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// 칸을 누르면 항상 키보드를 띄운다.
  /// 뒤로가기로 키보드만 내려간 경우 포커스는 남아 있어서 requestFocus 만으로는 다시 안 뜬다.
  void _openKeyboard() {
    if (_focus.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openKeyboard,
      child: Stack(
        children: [
          // 화면에는 보이지 않지만 키보드 입력을 받는 칸
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 1,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: widget.length,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                showCursor: false,
                enableInteractiveSelection: false,
                onChanged: (v) {
                  setState(() {});
                  widget.onChanged?.call(v);
                  if (v.length == widget.length) widget.onCompleted?.call(v);
                },
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _box(i, text)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _box(int i, String text) {
    final filled = i < text.length;
    final active = _focus.hasFocus && (i == text.length || (i == widget.length - 1 && text.length == widget.length));
    final borderColor = widget.hasError
        ? AuthColors.error
        : active
            ? AuthColors.primary
            : AuthColors.border;

    return AspectRatio(
      aspectRatio: 0.86,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: active ? 1.5 : 1),
        ),
        child: filled
            ? Text(
                text[i],
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AuthColors.textStrong),
              )
            : active
                ? Container(width: 2, height: 26, color: AuthColors.primary)
                : null,
      ),
    );
  }
}
