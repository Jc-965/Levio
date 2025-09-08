import 'dart:async';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:parkinson/singleton.dart';

class SpeechAudio extends StatefulWidget {
  const SpeechAudio({super.key});

  @override
  State<SpeechAudio> createState() => _SpeechAudioState();
}

class _SpeechAudioState extends State<SpeechAudio> {
  final singleton = Singleton();

  PlayerState? _playerState;
  Duration? _duration;
  Duration? _position;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerCompleteSubscription;
  StreamSubscription? _playerStateChangeSubscription;

  bool get _isPlaying => _playerState == PlayerState.playing;
  bool get _isPaused => _playerState == PlayerState.paused;
  String get _durationText => _duration?.toString().split('.').first ?? '';
  String get _positionText => _position?.toString().split('.').first ?? '';

  final player = AudioPlayer();
  //player.setSource(UrlSource())
  // play(UrlSource('https://www2.cs.uic.edu/~i101/SoundFiles/BabyElephantWalk60.wav'))

  Future<void> _play() async {
    await player.play(UrlSource(singleton.currentURL));
    setState(() => _playerState = PlayerState.playing);
  }

  Future<void> _resume() async {
    await player.resume();
    setState(() => _playerState = PlayerState.playing);
  }

  Future<void> _pause() async {
    await player.pause();
    setState(() => _playerState = PlayerState.paused);
  }

  Future<void> _stop() async {
    await player.stop();
    setState(() {
      _playerState = PlayerState.stopped;
      _position = Duration.zero;
    });
  }

  void _initStreams() {
    _durationSubscription = player.onDurationChanged.listen((duration) {
      setState(() => _duration = duration);
    });

    _positionSubscription = player.onPositionChanged.listen(
      (p) => setState(() => _position = p),
    );

    _playerCompleteSubscription = player.onPlayerComplete.listen((event) {
      setState(() {
        _playerState = PlayerState.stopped;
        _position = Duration.zero;
      });
    });

    _playerStateChangeSubscription =
        player.onPlayerStateChanged.listen((state) {
      setState(() {
        _playerState = state;
      });
    });
  }

  void checkPause() {
    if (_isPaused) {
      _resume();
    } else {
      _play();
    }
  }

  @override
  void initState() {
    super.initState();
    // Use initial values from player
    _playerState = player.state;
    player.getDuration().then(
          (value) => setState(() {
            _duration = value;
          }),
        );
    player.getCurrentPosition().then(
          (value) => setState(() {
            _position = value;
          }),
        );
    _initStreams();
  }

  @override
  void setState(VoidCallback fn) {
    // Subscriptions only can be closed asynchronously,
    // therefore events can occur after widget has been disposed.
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void dispose() {
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    _playerStateChangeSubscription?.cancel();
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              dispose();
              Navigator.pushNamed(context, '/speechScreen');
            },
          ),
        ),
        body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                  Text(
                    singleton.speeches[singleton.currentURL]![0],
                    style: TextStyle(
                        color: singleton.themeColor[singleton.colorMode][1],
                        fontSize: 30,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: const Key('play_button'),
                            onPressed: _isPlaying ? null : checkPause,
                            iconSize: 48.0,
                            icon: const Icon(Icons.play_arrow),
                            color: singleton.themeColor[singleton.colorMode][1],
                          ),
                          IconButton(
                            key: const Key('pause_button'),
                            onPressed: _isPlaying ? _pause : null,
                            iconSize: 48.0,
                            icon: const Icon(Icons.pause),
                            color: singleton.themeColor[singleton.colorMode][1],
                          ),
                          IconButton(
                            key: const Key('stop_button'),
                            onPressed: _isPlaying || _isPaused ? _stop : null,
                            iconSize: 48.0,
                            icon: const Icon(Icons.stop),
                            color: singleton.themeColor[singleton.colorMode][1],
                          ),
                        ],
                      ),
                      Slider(
                        inactiveColor: singleton.themeColor[singleton.colorMode]
                            [25],
                        activeColor: singleton.themeColor[singleton.colorMode]
                            [1],
                        thumbColor: singleton.themeColor[singleton.colorMode]
                            [1],
                        onChanged: (value) {
                          final duration = _duration;
                          if (duration == null) {
                            return;
                          }

                          final position = value * duration.inMilliseconds;
                          player.seek(Duration(milliseconds: position.round()));
                        },
                        value: (_position != null &&
                                _duration != null &&
                                _position!.inMilliseconds > 0 &&
                                _position!.inMilliseconds <
                                    _duration!.inMilliseconds)
                            ? _position!.inMilliseconds /
                                _duration!.inMilliseconds
                            : 0.0,
                      ),
                      Text(
                        _position != null
                            ? '$_positionText / $_durationText'
                            : _duration != null
                                ? _durationText
                                : '',
                        style: TextStyle(
                            fontSize: 16.0,
                            color: singleton.themeColor[singleton.colorMode]
                                [1]),
                      ),
                    ],
                  ),
                ]))));
  }
}
