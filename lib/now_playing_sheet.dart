// lib/now_playing_sheet.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:beat_sync/audio_player_service.dart';
import 'package:beat_sync/caching_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class NowPlayingSheet extends StatefulWidget {
  final String roomId;
  final bool isHost;
  final String songName;

  const NowPlayingSheet({
    Key? key,
    required this.roomId,
    required this.isHost,
    required this.songName,
  }) : super(key: key);

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet>
    with SingleTickerProviderStateMixin {
  late final StreamSubscription<ja.PlayerState> _playerStateSubscription;
  late final AnimationController _pulseController;
  late final PlayerController _waveformController;

  bool _isPlaying = false;
  bool _isLoading = true;
  String? _waveformPath;

  @override
  void initState() {
    super.initState();

    // Pulse animation for play button
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Initialize waveform controller (NO setRefreshRate!)
    _waveformController = PlayerController();

    _playerStateSubscription =
        AudioPlayerService.instance.player.playerStateStream.listen((state) {
      if (!mounted) return;

      setState(() {
        _isPlaying = state.playing;
        if (_isPlaying) {
          _pulseController.repeat(reverse: true);
          _waveformController.startPlayer();
        } else {
          _pulseController.stop();
          _waveformController.stopPlayer();
        }
      });
    });

    _initializeWaveform();
  }

  Future<void> _initializeWaveform() async {
    try {
      final localPath =
          await CachingService.instance.getCachedSongPath(widget.songName);

      if (localPath != null && mounted) {
        await _waveformController.preparePlayer(
          path: localPath,
          shouldExtractWaveform: true,
        );

        if (mounted) {
          setState(() {
            _waveformPath = localPath;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Waveform init error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _playerStateSubscription.cancel();
    _pulseController.dispose();
    _waveformController.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause(ja.PlayerState playerState) async {
    if (!widget.isHost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the host can control playback'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final player = AudioPlayerService.instance.player;
    final isPlaying = playerState.playing;
    final position = player.position.inMilliseconds / 1000.0;
    final now = DateTime.now().toUtc().toIso8601String();

    if (isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }

    await Supabase.instance.client.from('rooms').update({
      'is_playing': !isPlaying,
      'current_position_seconds': position,
      'last_updated_at': now,
    }).eq('id', widget.roomId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      height: MediaQuery.of(context).size.height * 0.45,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.primary.withOpacity(0.15),
            theme.colorScheme.surface.withOpacity(0.9),
            theme.colorScheme.surface,
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 20),

          // Song Title
          Text(
            widget.songName.replaceAll('.mp3', ''),
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 8),
          Text(
            _isPlaying ? 'Now Playing' : 'Paused',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: _isPlaying ? theme.colorScheme.primary : Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 24),

          // Waveform Visualization
          Container(
            height: 100,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _waveformPath != null
                    ? AudioFileWaveforms(
                        size: Size(MediaQuery.of(context).size.width, 80),
                        playerController: _waveformController,
                        waveformType: WaveformType.long,
                        playerWaveStyle: PlayerWaveStyle(
                          fixedWaveColor:
                              theme.colorScheme.primary.withOpacity(0.3),
                          liveWaveColor: theme.colorScheme.primary,
                          spacing: 5,
                          waveThickness: 3,
                          scaleFactor: 120,
                        ),
                      )
                    : Center(
                        child: Text(
                          'Waveform unavailable',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ),
          ),

          const SizedBox(height: 28),

          // Playback Controls
          StreamBuilder<ja.PlayerState>(
            stream: AudioPlayerService.instance.player.playerStateStream,
            builder: (context, snapshot) {
              final playerState = snapshot.data;
              final isBuffering = playerState?.processingState ==
                      ja.ProcessingState.buffering ||
                  playerState?.processingState == ja.ProcessingState.loading;

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Previous
                  _ControlButton(
                    icon: Icons.skip_previous_rounded,
                    onPressed: widget.isHost ? () {} : null,
                    size: 50,
                  ),

                  const SizedBox(width: 20),

                  // Play/Pause (Pulsing)
                  ScaleTransition(
                    scale: Tween<double>(begin: 1.0, end: 1.15).animate(
                      CurvedAnimation(
                        parent: _pulseController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.4),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 34,
                        backgroundColor: theme.colorScheme.primary,
                        child: isBuffering
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : IconButton(
                                icon: Icon(
                                  _isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 38,
                                ),
                                onPressed: widget.isHost
                                    ? () => _togglePlayPause(playerState!)
                                    : null,
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 20),

                  // Next
                  _ControlButton(
                    icon: Icons.skip_next_rounded,
                    onPressed: widget.isHost ? () {} : null,
                    size: 50,
                  ),
                ],
              );
            },
          ),

          const Spacer(),
        ],
      ),
    );
  }
}

// Reusable Control Button
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  const _ControlButton({
    required this.icon,
    this.onPressed,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;

    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? theme.colorScheme.surface.withOpacity(0.8)
              : Colors.transparent,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: IconButton(
          icon: Icon(
            icon,
            size: 28,
            color: enabled ? theme.colorScheme.primary : Colors.grey,
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
