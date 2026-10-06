import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  AudioPlayer? _player;
  Uint8List? _beepBytes;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _player = AudioPlayer();
      await _player!.setPlayerMode(PlayerMode.lowLatency);
      await _player!.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));
      await _player!.setVolume(1.0);

      // Preload bytes from asset bundle for instant playback
      try {
        final data = await rootBundle.load('assets/sounds/scanner_beep.mp3');
        _beepBytes = data.buffer.asUint8List();
        debugPrint('[SoundService] Preloaded custom barcode sound: ${_beepBytes!.length} bytes');
      } catch (e) {
        debugPrint('[SoundService] Preload error: $e');
      }

      _initialized = true;
    } catch (e) {
      debugPrint('[SoundService] init failed: $e');
    }
  }

  Future<void> playScannerBeep() async {
    // 1. Play immediate system feedback as guarantee
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}

    // 2. Play custom store scanner beep sound
    try {
      debugPrint('[SoundService] Playing barcode beep sound (bytes: ${_beepBytes?.length})...');
      final player = _player ?? AudioPlayer();
      if (_beepBytes != null) {
        await player.play(BytesSource(_beepBytes!), volume: 1.0);
      } else {
        await player.play(AssetSource('sounds/scanner_beep.mp3'), volume: 1.0);
      }
    } catch (e) {
      debugPrint('[SoundService] play error: $e');
      try {
        final fallback = AudioPlayer();
        await fallback.play(AssetSource('sounds/scanner_beep.mp3'), volume: 1.0);
      } catch (_) {}
    }
  }
}
