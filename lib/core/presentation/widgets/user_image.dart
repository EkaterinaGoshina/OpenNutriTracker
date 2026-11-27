import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';

/// Shows a photo the user attached, from wherever this platform keeps it.
///
/// [fallback] is what appears while it loads and when there is nothing to
/// show: no file, or bytes that do not decode.
class UserImage extends StatefulWidget {
  final String relativePath;
  final Widget fallback;
  final double? width;
  final double? height;

  const UserImage({
    super.key,
    required this.relativePath,
    required this.fallback,
    this.width,
    this.height,
  });

  @override
  State<UserImage> createState() => _UserImageState();
}

class _UserImageState extends State<UserImage> {
  late Future<ImageProvider?> _image;

  @override
  void initState() {
    super.initState();
    _load();
    UserImageStorage.revision.addListener(_reload);
  }

  @override
  void didUpdateWidget(UserImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath) _load();
  }

  @override
  void dispose() {
    UserImageStorage.revision.removeListener(_reload);
    super.dispose();
  }

  void _load() {
    _image = UserImageStorage.imageProvider(widget.relativePath);
  }

  void _reload() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ImageProvider?>(
      future: _image,
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image == null) return widget.fallback;
        return Image(
          image: image,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => widget.fallback,
        );
      },
    );
  }
}
