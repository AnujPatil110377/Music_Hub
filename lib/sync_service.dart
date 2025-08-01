// lib/sync_service.dart
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:beat_sync/audio_player_service.dart';
import 'package:beat_sync/caching_service.dart';
import 'package:beat_sync/music_service.dart'; // Needed for signed URL

/// A service to handle precise audio synchronization across devices
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  String? _currentSongName;
  Timer? _heartbeatTimer;
  Timer? _hostPositionTimer;
  bool _isSyncing = false;
  bool _wasPlaying = false;

  // ✅ NEW: Subscription to listen for song completion
  StreamSubscription<ProcessingState>? _playerStateSubscription;
  // ✅ NEW: Store the current room ID for the completion listener
  String? _currentRoomId;

  // Sync a listener's player (This function remains largely the same)
  Future<void> syncListenerPlayer({
    required Map<String, dynamic> roomData,
    required bool isInitialSync,
  }) async {
    final player = AudioPlayerService.instance.player;
    final newSongName = roomData['current_song_name'] as String?;
    final newUrl = roomData['current_song_url'] as String?;
    final isPlaying = roomData['is_playing'] as bool? ?? false;
    final lastUpdatedAtStr = roomData['last_updated_at'] as String?;
    final positionNum = roomData['current_position_seconds'] as num? ?? 0;
    final positionSeconds = positionNum.toDouble();

    if (isInitialSync && newSongName == null) {
      // If joining and nothing is playing, make sure player is stopped/paused
      await player.pause();
      return;
    }

    try {
      if (newSongName != null &&
          newUrl != null &&
          (_currentSongName != newSongName || isInitialSync)) {
        _currentSongName = newSongName;
        final localPath =
            await CachingService.instance.getCachedSongPath(newSongName);
        if (localPath != null) {
          await player.setFilePath(localPath);
        } else {
          await player.setUrl(newUrl);
          // Cache in background for future use
          CachingService.instance.cacheSong(newSongName);
        }

        if (lastUpdatedAtStr != null) {
          final lastUpdatedAt = DateTime.parse(lastUpdatedAtStr);
          final now = DateTime.now().toUtc();
          final latency = now.difference(lastUpdatedAt);

          final seekPosition =
              Duration(seconds: positionSeconds.toInt()) + latency;
          if (seekPosition.inSeconds >= 0) {
            // Ensure seek position is not negative
            await player.seek(seekPosition);
          } else {
            await player.seek(
                Duration.zero); // Seek to start if calculation is negative
          }
        }

        if (isPlaying) {
          await player.play();
          _wasPlaying = true;
        } else {
          // Explicitly pause if the initial state is paused
          await player.pause();
          _wasPlaying = false;
        }
      } else if (newSongName != null) {
        // Same song, check play state and position
        if (_wasPlaying != isPlaying) {
          // Play state changed
          if (isPlaying) {
            // Host resumed play
            if (lastUpdatedAtStr != null) {
              final lastUpdatedAt = DateTime.parse(lastUpdatedAtStr);
              final now = DateTime.now().toUtc();
              final latency = now.difference(lastUpdatedAt);

              final seekPosition =
                  Duration(seconds: positionSeconds.toInt()) + latency;
              if (seekPosition.inSeconds >= 0) {
                await player.seek(seekPosition);
              } else {
                await player.seek(Duration.zero);
              }
            }
            await player.play();
          } else {
            // Host paused
            await player.pause();
          }
          _wasPlaying = isPlaying;
        } else if (isPlaying) {
          // Still playing, sync position if needed
          if (lastUpdatedAtStr != null) {
            final lastUpdatedAt = DateTime.parse(lastUpdatedAtStr);
            final now = DateTime.now().toUtc();
            final latency = now.difference(lastUpdatedAt);

            final seekPosition =
                Duration(seconds: positionSeconds.toInt()) + latency;

            // Only seek if difference is significant
            if ((player.position - seekPosition).abs() >
                const Duration(milliseconds: 700)) {
              if (seekPosition.inSeconds >= 0) {
                await player.seek(seekPosition);
              } else {
                await player.seek(Duration.zero);
              }
            }
          }
        }
      } else if (newSongName == null && player.playing) {
        // If the song becomes null (e.g., during the pause), stop the player
        await player.pause();
        _wasPlaying = false;
      }

      // Pre-cache logic remains the same
      final playlistId = roomData['active_playlist_id'] as String?;
      final currentSequence = roomData['current_song_sequence'] as int?;
      if (playlistId != null && currentSequence != null) {
        try {
          final nextSongData = await Supabase.instance.client
              .from('playlist_songs')
              .select('song_name')
              .eq('playlist_id', playlistId)
              .eq('sequence', currentSequence + 1)
              .maybeSingle();

          if (nextSongData != null) {
            final nextSongName = nextSongData['song_name'];
            CachingService.instance.cacheSong(nextSongName);
          }
        } catch (e) {
          print('Error pre-caching next song: $e');
        }
      }
    } catch (e) {
      print('Error syncing listener player: $e');
      // Avoid rethrowing here, let heartbeat continue
    }
  }

  /// Start heartbeat mechanism (This function remains the same)
  void startHeartbeatSync(String roomId) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_isSyncing) return;
      try {
        _isSyncing = true;
        final roomData = await Supabase.instance.client
            .from('rooms')
            .select()
            .eq('id', roomId)
            .single();
        await syncListenerPlayer(roomData: roomData, isInitialSync: false);
      } catch (e) {
        print('Heartbeat sync error: $e');
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// Start host position updates AND listen for song completion
  void startHostPositionUpdates(String roomId) {
    final player = AudioPlayerService.instance.player;
    _currentRoomId = roomId; // Store room ID for the completion listener
    _hostPositionTimer?.cancel();
    _playerStateSubscription?.cancel(); // Cancel previous listener

    _hostPositionTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (player.playing) {
        Supabase.instance.client.from('rooms').update({
          'current_position_seconds': player.position.inMilliseconds / 1000.0,
          'last_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', roomId);
      }
    });

    // ✅ NEW: Listen for when the song finishes
    _playerStateSubscription = player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _playNextSong(); // Trigger the logic to play the next song
      }
    });
  }

  // ✅ NEW: Function to handle the transition to the next song
  Future<void> _playNextSong() async {
    if (_currentRoomId == null) return; // Need room context

    final player = AudioPlayerService.instance.player;

    try {
      // 1. Get current room state to find the sequence
      final roomData = await Supabase.instance.client
          .from('rooms')
          .select(
              'active_playlist_id, current_song_sequence, current_song_name')
          .eq('id', _currentRoomId!)
          .single();

      final playlistId = roomData['active_playlist_id'] as String?;
      final currentSequence = roomData['current_song_sequence'] as int?;
      final completedSongName = roomData['current_song_name'] as String?;

      if (playlistId == null || currentSequence == null)
        return; // No active playlist/sequence

      // 2. PAUSE & SYNC: Update Supabase to signal a pause between songs
      await Supabase.instance.client.from('rooms').update({
        'is_playing': false,
        'current_song_url': null, // Clear URL during pause
        'current_song_name': null, // Clear name during pause
      }).eq('id', _currentRoomId!);

      // Stop sending position updates during the pause
      _hostPositionTimer?.cancel();

      // 3. WAIT: Short delay for listeners to sync to the pause state
      await Future.delayed(const Duration(seconds: 3));

      // 4. Find the next song in the playlist
      final nextSequence = currentSequence + 1;
      final nextSongData = await Supabase.instance.client
          .from('playlist_songs')
          .select('song_name')
          .eq('playlist_id', playlistId)
          .eq('sequence', nextSequence)
          .maybeSingle();

      if (nextSongData != null) {
        // If there is a next song
        final nextSongName = nextSongData['song_name'] as String;

        // 5. Manage Cache
        if (completedSongName != null) {
          CachingService.instance.removeSongFromCache(completedSongName);
        }
        // Cache the song *after* the next one (sequence + 2)
        final nextNextSongData = await Supabase.instance.client
            .from('playlist_songs')
            .select('song_name')
            .eq('playlist_id', playlistId)
            .eq('sequence', nextSequence + 1)
            .maybeSingle();
        if (nextNextSongData != null) {
          CachingService.instance.cacheSong(nextNextSongData['song_name']);
        }

        // 6. Get playback source (cache first, then signed URL)
        String playbackSource;
        bool isLocal = false;
        final localPath =
            await CachingService.instance.getCachedSongPath(nextSongName);
        if (localPath != null) {
          playbackSource = localPath;
          isLocal = true;
        } else {
          // Fallback: get signed URL if not cached (shouldn't happen often)
          playbackSource = await MusicService.fetchSignedUrl(nextSongName);
        }

        // 7. Get Signed URL *for listeners*
        final listenerUrl = await MusicService.fetchSignedUrl(nextSongName);

        // 8. Update Supabase with the NEXT song details and set playing to TRUE
        await Supabase.instance.client.from('rooms').update({
          'current_song_sequence': nextSequence,
          'current_song_name': nextSongName,
          'current_song_url': listenerUrl, // URL for listeners
          'is_playing': true,
          'current_position_seconds': 0.0,
          'last_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', _currentRoomId!);

        // 9. Start Playback on Host
        if (isLocal) {
          await player.setFilePath(playbackSource);
        } else {
          await player.setUrl(playbackSource);
        }
        player.play();

        // 10. Restart host position updates
        startHostPositionUpdates(
            _currentRoomId!); // Recursively calls itself indirectly via listener
      } else {
        // End of playlist
        stopHostPositionUpdates(); // Stop sending updates
      }
    } catch (e) {
      print('Error playing next song: $e');
      stopHostPositionUpdates(); // Stop updates on error
    }
  }

  // Stop heartbeat sync (This function remains the same)
  void stopHeartbeatSync() {
    _heartbeatTimer?.cancel();
  }

  // Stop host position updates AND the completion listener
  void stopHostPositionUpdates() {
    _hostPositionTimer?.cancel();
    _playerStateSubscription?.cancel();
    _currentRoomId = null; // Clear room context
  }
}
