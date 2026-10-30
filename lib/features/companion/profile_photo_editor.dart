import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'controller.dart';
import 'models.dart';
import 'profile_photo_processing.dart';

abstract interface class ProfilePhotoSource {
  Future<Uint8List?> pick();
}

class GalleryProfilePhotoSource implements ProfilePhotoSource {
  final ImagePicker _picker = ImagePicker();
  Future<Uint8List> _read(XFile file) async {
    if (await file.length() > ProfilePhotoProcessing.maxSourceBytes) {
      throw const FeatureFailure('8MB 이하의 사진을 선택해 주세요.');
    }
    return file.readAsBytes();
  }

  @override
  Future<Uint8List?> pick() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    return file == null ? null : _read(file);
  }

  Future<Uint8List?> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    return response.files?.isNotEmpty == true
        ? _read(response.files!.first)
        : null;
  }
}

Future<bool?> showProfilePhotoEditor(
  BuildContext context,
  CompanionController controller, {
  Uint8List? recoveredBytes,
  ProfilePhotoSource? source,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ProfilePhotoEditor(
    controller: controller,
    initialPhoto: controller.snapshot?.profile?.user.photo,
    initialBytes: recoveredBytes,
    source: source,
  ),
);

class ProfilePhotoEditor extends StatefulWidget {
  const ProfilePhotoEditor({
    super.key,
    required this.controller,
    this.initialPhoto,
    this.initialBytes,
    this.source,
  });
  final CompanionController controller;
  final ProfilePhoto? initialPhoto;
  final Uint8List? initialBytes;
  final ProfilePhotoSource? source;
  @override
  State<ProfilePhotoEditor> createState() => _ProfilePhotoEditorState();
}

class _ProfilePhotoEditorState extends State<ProfilePhotoEditor> {
  late final ProfilePhotoSource _source =
      widget.source ?? GalleryProfilePhotoSource();
  ui.Image? _image;
  double _zoom = 1, _x = .5, _y = .5;
  int _turns = 0;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final bytes = widget.initialBytes ?? widget.initialPhoto?.bytes;
    if (bytes != null) _read(() async => bytes);
  }

  Future<void> _read(Future<Uint8List?> Function() read) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final bytes = await read();
      if (bytes == null) return;
      final image = await ProfilePhotoProcessing.decode(bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      _image?.dispose();
      setState(() {
        _image = image;
        _zoom = 1;
        _x = .5;
        _y = .5;
        _turns = 0;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FeatureFailure
              ? e.message
              : '사진을 가져오지 못했어요. 사진 접근 권한을 확인하고 다시 선택해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() async {
    if (_working ||
        _image == null ||
        widget.controller.busy ||
        widget.controller.loading) {
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final photo = await ProfilePhotoProcessing.encode(
        _image!,
        zoom: _zoom,
        x: _x,
        y: _y,
        quarterTurns: _turns,
      );
      if (!mounted) return;
      final saved = await widget.controller.perform(
        () => widget.controller.repository.saveProfilePhoto(photo),
      );
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context, true);
        return;
      }
      setState(() => _error = widget.controller.error ?? '사진을 저장하지 못했어요.');
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FeatureFailure
              ? e.message
              : '사진을 처리하지 못했어요. 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('프로필 사진을 삭제할까요?'),
        content: const Text('기본 사용자 아이콘으로 표시됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final deleted = await widget.controller.perform(
      () => widget.controller.repository.saveProfilePhoto(null),
    );
    if (!mounted) return;
    if (deleted) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _working = false;
      _error = widget.controller.error ?? '사진을 삭제하지 못했어요.';
    });
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> update,
    bool disabled,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Slider(
        value: value,
        min: min,
        max: max,
        onChanged: disabled ? null : (v) => setState(() => update(v)),
        semanticFormatterCallback: (v) => v.toStringAsFixed(1),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final disabled =
          _working || widget.controller.busy || widget.controller.loading;
      return PopScope(
        canPop: !disabled,
        child: Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('프로필 사진'),
              leading: IconButton(
                tooltip: '취소',
                onPressed: disabled
                    ? null
                    : () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text('사진을 선택하고 원하는 부분을 조정해 주세요.'),
                const SizedBox(height: 20),
                Center(
                  child: SizedBox.square(
                    dimension: 240,
                    child: ClipOval(
                      child: ColoredBox(
                        color: const Color(0xFFEEF1FF),
                        child: _image == null
                            ? const Icon(Icons.person, size: 100)
                            : CustomPaint(
                                painter: _PhotoPainter(
                                  _image!,
                                  _zoom,
                                  _x,
                                  _y,
                                  _turns,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: disabled ? null : () => _read(_source.pick),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('갤러리에서 선택'),
                ),
                if (_image != null) ...[
                  _slider('확대', _zoom, 1, 4, (v) => _zoom = v, disabled),
                  _slider('가로 위치', _x, 0, 1, (v) => _x = v, disabled),
                  _slider('세로 위치', _y, 0, 1, (v) => _y = v, disabled),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: disabled
                              ? null
                              : () => setState(() => _turns = (_turns + 1) % 4),
                          icon: const Icon(Icons.rotate_right),
                          label: const Text('90° 회전'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: disabled
                            ? null
                            : () => setState(() {
                                _zoom = 1;
                                _x = .5;
                                _y = .5;
                                _turns = 0;
                              }),
                        child: const Text('조정 초기화'),
                      ),
                    ],
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_working) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: disabled || _image == null ? null : _save,
                  child: const Text('사진 저장'),
                ),
                if (widget.initialPhoto != null)
                  TextButton(
                    onPressed: disabled ? null : _delete,
                    child: const Text('현재 사진 삭제'),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter(this.image, this.zoom, this.x, this.y, this.turns);
  final ui.Image image;
  final double zoom, x, y;
  final int turns;
  @override
  void paint(Canvas canvas, Size size) => ProfilePhotoProcessing.paint(
    canvas,
    size,
    image,
    zoom: zoom,
    x: x,
    y: y,
    quarterTurns: turns,
  );
  @override
  bool shouldRepaint(_PhotoPainter oldDelegate) =>
      image != oldDelegate.image ||
      zoom != oldDelegate.zoom ||
      x != oldDelegate.x ||
      y != oldDelegate.y ||
      turns != oldDelegate.turns;
}
