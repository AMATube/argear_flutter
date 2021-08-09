import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef ARGearCallback = void Function(ARGearController controller);
typedef OnVideoRecorded = void Function(String path);
typedef OnSetUpCompleted = void Function();

const channelName = 'plugins.flutter.io/argear_flutter';

class ARGearPreview extends StatefulWidget {
  const ARGearPreview({
    Key? key,
    required this.argearCallback,
    required this.onVideoRecorded,
    required this.onSetUpCompleted,
    required this.defaultFilterItemId,
    required this.apiHost,
    required this.apiKey,
    required this.apiSecretKey,
    required this.apiAuthKey,
  }) : super(key: key);

  final ARGearCallback argearCallback;
  final OnVideoRecorded onVideoRecorded;
  final OnSetUpCompleted onSetUpCompleted;
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
    widget.argearCallback(controller);
    _controller = controller;
    await controller.setUp();
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
    _controller.destroySession();
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
      default:
        throw MissingPluginException();
    }
  }

  Future<void> setUp() async {
    channel.invokeMethod<void>('setUp');
  }

  Future<void> addFilter() async {
    channel.invokeMethod<void>('addFilter');
  }

  Future<void> clearFilter() async {
    channel.invokeMethod<void>('clearFilter');
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
}
