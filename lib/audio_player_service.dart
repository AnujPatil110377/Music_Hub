// lib/audio_player_service.dart
import 'package:just_audio/just_audio.dart';

/// A singleton service to manage a single, shared AudioPlayer instance.
class AudioPlayerService {
  AudioPlayerService._internal();
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  static AudioPlayerService get instance => _instance;

  // This is our shared audio player for the entire app.
  final AudioPlayer player = AudioPlayer();
}
