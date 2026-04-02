import 'dart:convert';
import 'package:http/http.dart' as http;

class WikipediaService {
  // Fetch a summary of any Wikipedia article by search term
  Future<Map<String, String?>> getBuildingSummary(String buildingName) async {
    try {
      // First search for the article
      final searchUrl = Uri.parse(
        'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(buildingName)}',
      );

      final response = await http.get(searchUrl);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'title': data['title'] as String?,
          'summary': data['extract'] as String?,
          'imageUrl': data['thumbnail']?['source'] as String?,
          'pageUrl': data['content_urls']?['mobile']?['page'] as String?,
        };
      }

      // If exact match fails, try searching
      return await _searchAndFetch(buildingName);
    } catch (e) {
      return {
        'title': null,
        'summary': null,
        'imageUrl': null,
        'pageUrl': null,
      };
    }
  }

  // Search Wikipedia and get the first result's summary
  Future<Map<String, String?>> _searchAndFetch(String query) async {
    try {
      final searchUrl = Uri.parse(
        'https://en.wikipedia.org/w/api.php?action=opensearch&search=${Uri.encodeComponent(query)}&limit=1&format=json',
      );

      final searchResponse = await http.get(searchUrl);
      if (searchResponse.statusCode != 200) {
        return {
          'title': null,
          'summary': null,
          'imageUrl': null,
          'pageUrl': null,
        };
      }

      final searchData = json.decode(searchResponse.body);
      final titles = searchData[1] as List;
      if (titles.isEmpty) {
        return {
          'title': null,
          'summary': null,
          'imageUrl': null,
          'pageUrl': null,
        };
      }

      // Fetch the summary of the first search result
      final title = titles[0] as String;
      final summaryUrl = Uri.parse(
        'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title)}',
      );

      final summaryResponse = await http.get(summaryUrl);
      if (summaryResponse.statusCode == 200) {
        final data = json.decode(summaryResponse.body);
        return {
          'title': data['title'] as String?,
          'summary': data['extract'] as String?,
          'imageUrl': data['thumbnail']?['source'] as String?,
          'pageUrl': data['content_urls']?['mobile']?['page'] as String?,
        };
      }
    } catch (_) {}

    return {'title': null, 'summary': null, 'imageUrl': null, 'pageUrl': null};
  }
}
