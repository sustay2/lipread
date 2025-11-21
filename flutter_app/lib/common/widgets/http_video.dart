import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class HttpVideo extends StatefulWidget {
  final String url;
  const HttpVideo({super.key, required this.url});

  @override
  State<HttpVideo> createState() => _HttpVideoState();
}

class _HttpVideoState extends State<HttpVideo> {
  late final VideoPlayerController _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _c.play();
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const AspectRatio(
        aspectRatio: 16/9,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return AspectRatio(
      aspectRatio: _c.value.aspectRatio == 0 ? 16/9 : _c.value.aspectRatio,
      child: VideoPlayer(_c),
    );
  }
}