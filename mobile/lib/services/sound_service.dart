import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  AudioPool? _pool;
  AudioPlayer? _fallbackPlayer;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));

      // 1. Initialize AudioPool with trimmed, 0-latency WAV asset
      _pool = await AudioPool.createFromAsset(
        path: 'sounds/scanner_beep.wav',
        minPlayers: 2,
        maxPlayers: 4,
        playerMode: PlayerMode.lowLatency,
      );
      debugPrint('[SoundService] AudioPool initialized with zero-latency scanner_beep.wav');
      _initialized = true;
    } catch (e) {
      debugPrint('[SoundService] AudioPool init failed: $e, setting up fallback player');
      try {
        _fallbackPlayer = AudioPlayer();
        await _fallbackPlayer!.setPlayerMode(PlayerMode.lowLatency);
        await _fallbackPlayer!.setSource(AssetSource('sounds/scanner_beep.wav'));
        _initialized = true;
      } catch (err) {
        debugPrint('[SoundService] Fallback player error: $err');
      }
    }
  }

  void playScannerBeep() {
    // 1. Immediate hardware system click (0ms response guarantee)
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}

    // 2. Instant preloaded sound playback from pool
    try {
      if (_pool != null) {
        _pool!.start(volume: 1.0);
      } else if (_fallbackPlayer != null) {
        _fallbackPlayer!.seek(Duration.zero).then((_) {
          _fallbackPlayer!.resume();
        });
      } else {
        // Emergency uninitialized playback
        AudioPlayer().play(AssetSource('sounds/scanner_beep.wav'), volume: 1.0);
      }
    } catch (e) {
      debugPrint('[SoundService] playScannerBeep error: $e');
    }
  }
}
