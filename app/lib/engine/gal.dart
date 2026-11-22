/// `.gal` 作品包 —— Dart 版读写（与 Rust 的 `gal.rs` 字节级兼容）。
///
/// 只用 `dart:io` 的 raw zlib，不引第三方包。
///
/// ```text
/// magic "GAL\x01" │ version u16 │ flags u16 │ count u32 │ index_len u32
/// 索引： name_len u16 │ name │ method u8 │ offset u64 │ csize u64 │ usize u64 │ crc32 u32
/// 数据： 各条目按索引顺序紧密排列
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const List<int> kGalMagic = [0x47, 0x41, 0x4C, 0x01]; // "GAL\x01"
const int kGalVersion = 1;

/// 已经是压缩格式、再压没意义的扩展名（与 Rust 侧保持一致）
bool _precompressed(String name) {
  final l = name.toLowerCase();
  const exts = [
    '.png', '.jpg', '.jpeg', '.webp', '.gif', '.avif',
    '.mp3', '.ogg', '.opus', '.m4a', '.mp4', '.zip', '.gal'
  ];
  return exts.any(l.endsWith);
}

// ------------------------------------------------------------------ crc32

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[i] = c;
  }
  return t;
}();

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

// ------------------------------------------------------------------ 压缩

Uint8List _deflate(List<int> data) {
  final out = ZLibEncoder(raw: true, level: 9).convert(data);
  return Uint8List.fromList(out);
}

Uint8List _inflate(List<int> data) {
  final out = ZLibDecoder(raw: true).convert(data);
  return Uint8List.fromList(out);
}

// ------------------------------------------------------------------ 条目

class GalEntry {
  final String name;
  final int method; // 0 = 原样, 1 = deflate
  final int offset;
  final int csize;
  final int usize;
  final int crc;

  GalEntry(this.name, this.method, this.offset, this.csize, this.usize, this.crc);

  double get ratio => usize == 0 ? 1.0 : csize / usize;

  Map<String, Object?> toJson() => {
        'name': name,
        'method': method == 1 ? 'deflate' : '原样',
        'size': usize,
        'packed': csize,
        'ratio': '${(ratio * 100).toStringAsFixed(1)}%',
      };
}

class GalArchive {
  final List<GalEntry> entries;
  final Uint8List data;

  GalArchive(this.entries, this.data);

  int get totalRaw => entries.fold(0, (a, e) => a + e.usize);
  int get totalPacked => entries.fold(0, (a, e) => a + e.csize);

  String get storyName {
    if (entries.any((e) => e.name == 'story.gala.json')) return 'story.gala.json';
    return entries.firstWhere(
      (e) => e.name.endsWith('.json'),
      orElse: () => throw const FormatException('包里没有剧本'),
    ).name;
  }

  static GalArchive parse(Uint8List bytes) {
    if (bytes.length < 16) throw const FormatException('文件太短，不是 .gal');
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != kGalMagic[i]) throw const FormatException('不是 .gal 文件');
    }
    final bd = ByteData.sublistView(bytes);
    final ver = bd.getUint16(4, Endian.little);
    if (ver != kGalVersion) throw FormatException('不支持的 .gal 版本：$ver');
    final count = bd.getUint32(8, Endian.little);
    final indexLen = bd.getUint32(12, Endian.little);
    final dataStart = 16 + indexLen;
    if (bytes.length < dataStart) throw const FormatException('索引区越界');

    var p = 16;
    final entries = <GalEntry>[];
    for (var i = 0; i < count; i++) {
      if (p + 2 > dataStart) throw const FormatException('索引损坏');
      final nl = bd.getUint16(p, Endian.little);
      p += 2;
      if (p + nl + 29 > dataStart) throw const FormatException('索引损坏');
      final name = utf8.decode(bytes.sublist(p, p + nl), allowMalformed: true);
      p += nl;
      final method = bytes[p];
      p += 1;
      final offset = bd.getUint64(p, Endian.little);
      final csize = bd.getUint64(p + 8, Endian.little);
      final usize = bd.getUint64(p + 16, Endian.little);
      final crc = bd.getUint32(p + 24, Endian.little);
      p += 28;
      entries.add(GalEntry(name, method, offset, csize, usize, crc));
    }
    return GalArchive(entries, Uint8List.sublistView(bytes, dataStart));
  }

  static GalArchive fromFile(File f) => parse(f.readAsBytesSync());

  Uint8List read(String name) {
    final e = entries.firstWhere(
      (x) => x.name == name,
      orElse: () => throw FormatException('包里没有 `$name`'),
    );
    final start = e.offset.toInt();
    final end = start + e.csize.toInt();
    if (end > data.length) throw FormatException('`$name` 数据越界');
    final raw = e.method == 0
        ? Uint8List.fromList(data.sublist(start, end))
        : _inflate(data.sublist(start, end));
    if (raw.length != e.usize) throw FormatException('`$name` 长度不符');
    if (crc32(raw) != e.crc) throw FormatException('`$name` 校验失败（文件损坏）');
    return raw;
  }

  Map<String, Uint8List> readAll() =>
      {for (final e in entries) e.name: read(e.name)};

  /// 取出剧本原文（池化编码的 JSON 文本）
  String readStoryRaw() => utf8.decode(read(storyName));
}

/// 把一组文件打成 .gal 字节
Uint8List galPack(Map<String, List<int>> files) {
  final names = files.keys.toList()..sort();
  final entries = <GalEntry>[];
  final blobs = BytesBuilder();

  for (final name in names) {
    final raw = files[name]!;
    int method;
    List<int> body;
    if (_precompressed(name) || raw.length < 64) {
      method = 0;
      body = raw;
    } else {
      final packed = _deflate(raw);
      if (packed.length + 8 >= raw.length) {
        method = 0;
        body = raw;
      } else {
        method = 1;
        body = packed;
      }
    }
    entries.add(
        GalEntry(name, method, blobs.length, body.length, raw.length, crc32(raw)));
    blobs.add(body);
  }

  final index = BytesBuilder();
  for (final e in entries) {
    final nb = utf8.encode(e.name);
    index.add((ByteData(2)..setUint16(0, nb.length, Endian.little))
        .buffer
        .asUint8List());
    index.add(nb);
    index.addByte(e.method);
    for (final v in [e.offset, e.csize, e.usize]) {
      index.add((ByteData(8)..setUint64(0, v, Endian.little))
          .buffer
          .asUint8List());
    }
    index.add((ByteData(4)..setUint32(0, e.crc, Endian.little))
        .buffer
        .asUint8List());
  }
  final indexBytes = index.toBytes();
  final dataBytes = blobs.toBytes();

  final out = BytesBuilder();
  out.add(kGalMagic);
  out.add((ByteData(2)..setUint16(0, kGalVersion, Endian.little))
      .buffer
      .asUint8List());
  out.add((ByteData(2)..setUint16(0, 0, Endian.little)).buffer.asUint8List());
  out.add((ByteData(4)..setUint32(0, entries.length, Endian.little))
      .buffer
      .asUint8List());
  out.add((ByteData(4)..setUint32(0, indexBytes.length, Endian.little))
      .buffer
      .asUint8List());
  out.add(indexBytes);
  out.add(dataBytes);
  return out.toBytes();
}

// ------------------------------------------------------- 池化编码的还原

/// 还原 compact.rs 的字符串池化格式；普通文档原样返回
dynamic compactUnpack(dynamic wrapped) {
  if (wrapped is Map &&
      wrapped[r'$gal'] != null &&
      wrapped['pool'] is List &&
      wrapped.containsKey('doc')) {
    final pool = (wrapped['pool'] as List).map((e) => '$e').toList();
    return _expand(wrapped['doc'], pool);
  }
  return wrapped;
}

dynamic _expand(dynamic node, List<String> pool) {
  if (node is Map) {
    if (node.length == 1 && node[r'$s'] is num) {
      final i = (node[r'$s'] as num).toInt();
      if (i < 0 || i >= pool.length) throw FormatException('池引用 $i 越界');
      return pool[i];
    }
    return {for (final e in node.entries) e.key: _expand(e.value, pool)};
  }
  if (node is List) return [for (final v in node) _expand(v, pool)];
  return node;
}

/// 把文档压成池化格式（与 compact.rs 同构）
dynamic compactPack(dynamic doc) {
  final counts = <String, int>{};
  void walk(dynamic node) {
    if (node is String) {
      if (node.runes.length >= 3) counts[node] = (counts[node] ?? 0) + 1;
    } else if (node is List) {
      node.forEach(walk);
    } else if (node is Map) {
      node.values.forEach(walk);
    }
  }

  walk(doc);
  final candidates = counts.entries
      .where((e) => e.value >= 2 && e.key.runes.length >= 3)
      .toList()
    ..sort((a, b) {
      final sa = a.key.length * a.value - a.value * 6 - a.key.length;
      final sb = b.key.length * b.value - b.value * 6 - b.key.length;
      return sb.compareTo(sa);
    });
  final pool = <String>[];
  final map = <String, int>{};
  for (final e in candidates) {
    map[e.key] = pool.length;
    pool.add(e.key);
  }

  dynamic replace(dynamic node) {
    if (node is String) {
      final i = map[node];
      return i == null ? node : {r'$s': i};
    }
    if (node is List) return [for (final v in node) replace(v)];
    if (node is Map) {
      return {for (final e in node.entries) e.key: replace(e.value)};
    }
    return node;
  }

  return {r'$gal': 1, 'pool': pool, 'doc': replace(doc)};
}