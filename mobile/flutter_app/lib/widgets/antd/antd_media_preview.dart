import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/antd_tokens.dart';
import 'antd_modal.dart';
import 'antd_spin.dart';

enum AntdMediaType { image, video }

class AntdMediaPreview extends StatefulWidget {
  const AntdMediaPreview({
    super.key,
    required this.name,
    required this.type,
    this.imageBytes,
    this.videoUrl,
    this.videoHeaders = const {},
  });

  final String name;
  final AntdMediaType type;
  final Uint8List? imageBytes;
  final String? videoUrl;
  final Map<String, String> videoHeaders;

  @override
  State<AntdMediaPreview> createState() => _AntdMediaPreviewState();
}

class _AntdMediaPreviewState extends State<AntdMediaPreview> {
  Player? _player;
  VideoController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.type == AntdMediaType.video) {
      final player = Player();
      _player = player;
      _controller = VideoController(player);
      final url = widget.videoUrl;
      if (url == null) {
        _error = StateError('Missing video URL');
      } else {
        player
            .open(Media(url, httpHeaders: widget.videoHeaders))
            .catchError((Object error) {
          if (mounted) setState(() => _error = error);
        });
      }
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AntdModal(
      title: Text(widget.name),
      width: 960,
      bodyMaxHeight: 680,
      showFooter: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height.clamp(320, 620).toDouble(),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Text(
          '$_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AntdTokens.error),
        ),
      );
    }
    if (widget.type == AntdMediaType.image) {
      final bytes = widget.imageBytes;
      if (bytes == null) return const Center(child: AntdSpin());
      return InteractiveViewer(
        minScale: 0.25,
        maxScale: 8,
        child: Center(
          child: widget.name.toLowerCase().endsWith('.svg')
              ? SvgPicture.memory(bytes, fit: BoxFit.contain)
              : Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, error, __) => Text(
                    '$error',
                    style: const TextStyle(color: AntdTokens.error),
                  ),
                ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null) return const Center(child: AntdSpin());
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Video(controller: controller, fit: BoxFit.contain),
      ),
    );
  }
}
