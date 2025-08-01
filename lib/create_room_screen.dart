// lib/create_room_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:beat_sync/room_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen>
    with SingleTickerProviderStateMixin {
  final _roomNameController = TextEditingController();
  bool _isLoading = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      // duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();
  }

  Future<void> _createRoom() async {
    setState(() => _isLoading = true);
    final roomName = _roomNameController.text.trim();
    if (roomName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room name')),
      );
      setState(() => _isLoading = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    try {
      // 1. Create the room and get its ID
      final room = await Supabase.instance.client
          .from('rooms')
          .insert({'name': roomName, 'host_id': userId})
          .select()
          .single();

      final roomId = room['id'];

      // 2. Add the host as the first participant
      await Supabase.instance.client.from('room_participants').insert({
        'room_id': roomId,
        'profile_id': userId,
      });

      if (!mounted) return;
      // Navigate to the Room Screen, replacing the creation screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RoomScreen(roomId: roomId)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating room: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Create a Room', style: GoogleFonts.poppins()),
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with icon
            ScaleTransition(
              scale: _animationController,
              child: Icon(
                Icons.music_note,
                size: 64,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Create a New Room',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter a name for your music room and start syncing with friends',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue,
              ),
            ),

            const SizedBox(height: 40),

            // Room name input with enhanced styling
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Room Name',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _roomNameController,
                      decoration: InputDecoration(
                        hintText: 'Enter room name...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.black12,
                        prefixIcon: const Icon(Icons.meeting_room),
                      ),
                      style: const TextStyle(fontSize: 18),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _createRoom(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Create button with enhanced styling
            FilledButton(
              onPressed: _isLoading ? null : _createRoom,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                backgroundColor: Colors.blue,
              ),
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                        SizedBox(width: 16),
                        Text(
                          'Creating Room...',
                          style: TextStyle(fontSize: 18),
                        ),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_box, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'Create and Join Room',
                          style: TextStyle(fontSize: 18),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 24),

            // Info text
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'As the host, you\'ll be able to select songs and control playback for all participants in the room.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
