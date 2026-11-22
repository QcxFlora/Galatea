/// 从 Flutter 把作品交给 Godot 运行时。
///
/// Flutter 是编辑器；真正的 3D 演出跑在 Godot 里。
/// 桥接方式（按平台）：
///   · Android：把 .gal 拷到共享目录，用 ACTION_VIEW 交给已安装的 Galatea 运行时
///   · 桌面：直接 spawn 一个 `godot --path <runtime> -- <gal>` 进程
///   · 兜底：复制到剪贴板路径，提示用户手动打开
///
/// 这样两个 APK 可以独立升级：编辑器换皮肤不影响游戏，游戏换引擎不影响编辑器。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class GameLauncher {
  static const MethodChannel _channel = MethodChannel('galatea/game');

  /// 把作品导出到运行时可读的位置，返回落地路径
  static Future<String?> stage(String galPath) async {
    final src = File(galPath);
    if (!await src.exists()) return null;

    if (Platform.isAndroid) {
      // 共享目录：Godot 运行时（或用户手动）从这里读取
      final dir = Directory('/storage/emulated/0/Download/Galatea');
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (_) {
          return null;
        }
      }
      final dst = File('${dir.path}/${src.uri.pathSegments.last}');
      try {
        await src.copy(dst.path);
        return dst.path;
      } catch (_) {
        return null;
      }
    }
    return src.path;
  }

  /// 启动 Godot 运行时
  static Future<bool> launch(String galPath) async {
    final staged = await stage(galPath);
    if (staged == null) return false;

    // 1) 原生侧有实现就用原生（Android 上走 Intent，桌面走 spawn）
    try {
      final ok = await _channel.invokeMethod<bool>('launchGame', {
        'path': staged,
      });
      if (ok == true) return true;
    } on MissingPluginException {
      // 没实现就继续往下
    } on PlatformException catch (e) {
      debugPrint('launchGame 失败：${e.message}');
    }

    // 2) 桌面：找得到 godot 就直接起
    if (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      final candidates = ['godot', 'godot4', 'Godot'];
      for (final bin in candidates) {
        try {
          await Process.start(bin, ['--path', 'godot', '--', staged],
              mode: ProcessStartMode.detached);
          return true;
        } catch (_) {
          continue;
        }
      }
    }

    // 3) 兜底：把路径复制到剪贴板
    await Clipboard.setData(ClipboardData(text: staged));
    return false;
  }

  /// 导出作品包（给"分享给别人的运行时"用）
  static Future<String?> exportToDownloads(String galPath) async {
    final src = File(galPath);
    if (!await src.exists()) return null;
    final dir = Directory(Platform.isAndroid
        ? '/storage/emulated/0/Download/Galatea'
        : '${Directory.systemTemp.path}/Galatea');
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      final dst = File('${dir.path}/${src.uri.pathSegments.last}');
      await src.copy(dst.path);
      return dst.path;
    } catch (e) {
      debugPrint('导出失败：$e');
      return null;
    }
  }
}

/// 便捷：从书柜直接开一局 Godot 版的
Future<String> launchWithProject(String galPath) async {
  final ok = await GameLauncher.launch(galPath);
  if (ok) return '已启动 Godot 运行时';
  final where = await GameLauncher.exportToDownloads(galPath);
  return where == null ? '启动失败' : '运行时不可用，作品已导出到：$where';
}

/// 给 UI 用的：当前作品是否可以直接交给 Godot
Future<bool> hasGodotRuntime() async {
  try {
    final v = await GameLauncher._channel.invokeMethod<bool>('hasRuntime');
    return v ?? false;
  } catch (_) {
    return false;
  }
}

/// 复用 store 里的扩展名判断，避免两处写死
bool looksLikeGal(String path) => path.toLowerCase().endsWith('.gal');
