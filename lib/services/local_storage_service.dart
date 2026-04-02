import 'package:hive_flutter/hive_flutter.dart';

class LocalStorageService {
  static const String _bookmarksBox = 'bookmarks';

  Future<void> addBookmark(String buildingId) async {
    final box = await Hive.openBox(_bookmarksBox);
    await box.put(buildingId, DateTime.now().toIso8601String());
  }

  Future<void> removeBookmark(String buildingId) async {
    final box = await Hive.openBox(_bookmarksBox);
    await box.delete(buildingId);
  }

  Future<bool> isBookmarked(String buildingId) async {
    final box = await Hive.openBox(_bookmarksBox);
    return box.containsKey(buildingId);
  }

  Future<List<String>> getAllBookmarkIds() async {
    final box = await Hive.openBox(_bookmarksBox);
    return box.keys.cast<String>().toList();
  }
}
