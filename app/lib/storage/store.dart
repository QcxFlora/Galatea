/// 书柜：应用私有目录里放 `.gal` 作品包。
///
/// 一个 `.gal` 就是一个作品（剧本 + 立绘 + 脚本全在里面），
/// 所以书柜只需要扫这一个目录，不需要管散落的 json / png。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../engine/gal.dart';
import '../models/graph.dart';

/// 打开后缓存下来的作品：剧本 + 里面的资源（立绘等）
class LoadedProject {
  final Story story;
  final File file;
  /// 除剧本以外的条目（assets/xxx.webp 等），保存时原样写回
  final Map<String, Uint8List> assets;

  const LoadedProject({
    required this.story,
    required this.file,
    required this.assets,
  });

  String get name => file.uri.pathSegments.last;
  int get assetCount => assets.length;
}

class ProjectStore {
  static Directory? _cached;

  static Future<Directory> dir() async {
    if (_cached != null) return _cached!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/shelf');
    if (!await d.exists()) await d.create(recursive: true);
    _cached = d;
    return d;
  }

  static String fileNameFor(String title) {
    final safe = title.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5\-]'), '_');
    final name = safe.isEmpty ? 'untitled' : safe;
    return '$name.gal';
  }

  /// 书柜上的所有作品
  static Future<List<File>> listGal() async {
    final d = await dir();
    final files = d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.gal'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// 只读标题（书脊用）。
  ///
  /// **坏了就抛**——不在这一层假装"还行"。
  /// 调用方（书柜）负责把它显示成红色「损坏」条目并给出具体原因。
  static String titleOf(File f) {
    final arc = GalArchive.fromFile(f);
    final raw = arc.readStoryRaw();
    final doc = compactUnpack(jsonDecode(raw));
    if (doc is! Map) {
      throw FormatException('${f.path} 的剧本不是 JSON 对象');
    }
    final meta = doc['meta'];
    if (meta is Map && meta['title'] is String) {
      final t = (meta['title'] as String).trim();
      if (t.isNotEmpty) return t;
    }
    throw FormatException('${f.path} 缺少 meta.title');
  }

  /// 打开一个作品
  static Future<LoadedProject> open(File f) async {
    final arc = GalArchive.fromFile(f);
    final raw = arc.readStoryRaw();
    final doc = compactUnpack(jsonDecode(raw));
    if (doc is! Map) throw const FormatException('剧本不是 JSON 对象');
    final story = Story.fromJson(Map<String, dynamic>.from(doc));
    final assets = <String, Uint8List>{};
    for (final e in arc.entries) {
      if (e.name == arc.storyName) continue;
      assets[e.name] = arc.read(e.name);
    }
    return LoadedProject(story: story, file: f, assets: assets);
  }

  /// 保存（重新打包成 .gal）
  static Future<File> save(LoadedProject p, {String? fileName}) async {
    final d = await dir();
    final name = fileName ?? p.file.uri.pathSegments.last;
    final f = File('${d.path}/$name');

    final storyJson = p.story.toJson();
    final pooled = compactPack(storyJson);
    final files = <String, List<int>>{
      'story.gala.json': utf8.encode(jsonEncode(pooled)),
    };
    p.assets.forEach((k, v) => files[k] = v);

    await f.writeAsBytes(galPack(files), flush: true);
    return f;
  }

  /// 新建：给一份空剧本，资源为空
  static Future<LoadedProject> create(String title) async {
    final d = await dir();
    final story = Story.blank(title);
    final f = File('${d.path}/${fileNameFor(title)}');
    final p = LoadedProject(
      story: story,
      file: f,
      assets: const {},
    );
    await save(p);
    return p;
  }

  /// 从文件管理器选进来的 .gal：校验后复制到书柜
  static Future<LoadedProject> importFrom(File src) async {
    final arc = GalArchive.fromFile(src); // 校验魔数/索引/CRC 会在 read 时抛
    arc.readStoryRaw(); // 提前验证剧本可读
    final d = await dir();
    var name = src.uri.pathSegments.last;
    if (!name.toLowerCase().endsWith('.gal')) name = '$name.gal';
    final dst = File('${d.path}/$name');
    await src.copy(dst.path);
    return open(dst);
  }

  static Future<void> delete(File f) async {
    if (await f.exists()) await f.delete();
  }

  /// 把作品包导出到外部目录（分享给别人）
  static Future<File> exportTo(File f, Directory target) async {
    if (!await target.exists()) await target.create(recursive: true);
    final dst = File('${target.path}/${f.uri.pathSegments.last}');
    return f.copy(dst.path);
  }

  /// 打开示例：把 assets 内置的 .gal 复制到书柜（只装一次）
  static Future<LoadedProject> installSample(
      String packedAsset, String fileName) async {
    final d = await dir();
    final f = File('${d.path}/$fileName');
    if (!await f.exists()) {
      final data = await rootBundle.load(packedAsset);
      await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return open(f);
  }
}