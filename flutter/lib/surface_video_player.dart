import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Native ExoPlayer controller that renders via SurfaceView (not TextureView).
///
/// On Android TV, hardware decoders may fail when rendering to a SurfaceTexture
/// (Flutter's default). SurfaceView renders directly to the display, bypassing
/// the extra GPU composition pass that causes the failure.
class SurfaceVideoPlayerController {
  static const _viewType = 'com.example.alextv/surface_video_player';

  final MethodChannel _channel;
  final Completer<void> _ready = Completer();
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  SurfaceVideoPlayerController._(this._channel) {
    _channel.setMethodCallHandler(_handleCall);
  }

  static Widget view({
    required String url,
    String ext = '',
    bool autoPlay = true,
    required void Function(SurfaceVideoPlayerController) onCreated,
  }) {
    return AndroidView(
      viewType: _viewType,
      creationParams: {'url': url, 'ext': ext, 'autoPlay': autoPlay},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (id) {
        final channel = MethodChannel('$_viewType/$id');
        onCreated(SurfaceVideoPlayerController._(channel));
      },
    );
  }

  Future<void> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'onReady':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _duration = Duration(milliseconds: (args['duration'] as num?)?.toInt() ?? 0);
        if (!_ready.isCompleted) _ready.complete();
        _stateController.add(PlayerState.ready);
      case 'onStateChanged':
        final state = (call.arguments as Map)['state'] as String;
        switch (state) {
          case 'buffering':
            _stateController.add(PlayerState.buffering);
          case 'ended':
            _isPlaying = false;
            _stateController.add(PlayerState.ended);
          case 'idle':
            _stateController.add(PlayerState.idle);
          case 'ready':
            _stateController.add(PlayerState.ready);
        }
      case 'onPlayingChanged':
        _isPlaying = (call.arguments as Map)['isPlaying'] as bool;
        _stateController.add(_isPlaying ? PlayerState.playing : PlayerState.paused);
      case 'onError':
        _error = (call.arguments as Map)['message'] as String?;
        if (!_ready.isCompleted) _ready.completeError(_error ?? 'Playback error');
        _stateController.add(PlayerState.error);
    }
  }

  Future<void> get ready => _ready.future;
  Stream<PlayerState> get stateStream => _stateController.stream;
  bool get isPlaying => _isPlaying;
  String? get error => _error;

  Duration get position => _position;
  Duration get duration => _duration;

  Future<void> play() => _channel.invokeMethod('play');
  Future<void> pause() => _channel.invokeMethod('pause');
  Future<void> seekTo(Duration position) =>
      _channel.invokeMethod('seekTo', {'position': position.inMilliseconds});
  Future<void> setVolume(double volume) =>
      _channel.invokeMethod('setVolume', {'volume': volume});

  Future<Duration> getPosition() async {
    final pos = await _channel.invokeMethod<int>('getPosition');
    _position = Duration(milliseconds: pos ?? 0);
    return _position;
  }

  void startPolling() {
    Timer.periodic(const Duration(milliseconds: 500), (t) async {
      if (!_stateController.isClosed) {
        _position = await getPosition();
        _positionController.add(_position);
      } else {
        t.cancel();
      }
    });
  }

  Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
    _stateController.close();
    _positionController.close();
  }
}

enum PlayerState { idle, buffering, ready, playing, paused, ended, error }
