// lib/home_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beat_sync/create_room_screen.dart';
import 'package:beat_sync/join_room_screen.dart';
import 'package:beat_sync/room_screen.dart';
import 'package:beat_sync/create_playlist_screen.dart'; // Import for Playlist Screen
import 'package:google_fonts/google_fonts.dart'; // Add for fonts

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  Future<List<Map<String, dynamic>>>? _hostedRoomsFuture;
  List<String> _recentlyJoinedRoomIds = [];
  // Future for fetching full data of recently joined rooms
  Future<List<Map<String, dynamic>>>? _recentlyJoinedRoomsFuture;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true); // For pulsing animations
    _loadRecentlyJoinedRooms();
    _loadRooms();
  }

  Future<void> _loadRecentlyJoinedRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final recentlyJoinedRoomsJson =
        prefs.getString('recently_joined_rooms') ?? '[]';
    final List<dynamic> roomIds = jsonDecode(recentlyJoinedRoomsJson);
    setState(() {
      _recentlyJoinedRoomIds = List<String>.from(roomIds);
      // Fetch full data for the recently joined rooms
      _loadRecentlyJoinedRoomsData();
    });
  }

  // Fetches full room data (id, name) for the UI
  void _loadRecentlyJoinedRoomsData() {
    if (_recentlyJoinedRoomIds.isEmpty) {
      setState(() {
        _recentlyJoinedRoomsFuture = Future.value([]); // Return an empty future
      });
      return;
    }
    setState(() {
      _recentlyJoinedRoomsFuture = Supabase.instance.client
          .from('rooms')
          .select('id, name')
          .inFilter('id', _recentlyJoinedRoomIds); // Corrected method name
    });
  }

  Future<void> _saveRecentlyJoinedRoom(String roomId) async {
    final updatedList = List<String>.from(_recentlyJoinedRoomIds);

    // Remove if exists, then add to the front to mark it as most recent
    updatedList.remove(roomId);
    updatedList.insert(0, roomId);

    // Keep only the last 10 rooms
    final uniqueList = updatedList.take(10).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recently_joined_rooms', jsonEncode(uniqueList));
    setState(() {
      _recentlyJoinedRoomIds = uniqueList;
      // Refresh the room data when the list changes
      _loadRecentlyJoinedRoomsData();
    });
  }

  Future<void> _removeRecentlyJoinedRoom(String roomId) async {
    final updatedList = List<String>.from(_recentlyJoinedRoomIds);
    updatedList.remove(roomId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recently_joined_rooms', jsonEncode(updatedList));
    setState(() {
      _recentlyJoinedRoomIds = updatedList;
      // Refresh the room data when the list changes
      _loadRecentlyJoinedRoomsData();
    });
  }

  Future<void> _loadRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId != null) {
      setState(() {
        _hostedRoomsFuture = Supabase.instance.client
            .from('rooms')
            .select()
            .eq('host_id', userId);
      });
    }
    // Refresh recently joined rooms data as well
    _loadRecentlyJoinedRoomsData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        // For smooth scrolling
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            flexibleSpace: FlexibleSpaceBar(
              title: Text('BeatSync',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.blue, Colors.black]),
                ),
                child: Center(
                    child: ScaleTransition(
                        scale: _animationController,
                        child: const Icon(Icons.music_note, size: 100))),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedScale(
                          scale: 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: FilledButton.icon(
                            icon: const Icon(Icons.add_box),
                            label: const Text('Create Room'),
                            onPressed: () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const CreateRoomScreen()));
                              _loadRooms();
                            },
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.blue),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Join Room'),
                          onPressed: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const JoinRoomScreen()));
                            _loadRooms();
                          },
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Manage Playlists'),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const CreatePlaylistScreen()));
                    },
                  ),
                  const SizedBox(height: 32),
                  const Text('Hosted Rooms',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildHostedRoomsList(),
                  const SizedBox(height: 32),
                  const Text('Recently Joined Rooms',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildRecentlyJoinedRoomsList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostedRoomsList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _hostedRoomsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                'You haven\'t created any rooms yet. Tap "Create Room" to get started!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          );
        }
        final rooms = snapshot.data!;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rooms.length,
          itemBuilder: (context, index) {
            final room = rooms[index];
            // dart
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.withOpacity(0.1),
                child: Icon(Icons.key, color: Colors.blue),
              ),
              title: Text(
                room['name'],
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text('ID: ${room['id']}'),
              trailing: Icon(Icons.arrow_forward_ios, color: Colors.blue),
              onTap: () => _handleRoomTap(room['id'], isHost: true),
            );
          },
        );
      },
    );
  }

  // dart
// file: 'lib/home_screen.dart'
  Widget _buildRecentlyJoinedRoomsList() {
    if (_recentlyJoinedRoomIds.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            'No recently joined rooms. Join a room to see it here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _recentlyJoinedRoomsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load rooms.'));
        }

        final rooms = snapshot.data!;

        final orderedRooms = <Map<String, dynamic>>[];
        for (final id in _recentlyJoinedRoomIds) {
          final room = rooms.firstWhere((r) => r['id'] == id, orElse: () => {});
          if (room.isNotEmpty) {
            orderedRooms.add(room);
          }
        }

        return SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: orderedRooms.length,
            itemBuilder: (context, index) {
              final room = orderedRooms[index];
              final roomId = room['id'] as String;
              final roomName = room['name'] as String;

              return Card(
                margin: const EdgeInsets.all(12.0),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.room,
                          size: 36,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        roomName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.login, size: 20),
                            onPressed: () =>
                                _handleRoomTap(roomId, isHost: false),
                            tooltip: 'Join Room',
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => _removeRecentlyJoinedRoom(roomId),
                            tooltip: 'Remove from List',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _handleRoomTap(String roomId, {required bool isHost}) async {
    if (!isHost) {
      final roomResponse = await Supabase.instance.client
          .from('rooms')
          .select('id')
          .eq('id', roomId)
          .maybeSingle();

      if (roomResponse == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('This room has been ended by the host.')),
          );
        }
        _loadRooms();
        _removeRecentlyJoinedRoom(roomId);
        return;
      }

      await _saveRecentlyJoinedRoom(roomId);
    }

    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RoomScreen(roomId: roomId)),
      );
      _loadRooms();
    }
  }
}
