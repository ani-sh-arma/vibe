import 'dart:io';
import 'package:vibe/youtube_music_service.dart';
import 'package:vibe/stream_provider.dart';

Future<bool> isCommandAvailable(String command) async {
  try {
    final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
      command,
    ], runInShell: true);
    return result.exitCode == 0;
  } catch (e) {
    return false;
  }
}

Future<void> _playStream(
  String urlToPlay, {
  String? title,
  String? artist,
}) async {
  if (title != null && artist != null) {
    print('Playing "$title" by $artist...');
  } else {
    print('Playing stream: $urlToPlay...');
  }

  final ffplayAvailable = await isCommandAvailable('ffplay');

  if (ffplayAvailable) {
    print(
      'Using ffplay to play the audio stream. Press "q" in the ffplay window to stop playback.',
    );
    print('Attempting to play audio with ffplay...');
    // Pass arguments as a list directly to avoid shell parsing issues with complex URLs
    final result = await Process.run('ffplay', [
      '-nodisp',
      '-autoexit',
      '-i', // Explicitly specify input
      urlToPlay, // Pass URL directly, no need for manual quoting here
    ], stdoutEncoding: SystemEncoding(), stderrEncoding: SystemEncoding()); // Removed runInShell: true

    stdout.write(result.stdout);
    stderr.write(result.stderr);

    print('ffplay exited with code: ${result.exitCode}');
    print('Vibe CLI exiting.'); // Confirmation message
  } else {
    print(
      'ffplay not found. Please install FFmpeg to play audio directly in the CLI.',
    );
    print('You can download FFmpeg from: https://ffmpeg.org/download.html');
    print('Alternatively, opening the URL in your default browser:');
    if (Platform.isWindows) {
      await Process.run('start', [urlToPlay], runInShell: true);
    } else if (Platform.isMacOS) {
      await Process.run('open', [urlToPlay]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [urlToPlay]);
    } else {
      print('Unsupported operating system for opening URL automatically.');
    }
  }
}

void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('Usage: dart run bin/vibe.dart "search query"');
    print('Or:    dart run bin/vibe.dart -p "stream_url"');
    return;
  }

  // Check for -p flag for direct playback
  if (arguments.length >= 2 && arguments[0] == '-p') {
    final streamUrl = arguments[1];
    await _playStream(streamUrl);
    return; // Exit after playing the stream
  }

  final query = arguments.join(' ');
  final service = YouTubeMusicService();

  print('Searching for: $query');
  print('─' * 50);

  try {
    final songs = await service.search(query);

    if (songs.isEmpty) {
      print('No songs found.');
      return;
    }

    final List<Map<String, dynamic>> playableSongs = [];

    for (int i = 0; i < songs.length && i < 10; i++) {
      final song = songs[i];
      if (song['videoId'] != null) {
        final streamProvider = await StreamProvider.fetch(song['videoId']);
        if (streamProvider.playable &&
            streamProvider.highestQualityAudio?.url != null) {
          playableSongs.add({
            'title': song['title'],
            'artist': song['artist'],
            'streamUrl': streamProvider.highestQualityAudio!.url,
          });
          print(
            '${playableSongs.length}. ${song['title']} - ${song['artist']}',
          );
          print('   Stream URL: ${streamProvider.highestQualityAudio!.url}');
          print('');
        } else {
          print('${i + 1}. ${song['title']} - ${song['artist']}');
          print('   Stream URL: Not available (${streamProvider.statusMSG})');
          print('');
        }
      } else {
        print('${i + 1}. ${song['title']} - ${song['artist']}');
        print('   Stream URL: Not available (No video ID)');
        print('');
      }
    }

    if (playableSongs.isEmpty) {
      print('No playable songs found with valid stream URLs.');
      return;
    }

    print('─' * 50);
    stdout.write(
      'Enter the number of the song you want to play (1-${playableSongs.length}): ',
    );
    final input = stdin.readLineSync();
    final selectedIndex = int.tryParse(input ?? '');

    if (selectedIndex == null ||
        selectedIndex < 1 ||
        selectedIndex > playableSongs.length) {
      print(
        'Invalid input. Please enter a number between 1 and ${playableSongs.length}.',
      );
      return;
    }

    final selectedSong = playableSongs[selectedIndex - 1];
    final urlToPlay = selectedSong['streamUrl'];

    await _playStream(
      urlToPlay,
      title: selectedSong['title'],
      artist: selectedSong['artist'],
    );
  } catch (e) {
    print('Error: $e');
  } finally {
    // yt.close(); // Handled by StreamProvider
  }
}
