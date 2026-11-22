/// 项目文件管理：一个 `.gala.json` 就是一个项目。
/// 桌面/移动端都用应用私有目录，导出时再交给用户。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/graph.dart';

class ProjectStore {
  static Directory? _cached;

  static Future<Directory> dir() async {
    if (_cached != null) return _cached!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/galatea_projects');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    _cached = d;
    return d;
  }

  static String fileNameFor(String title) {
    final safe = title.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5-]'), '_');
    final name = safe.isEmpty ? 'untitled' : safe;
    return '$name.gala.json';
  }

  static Future<List<File>> list() async {
    final d = await dir();
    final files = d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gala.json'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  static Future<File> save(Story story, {String? fileName}) async {
    final d = await dir();
    final name = fileName ?? fileNameFor(story.title);
    final f = File('${d.path}/$name');
    await f.writeAsString(story.toPrettyJson(), flush: true);
    return f;
  }

  static Future<Story> load(File f) async {
    final text = await f.readAsString();
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('剧本文件不是 JSON 对象');
    }
    return Story.fromJson(Map<String, dynamic>.from(decoded));
  }

  static Future<void> delete(File f) async {
    if (await f.exists()) await f.delete();
  }

  /// 从一段 JSON 文本导入（手机/桌面上都能用，不依赖文件选择器）
  static Future<File> importText(String text, {String? titleHint}) async {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('不是 JSON 对象');
    }
    final story = Story.fromJson(Map<String, dynamic>.from(decoded));
    if (titleHint != null && titleHint.isNotEmpty) {
      story.title = titleHint;
    }
    return save(story);
  }

  static Future<File> exportTo(Story story, Directory target) async {
    if (!await target.exists()) await target.create(recursive: true);
    final f = File('${target.path}/${fileNameFor(story.title)}');
    await f.writeAsString(story.toPrettyJson(), flush: true);
    return f;
  }
}