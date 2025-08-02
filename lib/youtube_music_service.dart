import 'package:dio/dio.dart';

class YouTubeMusicService {
  final Dio _dio = Dio();

  static const String domain = "https://music.youtube.com/";
  static const String baseUrl = '${domain}youtubei/v1/';
  static const String fixedParams = '?prettyPrint=false&alt=json&key=AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

  final Map<String, String> _headers = {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
    'accept': '*/*',
    'accept-encoding': 'gzip, deflate',
    'content-type': 'application/json',
    'origin': domain,
    'cookie': 'CONSENT=YES+1',
  };

  final Map<String, dynamic> _context = {
    'context': {
      'client': {
        "clientName": "WEB_REMIX",
        "clientVersion": "1.20230213.01.00",
      },
      'user': {}
    }
  };

  Future<Response> _sendRequest(String action, Map<dynamic, dynamic> data) async {
    try {
      final response = await _dio.post(
        "$baseUrl$action$fixedParams",
        options: Options(headers: _headers),
        data: data,
      );
      return response;
    } catch (e) {
      print('Request failed: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    final data = Map.from(_context);
    data['query'] = query;

    final response = await _sendRequest('search', data);

    // Parse search results (simplified)
    final contents = response.data['contents']['tabbedSearchResultsRenderer']
        ['tabs'][0]['tabRenderer']['content']['sectionListRenderer']['contents'];

    List<Map<String, dynamic>> songs = [];

    for (var section in contents) {
      if (section['musicShelfRenderer'] != null) {
        final items = section['musicShelfRenderer']['contents'];
        for (var item in items) {
          if (item['musicResponsiveListItemRenderer'] != null) {
            final song = _parseSong(item['musicResponsiveListItemRenderer']);
            if (song != null) songs.add(song);
          }
        }
      }
    }

    return songs;
  }

  Map<String, dynamic>? _parseSong(Map<String, dynamic> item) {
    try {
      final flexColumns = item['flexColumns'];
      if (flexColumns == null || flexColumns.length < 2) return null;

      // Extract title
      final titleRuns = flexColumns[0]['musicResponsiveListItemFlexColumnRenderer']
          ['text']['runs'];
      final title = titleRuns[0]['text'];

      // Extract artist
      final artistRuns = flexColumns[1]['musicResponsiveListItemFlexColumnRenderer']
          ['text']['runs'];
      final artist = artistRuns.length > 0 ? artistRuns[0]['text'] : 'Unknown';

      // Extract video ID
      final videoId = item['playNavigationEndpoint']?['watchEndpoint']?['videoId'];

      return {
        'title': title,
        'artist': artist,
        'videoId': videoId,
      };
    } catch (e) {
      return null;
    }
  }
}
