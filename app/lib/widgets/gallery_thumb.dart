import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/device/gallery_reader.dart';

/// 갤러리 썸네일 한 장을 불러와 보여 준다(선택 표시 등은 쓰는 쪽이 맡는다).
class GalleryThumb extends StatefulWidget {
  const GalleryThumb({super.key, required this.reader, required this.photoId});

  final GalleryReader reader;
  final String photoId;

  @override
  State<GalleryThumb> createState() => _GalleryThumbState();
}

class _GalleryThumbState extends State<GalleryThumb> {
  late final Future<Uint8List?> _bytes = widget.reader.thumbnail(
    widget.photoId,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) => snap.data == null
          ? const SizedBox.shrink()
          : Image.memory(snap.data!, fit: BoxFit.cover),
    );
  }
}
