import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

typedef ARGearCallback = void Function(ARGearController controller);
typedef OnVideoRecording = void Function(double? sec);
typedef OnVideoRecorded = void Function(String path);
typedef OnSetUpCompleted = void Function();
typedef OnViewCreated = void Function();

const channelName = 'plugins.flutter.io/argear_flutter';

class ARGearPreview extends StatefulWidget {
  const ARGearPreview({
    Key? key,
    required this.argearCallback,
    required this.onVideoRecording,
    required this.onVideoRecorded,
    required this.onSetUpCompleted,
    required this.onViewCreated,
    required this.defaultFilterItemId,
    required this.apiHost,
    required this.apiKey,
    required this.apiSecretKey,
    required this.apiAuthKey,
  }) : super(key: key);

  final ARGearCallback argearCallback;
  final OnVideoRecording onVideoRecording;
  final OnVideoRecorded onVideoRecorded;
  final OnSetUpCompleted onSetUpCompleted;
  final OnViewCreated onViewCreated;
  final String defaultFilterItemId;
  final String apiHost;
  final String apiKey;
  final String apiSecretKey;
  final String apiAuthKey;

  @override
  createState() => _ARGearState();
}

class _ARGearState extends State<ARGearPreview> {
  // ignore: unused_field
  late ARGearController _controller;

  Future<void> _onPlatformViewCreated(int id) async {
    final controller = await ARGearController.init(id, this);
    await controller.startSession();
    widget.argearCallback(controller);
    _controller = controller;
    widget.onViewCreated();
  }

  void onVideoRecording(double? sec) {
    widget.onVideoRecording(sec);
  }

  void onVideoRecorded(String path) {
    widget.onVideoRecorded(path);
  }

  void onSetUpCompleted() {
    widget.onSetUpCompleted();
  }

  @override
  void dispose() {
    super.dispose();
    _controller.pauseSession();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, Object> args = {
      'defaultFilterItemId': widget.defaultFilterItemId,
      'apiHost': widget.apiHost,
      'apiKey': widget.apiKey,
      'apiSecretKey': widget.apiSecretKey,
      'apiAuthKey': widget.apiAuthKey,
    };

    return UiKitView(
      viewType: channelName,
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: args,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

class ARGearController {
  ARGearController._(this.channel, this._argState) {
    channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel channel;
  final _ARGearState _argState;

  static Future<ARGearController> init(int id, _ARGearState _argState) async {
    final channel = MethodChannel('$channelName/$id');
    return ARGearController._(channel, _argState);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onVideoRecording':
        final sec = call.arguments['sec'] as double?;
        _argState.onVideoRecording(sec);
        break;
      case 'onVideoRecordingComplete':
        final video = call.arguments['video'] as String?;
        if (video == null) {
          throw Exception();
        }
        _argState.onVideoRecorded(video);
        break;
      case 'onSetUpComplete':
        _argState.onSetUpCompleted();
        break;
      case 'onDownloadItemComplete':
        final fileName = call.arguments['zipFileName'] as String?;
        if (fileName != null) {
          final cacheDir = await getTemporaryDirectory();
          final itemPath = '${cacheDir.path}/$fileName';
          channel.invokeMethod<void>('addFilter',
              {'cacheFilePath': itemPath, 'itemId': fileName.split('.')[0]});
        }
        break;
      default:
        throw MissingPluginException();
    }
  }

  Future<void> setUp() async {
    channel.invokeMethod<void>('setUp');
  }

  Future<void> addFilter(String itemId) async {
    final cacheDir = await getTemporaryDirectory();
    final itemPath = '${cacheDir.path}/$itemId.zip';
    final isExists = File(itemPath).existsSync();
    if (isExists) {
      channel.invokeMethod<void>(
          'addFilter', {'cacheFilePath': itemPath, 'itemId': itemId});
    } else {
      await channel.invokeMethod<String?>('downloadItem');
    }
  }

  Future<void> clearFilter() async {
    channel.invokeMethod<void>('clearFilter');
  }

  Future<void> clearBeauty() async {
    channel.invokeMethod<void>('clearBeauty');
  }

  Future<void> addBeauty() async {
    channel.invokeMethod<void>('addBeauty');
  }

  Future<void> startVideoRecording() async {
    channel.invokeMethod<void>('startVideoRecording');
  }

  Future<void> stopVideoRecording() async {
    channel.invokeMethod<void>('stopVideoRecording');
  }

  Future<void> destroySession() async {
    channel.invokeMethod<void>('destroy');
  }

  Future<void> pauseSession() async {
    channel.invokeMethod<void>('pause');
  }

  Future<void> startSession() async {
    channel.invokeMethod<void>('start');
  }
}
