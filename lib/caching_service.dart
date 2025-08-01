// lib/caching_service.dart
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:beat_sync/music_service.dart';

class CachingService {
  CachingService._internal();
  static final CachingService _instance = CachingService._internal();
  static CachingService get instance => _instance;

  final CacheManager _cacheManager = DefaultCacheManager();

  /// Downloads a song and stores it in the cache.
  Future<void> cacheSong(String songName) async {
    try {
      final url = await MusicService.fetchSignedUrl(songName);
      await _cacheManager.downloadFile(url, key: songName);
      print('$songName has been cached.');
    } catch (e) {
      print('Failed to cache $songName: $e');
    }
  }

  /// Gets the local file path for a cached song. Returns null if not cached.
  Future<String?> getCachedSongPath(String songName) async {
    final fileInfo = await _cacheManager.getFileFromCache(songName);
    return fileInfo?.file.path;
  }

  /// Removes a specific song from the cache.
  Future<void> removeSongFromCache(String songName) async {
    await _cacheManager.removeFile(songName);
    print('$songName removed from cache.');
  }
}
