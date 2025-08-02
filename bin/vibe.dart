import 'package:vibe/youtube_music_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('Usage: dart run bin/youtube_music_cli.dart "search query"');
    return;
  }

  final query = arguments.join(' ');
  final service = YouTubeMusicService();
  final yt = YoutubeExplode();

  print('Searching for: $query');
  print('─' * 50);

  try {
    final songs = await service.search(query);

    if (songs.isEmpty) {
      print('No songs found.');
      return;
    }

    for (int i = 0; i < songs.length && i < 10; i++) {
      final song = songs[i];
      print('${i + 1}. ${song['title']} - ${song['artist']}');

      // Optionally get stream URL
      if (song['videoId'] != null) {
        try {
          final manifest = await yt.videos.streamsClient.getManifest(
            song['videoId'],
          );
          final audioStream = manifest.audioOnly.withHighestBitrate();
          print('   Stream URL: ${audioStream.url}');
        } catch (e) {
          print('   Stream URL: Not available');
        }
      } else {
        print('   Stream URL: Not available');
      }
      print('');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    yt.close();
  }
}
