// lib/music_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class MusicService {
  // ✅ IMPORTANT: Replace with your computer's local IP address
  // static const String _baseUrl = 'http://local ip address:port no.';
  static const String _baseUrl = 'https://beat-sync-backend.vercel.app';
  // static const String _baseUrl = 'http://172.31.29.118:3000';

  // Fetches the list of all available songs from your backend
  static Future<List<String>> fetchSongs() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/songs'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((song) => song['name'] as String).toList();
      } else {
        throw Exception(
            'Failed to load songs from backend: ${response.statusCode}');
      }
    } catch (e) {
      // Handle connection errors, etc.
      throw Exception('Could not connect to the server: $e');
    }
  }

  // Asks your backend for a temporary, secure URL to stream a song
  static Future<String> fetchSignedUrl(String songName) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/sign-url'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'name': songName}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['url'];
      } else {
        throw Exception('Failed to get signed URL: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Could not connect to the server: $e');
    }
  }
}
