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
  int? durationMs,
  String? videoId, // Add videoId for re-fetching streams
}) async {
  if (title != null && artist != null) {
    print('Playing "$title" by $artist...');
  } else {
    print('Playing stream: $urlToPlay...');
  }

  final ffplayAvailable = await isCommandAvailable('ffplay');

  if (ffplayAvailable) {
    await _playWithFFplay(urlToPlay, durationMs, videoId, title, artist);
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

Future<void> _playWithFFplay(
  String urlToPlay,
  int? durationMs,
  String? videoId,
  String? title,
  String? artist,
) async {
  int retryCount = 0;
  const maxRetries = 3;
  String currentUrl = urlToPlay;

  while (retryCount <= maxRetries) {
    if (retryCount > 0) {
      print(
        '\nRetrying playback (attempt ${retryCount + 1}/${maxRetries + 1})...',
      );

      // Try to get a fresh stream URL if we have videoId
      if (videoId != null) {
        print('Fetching fresh stream URL...');
        try {
          final streamProvider = await StreamProvider.fetch(videoId);
          if (streamProvider.playable &&
              streamProvider.highestQualityAudio?.url != null) {
            currentUrl = streamProvider.highestQualityAudio!.url;
            print('Got fresh stream URL');
          } else {
            print(
              'Failed to get fresh stream URL: ${streamProvider.statusMSG}',
            );
          }
        } catch (e) {
          print('Error fetching fresh stream URL: $e');
        }
      }

      // Wait a bit before retrying
      await Future.delayed(Duration(seconds: 2));
    }

    print('Attempting to play audio with ffplay...');

    final process = await Process.start('ffplay', [
      '-nodisp',
      '-autoexit',
      '-reconnect',
      '1',
      '-reconnect_at_eof',
      '1',
      '-reconnect_streamed',
      '1',
      '-reconnect_delay_max',
      '5',
      '-i',
      currentUrl,
    ]);

    bool hasError = false;
    bool isPlaying = false;

    // Listen to stderr for progress updates and errors
    process.stderr.transform(SystemEncoding().decoder).listen((data) {
      // Check for network errors
      if (data.contains('Error in the pull function') ||
          data.contains('IO error') ||
          data.contains('Connection reset') ||
          data.contains('session has been invalidated')) {
        hasError = true;
        if (!isPlaying) {
          stderr.write(data); // Show error if we haven't started playing yet
        }
        return;
      }

      final regex = RegExp(r'A:\s*(\d+\.\d+)\s*');
      final match = regex.firstMatch(data);
      if (match != null) {
        isPlaying = true;
        final currentTime = double.parse(match.group(1)!);
        final totalDurationSeconds = (durationMs ?? 0) / 1000;
        String progress = '';
        if (totalDurationSeconds > 0) {
          final currentMinutes = (currentTime ~/ 60).toString().padLeft(2, '0');
          final currentSeconds = (currentTime % 60).toInt().toString().padLeft(
            2,
            '0',
          );
          final totalMinutes = (totalDurationSeconds ~/ 60).toString().padLeft(
            2,
            '0',
          );
          final totalSeconds = (totalDurationSeconds % 60)
              .toInt()
              .toString()
              .padLeft(2, '0');
          progress =
              '(${currentMinutes}:${currentSeconds} / ${totalMinutes}:${totalSeconds})';
        }
        stdout.write('\rPlaying... ${progress} '); // Use \r to overwrite line
      } else if (!isPlaying) {
        // Only show other stderr output if we're not playing (to avoid spam)
        stderr.write(data);
      }
    });

    // Listen to stdout for other messages
    process.stdout.transform(SystemEncoding().decoder).listen((data) {
      stdout.write(data);
    });

    final exitCode = await process.exitCode;
    print('\nffplay exited with code: $exitCode');

    // If playback completed successfully (exit code 0) or user interrupted, don't retry
    if (exitCode == 0 || exitCode == 255) {
      break;
    }

    // If we had network errors and haven't exceeded retry limit, try again
    if (hasError && retryCount < maxRetries) {
      retryCount++;
      print('Network error detected, will retry...');
      continue;
    }

    // If no error or exceeded retry limit, break
    break;
  }

  if (retryCount > maxRetries) {
    print('Max retries exceeded. Playback failed.');
  }

  stdout.write('Press Enter to exit Vibe CLI: '); // Prompt to keep CLI open
  stdin.readLineSync(); // Keep the Dart program alive until user presses Enter
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
            'videoId': song['videoId'], // Store videoId for re-fetching
            'streamUrl': streamProvider.highestQualityAudio!.url,
            'durationMs': streamProvider.highestQualityAudio!.duration,
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
      durationMs: selectedSong['durationMs'],
      videoId: selectedSong['videoId'], // Pass videoId for re-fetching
    );
  } catch (e) {
    print('Error: $e');
  } finally {
    // yt.close(); // Handled by StreamProvider
  }
}
