import 'dart:io';

import 'package:argear_flutter_example/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:argear_flutter/argear_flutter.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends HookWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Home(),
    );
  }
}

// ignore: must_be_immutable
class Home extends HookWidget {
  Home({Key? key}) : super(key: key);

  ARGearController? argearController;

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      return () => argearController?.destroySession();
    }, []);
    return Scaffold(
      body: Stack(children: [
        ARGearPreview(
          defaultFilterItemId: defaultFilterItemId,
          apiHost: apiHost,
          apiKey: apiKey,
          apiSecretKey: apiSecretKey,
          apiAuthKey: apiAuthKey,
          onVideoRecorded: (path) {
            Navigator.of(context).push(
              MaterialPageRoute<PreviewPage>(
                builder: (BuildContext context) {
                  return PreviewPage(videoPath: path);
                },
              ),
            );
          },
          argearCallback: (c) async {
            argearController = c;
          },
        ),
        Column(
          children: [
            TextButton(
              onPressed: () {
                argearController?.clearFilter();
              },
              child: const Text('フィルター削除'),
            ),
            TextButton(
              onPressed: () {
                argearController?.addFilter();
              },
              child: const Text('フィルター追加'),
            ),
            TextButton(
              onPressed: () {
                argearController?.startVideoRecording();
              },
              child: const Text('録画開始'),
            ),
            TextButton(
              onPressed: () async {
                await argearController?.stopVideoRecording();
              },
              child: const Text('録画終了'),
            ),
          ],
        )
      ]),
    );
  }
}

// ignore: must_be_immutable
class PreviewPage extends HookWidget {
  PreviewPage({Key? key, required this.videoPath}) : super(key: key);

  final String videoPath;
  VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    final videoLoadingState = useState(true);

    final initVideo = useCallback(() async {
      try {
        controller = VideoPlayerController.file(File(videoPath));
        await controller?.initialize();
      } finally {
        videoLoadingState.value = false;
      }
    }, []);

    useEffect(() {
      initVideo();
      return () => controller?.dispose();
    }, []);

    return Scaffold(
      body: videoLoadingState.value
          ? const Text('...loading')
          : controller == null
              ? const Text('ビデオが再生できません')
              : VideoPlayerWidget(controller: controller!),
    );
  }
}

class VideoPlayerWidget extends HookWidget {
  const VideoPlayerWidget({Key? key, required this.controller})
      : super(key: key);

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      controller.setLooping(true);
      controller.play();
    }, []);

    return SafeArea(
      child: Center(
        child: VideoPlayer(controller),
      ),
    );
  }
}
