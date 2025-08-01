beat_sync
A Flutter app for synchronized music playback across multiple devices using Supabase and just_audio. One device acts as the host; others join as listeners. Playback state, timing, and playlist progression are shared via Supabase.
Tech stack
Flutter + Dart
just_audio for playback
Supabase (Database + Storage) for realtime state and song URLs
Optional local caching for faster playback and reduced bandwidth
Project structure
lib/sync_service.dart — Core sync engine for host and listeners (heartbeat, position updates, completion handling, pre-caching).
lib/audio_player_service.dart — Centralized just_audio player wrapper. Provides a singleton AudioPlayer.
lib/caching_service.dart — Manages local song caching & retrieval, and cleanup.
lib/music_service.dart — Fetches signed download URLs from Supabase Storage for song names.
README.md — Project docs.
Note: Only lib/sync_service.dart is provided here. The other services are referenced by the sync flow and must exist in the project.
Data model & Supabase
Expected tables and columns:
rooms
id (uuid or text, primary key)
active_playlist_id (uuid or text)
current_song_sequence (int)
current_song_name (text)
current_song_url (text) — listener playback URL (signed)
is_playing (bool)
current_position_seconds (float)
last_updated_at (timestamptz in UTC)
playlist_songs
playlist_id (uuid or text)
sequence (int, 1-based or 0-based consistently)
song_name (text) — storage object key or canonical name
Example minimal SQL:
-- rooms
create table if not exists public.rooms (
id uuid primary key default gen_random_uuid(),
active_playlist_id uuid,
current_song_sequence int,
current_song_name text,
current_song_url text,
is_playing boolean not null default false,
current_position_seconds double precision not null default 0,
last_updated_at timestamptz
);

-- playlist_songs
create table if not exists public.playlist_songs (
playlist_id uuid not null,
sequence int not null,
song_name text not null,
primary key (playlist_id, sequence)
);
Core workflow
Host device
Starts playback locally, calls startHostPositionUpdates(roomId).
Every 2s, pushes position and timestamp to rooms.
On track completion, _playNextSong():
Pauses globally, clears URL to let listeners pause.
Looks up next song by sequence + 1 in playlist_songs.
Optionally evicts completed song from cache and pre-caches the next-next song.
Fetches a signed URL for listeners, updates rooms state & resumes is_playing.
Sets up local playback source (cached file path or network URL) and restarts position updates.
Listener device
Calls startHeartbeatSync(roomId).
Every 5s, pulls rooms state and runs syncListenerPlayer(...).
If URL changed or initial sync:
Loads the new URL, seeks using current_position_seconds + (now \- last_updated_at).
Plays or pauses per is_playing.
While playing, corrects drift if deviation > ~700ms.
Pre-caches the next song based on active_playlist_id and current_song_sequence.
Timing & drift handling
Host writes current_position_seconds and last_updated_at (UTC) periodically.
Listeners compute latency now \- last_updated_at and seek to position + latency.
Drift correction seeks only if deviation crosses a 700ms threshold.
Caching strategy
On listeners: pre-cache sequence + 1 song when possible.
On host: after a song completes, remove completed song from cache; pre-cache sequence + 2.
Playback source preference:
If cached path exists, use local file.
Otherwise, fetch signed URL and stream.
Requires storage permissions on Android if writing to external storage.
Android example permission (if your cache writes outside app sandbox):
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
Prefer app-internal storage to avoid permissions on modern Android.
Initialization & usage
Initialize Supabase early in app startup.
Ensure AudioPlayerService.instance.player is ready (single instance).
Use the SyncService singleton.
// Example: host flow
final roomId = '...';
final sync = SyncService();

// When host taps Play on a selected song:
// 1) Host sets initial room state (sequence, name, URL, is_playing=true, pos=0, last_updated_at=now)
// 2) Then start position updates:
sync.startHostPositionUpdates(roomId);

// On host pause/stop:
sync.stopHostPositionUpdates();

// Example: listener flow
sync.startHeartbeatSync(roomId);

// On leaving the room:
sync.stopHeartbeatSync();
Screens & responsibilities
The repository does not include UI code. A typical mapping:
RoomListScreen — Discover or enter a room ID.
HostControlsScreen — Select playlist, start/pause, skip; shows current position and sequence.
ListenerScreen — Displays current song and play state; handles join/leave.
PlaylistScreen — Manage playlist_songs order and membership.
Wire these screens to call SyncService APIs and update rooms table accordingly.
Environment setup
Install Flutter SDK and Dart.
flutter pub get
Configure Supabase:
Create the rooms and playlist_songs tables.
Upload audio files to Supabase Storage.
Implement MusicService.fetchSignedUrl(songName) to return time-limited URLs.
Ensure CachingService reads/writes within app storage and exposes:
cacheSong(name), getCachedSongPath(name), removeSongFromCache(name)
Build & run (Windows)
Debug: flutter run
Release APK: flutter build apk
Clean: flutter clean && flutter pub get
Error handling & safeguards
All timers are canceled on stop to prevent leaks.
Listener sync is guarded by _isSyncing to avoid overlapping pulls.
Seek positions are clamped to >= 0.
Drift corrections are throttled with a threshold.
Network errors are caught and logged; heartbeats continue.
Known limitations
Heartbeat is pull-based (5s). For tighter sync, add Supabase Realtime or shorter intervals.
Clock skew between devices is assumed negligible for the latency estimate.
Requires consistent sequence numbering in playlist_songs.
Contributions
Keep SyncService stateless regarding UI.
Avoid multiple AudioPlayer instances.
Validate Supabase writes and handle offline scenarios gracefully.