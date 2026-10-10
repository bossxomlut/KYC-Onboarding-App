import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Owns private image-cache lifetime at the reviewer page boundary.
class PrivateReviewPhoto extends StatefulWidget {
  const PrivateReviewPhoto({
    required this.bytes,
    required this.label,
    super.key,
  });
  final Uint8List bytes;
  final String label;
  @override
  State<PrivateReviewPhoto> createState() => _PrivateReviewPhotoState();
}

class _PrivateReviewPhotoState extends State<PrivateReviewPhoto> {
  late MemoryImage _image;
  @override
  void initState() {
    super.initState();
    _image = MemoryImage(widget.bytes);
  }

  @override
  void didUpdateWidget(PrivateReviewPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _image.evict();
      _image = MemoryImage(widget.bytes);
    }
  }

  @override
  void dispose() {
    _image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image(
      image: _image,
      height: 250,
      fit: BoxFit.contain,
      semanticLabel: widget.label,
      errorBuilder: (_, _, _) => const SizedBox(
        height: 80,
        child: Center(
          child: Text('This image cannot be displayed. Refresh and try again.'),
        ),
      ),
    ),
  );
}
