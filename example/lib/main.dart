import 'dart:io';

import 'package:argear_flutter_example/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:argear_flutter/argear_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
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
    final viewCreatedState = useState(false);
    final loadingState = useState(true);
    final recordingTimeState = useState<double?>(null);

    useEffect(() {
      checkStatus() async {
        final status = await Permission.microphone.status;
        if (status.isDenied) {
          Permission.microphone.request();
        }
      }
      checkStatus();
    }, []);

    useEffect(() {
      if (viewCreatedState.value && argearController != null) {
        argearController?.setUp();
      }
    }, [viewCreatedState.value]);

    return Scaffold(
      body: Stack(children: [
        ARGearPreview(
          defaultFilterItemId: defaultFilterItemId,
          apiHost: apiHost,
          apiKey: apiKey,
          apiSecretKey: apiSecretKey,
          apiAuthKey: apiAuthKey,
          onVideoRecording: (sec) {
            recordingTimeState.value = sec;
          },
          onViewCreated: () {
            viewCreatedState.value = true;
          },
          onSetUpCompleted: () {
            loadingState.value = false;
          },
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
        if (loadingState.value) const Spinner(),
        if (!loadingState.value)
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
                  argearController?.addFilter(defaultFilterItemId);
                },
                child: const Text('フィルター追加'),
              ),
              TextButton(
                onPressed: () {
                  argearController?.clearBeauty();
                },
                child: const Text('ビューティー削除'),
              ),
              TextButton(
                onPressed: () {
                  argearController?.addBeauty();
                },
                child: const Text('ビューティー追加'),
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
              Text(recordingTimeState.value.toString()),
            ],
          )
      ]),
    );
  }
}

class Spinner extends StatelessWidget {
  const Spinner({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 24),
      child: Align(
        alignment: Alignment.center,
        child: CircularProgressIndicator(),
      ),
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
