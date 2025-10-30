# Beat Sync 

A Flutter application for synchronized music playback across multiple devices using Supabase and just_audio. One device acts as the host while others join as listeners; playback state, timing, and playlist progression are shared via Supabase.

---

## Table of contents
- [Features](#features)
- [Quick start](#quick-start)
- [Project structure](#project-structure)
- [How it works](#how-it-works)
  - [Host flow](#host-flow)
  - [Listener flow](#listener-flow)
- [Configuration](#configuration)
- [Permissions](#permissions)
- [Building for production](#building-for-production)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License & Support](#license--support)

---

## Features
- Host–Listener architecture (one device controls, others follow)
- Real-time synchronization (sub-second accuracy)
- Automatic drift correction (threshold-based adjustments)
- Smart caching (preloads songs for smooth transitions)
- Cross-platform: Android & iOS
- Playlist management with seamless track switching

## Quick start
Prerequisites:
- Flutter SDK (>= 3.0.0)
- Dart SDK (>= 3.0.0)
- Supabase account + project
- Android Studio / VS Code

Clone and install:

```bash
git clone https://github.com/yourusername/beat-sync.git
cd beat-sync
flutter pub get
```

Configure Supabase: create a `.env` in the project root with:

```
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key
```

Create the DB tables (run in Supabase SQL editor):

```sql
-- rooms
CREATE TABLE IF NOT EXISTS public.rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  active_playlist_id UUID,
  current_song_sequence INT,
  current_song_name TEXT,
  current_song_url TEXT,
  is_playing BOOLEAN NOT NULL DEFAULT false,
  current_position_seconds DOUBLE PRECISION NOT NULL DEFAULT 0,
  last_updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- playlist_songs
CREATE TABLE IF NOT EXISTS public.playlist_songs (
  playlist_id UUID NOT NULL,
  sequence INT NOT NULL,
  song_name TEXT NOT NULL,
  PRIMARY KEY (playlist_id, sequence)
);
```

Upload audio files to a Supabase Storage bucket (for example: `songs`).

Run the app:

```bash
flutter run
```

## Project structure
```
lib/
 sync_service.dart           # Core synchronization engine (host & listener)
 audio_player_service.dart   # just_audio wrapper / singleton player
 caching_service.dart        # Local caching and eviction
 music_service.dart          # Supabase storage / signed URL fetcher
 models/                     # Data models
 screens/                    # UI screens
 widgets/                    # Reusable components
```

## How it works

### Host flow
1. Host starts playback and sets room state (sequence, name, url, is_playing=true, pos=0, last_updated_at=now).
2. Host calls `startHostPositionUpdates(roomId)` and updates `rooms` every ~2 seconds with current position and timestamp.
3. On track completion: host loads the next track, updates `rooms` with a signed URL for listeners, and resumes playback.
4. Host can pre-cache next tracks and evict completed ones from cache.

### Listener flow
1. Listener calls `startHeartbeatSync(roomId)` and polls `rooms` (every ~5s by default).
2. If URL or sequence changed, listener loads the new URL and seeks to `current_position_seconds + (now - last_updated_at)`.
3. While playing, listeners correct drift only when deviation exceeds a threshold (default ~700ms).
4. Listeners pre-cache the next song (sequence + 1) where possible.

## Configuration
Adjust intervals and thresholds in `sync_service.dart`:

```dart
static const Duration _hostUpdateInterval = Duration(seconds: 2);
static const Duration _listenerSyncInterval = Duration(seconds: 5);
static const int _driftCorrectionThresholdMs = 700;
```

Cache settings (example):

```dart
static const int maxCacheSize = 500; // MB
static const Duration cacheRetention = Duration(days: 7);
```

## Permissions
**Android** (add to `android/app/src/main/AndroidManifest.xml`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<!-- For external storage (API < 29) -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

Prefer using app-internal storage to avoid extra permissions on modern Android.

**iOS** (add to `ios/Runner/Info.plist`):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs audio permissions for music playback</string>
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

## Building for production
- Android APK: `flutter build apk --release --split-per-abi`
- iOS App Store: `flutter build ios --release`
- Web (experimental): `flutter build web --release`

## Troubleshooting
**Sync not working**
- Check network & Supabase credentials
- Verify the `rooms` record exists and the `last_updated_at` field is recent

**Audio not playing**
- Check device volume & supported audio format
- Test with another audio file or direct URL

**High battery usage**
- Reduce sync frequency
- Consider background execution and platform-specific battery optimizations

## Contributing
1. Fork the repo
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes and push
4. Open a Pull Request

Please follow Dart style and run `flutter format` before committing.

## License & Support
This project is licensed under the MIT License. See `LICENSE` for details.

Support: support@beatsync.app

---

*If you'd like, I can add a `README` table of contents links, `.env.example`, or a `CONTRIBUTING.md` next.*
