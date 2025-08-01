// lib/create_playlist_screen.dart
import 'package:flutter/material.dart';
import 'package:beat_sync/music_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

class CreatePlaylistScreen extends StatefulWidget {
  const CreatePlaylistScreen({Key? key}) : super(key: key);

  @override
  State<CreatePlaylistScreen> createState() => _CreatePlaylistScreenState();
}

class _CreatePlaylistScreenState extends State<CreatePlaylistScreen>
    with SingleTickerProviderStateMixin {
  final _playlistNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // State variables
  List<String> _availableSongs = [];
  List<String> _playlistSongs = [];
  bool _isLoading = true;
  bool _isSaving = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..repeat(reverse: true);
    _fetchAvailableSongs();
  }

  /// Fetches all song names from your backend to display them
  Future<void> _fetchAvailableSongs() async {
    try {
      final songs = await MusicService.fetchSongs();
      setState(() {
        _availableSongs = songs;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching songs: ${e.toString()}')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  /// Saves the created playlist and its songs to Supabase
  Future<void> _savePlaylist() async {
    if (!_formKey.currentState!.validate() || _playlistSongs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please add a name and at least one song.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final playlistName = _playlistNameController.text.trim();

      // 1. Create the new playlist and get its generated ID
      final playlistResponse = await Supabase.instance.client
          .from('playlists')
          .insert({'name': playlistName, 'host_id': userId})
          .select('id')
          .single();

      final playlistId = playlistResponse['id'];

      // 2. Prepare the list of songs with their sequence number
      final List<Map<String, dynamic>> songsToInsert = [];
      for (int i = 0; i < _playlistSongs.length; i++) {
        songsToInsert.add({
          'playlist_id': playlistId,
          'song_name': _playlistSongs[i],
          'sequence': i, // The index in the list is the sequence
        });
      }

      // 3. Insert all songs into the playlist_songs table
      await Supabase.instance.client
          .from('playlist_songs')
          .insert(songsToInsert);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playlist "$playlistName" saved!')),
        );
        Navigator.of(context).pop(); // Go back to the previous screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving playlist: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create New Playlist', style: GoogleFonts.poppins()),
      ),
      // Use a FloatingActionButton to save the playlist
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _savePlaylist,
        label: _isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text('Save Playlist'),
        icon: _isSaving ? null : const Icon(Icons.save),
        backgroundColor: Colors.blue,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Text field for the playlist name
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _playlistNameController,
                      decoration: const InputDecoration(
                        labelText: 'Playlist Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value!.trim().isEmpty ? 'Name cannot be empty' : null,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // The list of songs the user has added to their new playlist
                  const Text('Your Playlist (Drag to Reorder)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                    flex: 1,
                    child: Card(
                      child: _playlistSongs.isEmpty
                          ? const Center(
                              child: Text('Add songs from the list below.'))
                          : ReorderableListView.builder(
                              itemCount: _playlistSongs.length,
                              itemBuilder: (context, index) {
                                final songName = _playlistSongs[index];
                                return ListTile(
                                  key: ValueKey(songName),
                                  title: Text(songName.replaceAll('.mp3', '')),
                                  leading: ReorderableDragStartListener(
                                    index: index,
                                    child: const Icon(Icons.drag_handle),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.remove_circle,
                                        color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        _playlistSongs.removeAt(index);
                                        _availableSongs.add(songName);
                                      });
                                    },
                                  ),
                                );
                              },
                              onReorder: (oldIndex, newIndex) {
                                setState(() {
                                  if (newIndex > oldIndex) newIndex -= 1;
                                  final song =
                                      _playlistSongs.removeAt(oldIndex);
                                  _playlistSongs.insert(newIndex, song);
                                });
                              },
                            ),
                    ),
                  ),
                  const Divider(height: 32),

                  // The list of all available songs from the user's bucket
                  const Text('Available Songs',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                    flex: 1,
                    child: Card(
                      child: ListView.builder(
                        itemCount: _availableSongs.length,
                        itemBuilder: (context, index) {
                          final songName = _availableSongs[index];
                          return ListTile(
                            key: ValueKey(songName),
                            title: Text(songName.replaceAll('.mp3', '')),
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle,
                                  color: Colors.blue),
                              onPressed: () {
                                setState(() {
                                  _playlistSongs.add(songName);
                                  _availableSongs.removeAt(index);
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  )
                ],
              ),
            ),
    );
  }
}
