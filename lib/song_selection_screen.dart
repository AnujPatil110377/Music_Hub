// lib/song_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:beat_sync/audio_player_service.dart';
import 'package:beat_sync/music_service.dart';
import 'package:beat_sync/sync_service.dart';
import 'package:beat_sync/caching_service.dart';
import 'package:beat_sync/create_playlist_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class SongSelectionScreen extends StatefulWidget {
  final String roomId;
  const SongSelectionScreen({Key? key, required this.roomId}) : super(key: key);

  @override
  State<SongSelectionScreen> createState() => _SongSelectionScreenState();
}

class _SongSelectionScreenState extends State<SongSelectionScreen> {
  Future<List<Map<String, dynamic>>>? _playlistsFuture;
  bool _isActivatingPlaylist = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _fetchPlaylists();
  }

  Future<void> _fetchPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getString('user_id');
    if (_currentUserId == null) return;

    setState(() {
      _playlistsFuture = Supabase.instance.client
          .from('playlists')
          .select('id, name')
          .eq('host_id', _currentUserId!);
    });
  }

  Future<void> _onPlaylistSelected(
      String playlistId, String playlistName) async {
    if (_isActivatingPlaylist) return;
    setState(() => _isActivatingPlaylist = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Caching songs...'),
          ],
        ),
      ),
    );

    try {
      final songsData = await Supabase.instance.client
          .from('playlist_songs')
          .select('song_name')
          .eq('playlist_id', playlistId)
          .order('sequence', ascending: true);

      if (songsData.isEmpty) {
        throw Exception('This playlist is empty.');
      }
      final playlistSongs =
          songsData.map((s) => s['song_name'] as String).toList();
      final firstSong = playlistSongs[0];

      await CachingService.instance.cacheSong(firstSong);
      if (playlistSongs.length > 1) {
        CachingService.instance.cacheSong(playlistSongs[1]);
      }

      final localPath =
          await CachingService.instance.getCachedSongPath(firstSong);
      if (localPath == null) {
        throw Exception('Failed to cache and retrieve the first song.');
      }

      final signedUrl = await MusicService.fetchSignedUrl(firstSong);

      final player = AudioPlayerService.instance.player;
      await player.setFilePath(localPath);
      player.play();

      await Supabase.instance.client.from('rooms').update({
        'active_playlist_id': playlistId,
        'current_song_sequence': 0,
        'current_song_name': firstSong,
        'current_song_url': signedUrl,
        'is_playing': true,
        'current_position_seconds': 0.0,
        'last_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.roomId);

      SyncService().startHostPositionUpdates(widget.roomId);

      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        Navigator.of(context).pop(); // Close this screen
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting playlist: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isActivatingPlaylist = false);
    }
  }

  @override
  void dispose() {
    SyncService().stopHostPositionUpdates();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select a Playlist', style: GoogleFonts.poppins()),
        elevation: 4,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _playlistsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('You haven\'t created any playlists yet.'),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CreatePlaylistScreen(),
                        ),
                      );
                      _fetchPlaylists();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    child: const Text('Create one?'),
                  ),
                ],
              ),
            );
          }

          final playlists = snapshot.data!;
          return ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final playlistName = playlist['name'] as String;
              final playlistId = playlist['id'] as String;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: ListTile(
                  leading: const Icon(Icons.playlist_play, color: Colors.blue),
                  title: Text(
                    playlistName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: _isActivatingPlaylist
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.play_arrow),
                  onTap: () => _onPlaylistSelected(playlistId, playlistName),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
