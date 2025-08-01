// lib/join_room_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:beat_sync/room_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen>
    with SingleTickerProviderStateMixin {
  final _roomIdController = TextEditingController();
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  // Function to save room to recently joined rooms
  Future<void> _saveToRecentlyJoinedRooms(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final recentlyJoinedRoomsJson =
        prefs.getString('recently_joined_rooms') ?? '[]';
    final List<dynamic> roomIds = jsonDecode(recentlyJoinedRoomsJson);
    final updatedList = List<String>.from(roomIds);

    // Add the room ID to the beginning of the list
    if (!updatedList.contains(roomId)) {
      updatedList.insert(0, roomId);
    } else {
      // Move to the beginning if it already exists
      updatedList.remove(roomId);
      updatedList.insert(0, roomId);
    }

    // Keep only the last 10 rooms
    if (updatedList.length > 10) {
      updatedList.removeRange(10, updatedList.length);
    }

    await prefs.setString('recently_joined_rooms', jsonEncode(updatedList));
  }

  Future<void> _joinRoom(String roomId) async {
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room ID')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    try {
      // Check if room exists first
      final roomData = await Supabase.instance.client
          .from('rooms')
          .select()
          .eq('id', roomId)
          .single();

      // Add user to participants if not already a participant
      try {
        await Supabase.instance.client.from('room_participants').upsert({
          'room_id': roomId,
          'profile_id': userId,
        }, onConflict: 'room_id,profile_id');
      } catch (e) {
        // If upsert fails, try insert
        await Supabase.instance.client.from('room_participants').insert({
          'room_id': roomId,
          'profile_id': userId,
        });
      }

      // Save to recently joined rooms
      await _saveToRecentlyJoinedRooms(roomId);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RoomScreen(roomId: roomId)),
      );
    } catch (e) {
      print('Error joining room: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error joining room: ${e.toString()}')),
      );
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
        title: Text('Join a Room', style: GoogleFonts.poppins()),
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with icon
            ScaleTransition(
              scale: _animationController,
              child: Icon(
                Icons.qr_code_scanner,
                size: 64,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Join a Room',
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter a room ID or scan a QR code to join',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 40),

            // Room ID input
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
                      'Room ID',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _roomIdController,
                      decoration: InputDecoration(
                        hintText: 'Enter room ID...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        prefixIcon: const Icon(Icons.meeting_room),
                      ),
                      style: const TextStyle(fontSize: 18),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (value) => _joinRoom(value.trim()),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Join button
            FilledButton(
              onPressed: () => _joinRoom(_roomIdController.text.trim()),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                backgroundColor: Colors.blue,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Join by ID',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            const Divider(height: 48),

            const SizedBox(height: 16),

            // QR Scan button
            FilledButton.icon(
              icon: const Icon(Icons.qr_code, size: 24),
              label: const Text(
                'Scan QR Code',
                style: TextStyle(fontSize: 18),
              ),
              onPressed: () async {
                final result = await showModalBottomSheet<String>(
                  context: context,
                  builder: (_) => const QRScanSheet(),
                  isScrollControlled: true,
                );
                if (result != null) {
                  _roomIdController.text = result;
                  _joinRoom(result);
                }
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                backgroundColor: Colors.blue,
              ),
            ),

            const SizedBox(height: 24),

            // Info text
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'After joining, you\'ll be able to listen to music synchronized with the host and other participants.',
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

// A simple sheet for scanning QR codes
class QRScanSheet extends StatelessWidget {
  const QRScanSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            'Scan QR Code',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final code = capture.barcodes.first.rawValue;
                if (code != null) {
                  Navigator.of(context).pop(code);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
