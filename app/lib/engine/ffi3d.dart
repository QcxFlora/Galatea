/// Flutter 独占显示层的 3D 视图。
///
/// # 为什么这么设计
///
/// 一个 APK 里只允许**一个**东西往屏幕上画。Godot 在 Android 上默认会
/// 自己开 SurfaceView，和 Flutter 抢 GL 上下文 —— 这就是你提到的"打架"。
///
/// 所以把职责拆开：
///
/// ```
///   Godot（headless / libgodot）  只跑逻辑：场景树、物理、GDScript 小游戏
///              │  通过共享内存或 GDExtension 调用传"状态"
///              ▼
///   galatea-3d（Rust cdylib）     把状态变成像素（本文件通过 dart:ffi 调它）
///              │  直接给一块 RGBA
///              ▼
///   Flutter                       唯一的显示层（RawImage）
/// ```
///
/// 好处：只有一个渲染出口、只有一个 GL 上下文、只有一个 SurfaceView；
/// Godot 挂掉不会把 UI 拖死，UI 也能在任何时候盖在 3D 上（浮层、按钮、字幕）。
///
/// # 加载
///
/// ```text
/// Android: android/app/src/main/jniLibs/arm64-v8a/libgalatea_3d.so
/// Linux:   /usr/local/lib/libgalatea_3d.so 或同目录
/// ```
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

// ---------------------------------------------------------------- C ABI

typedef _NewC = ffi.Pointer<ffi.Void> Function(ffi.Int32, ffi.Int32);
typedef _NewD = ffi.Pointer<ffi.Void> Function(int, int);

typedef _Void1C = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _Void1D = void Function(ffi.Pointer<ffi.Void>);

typedef _AddC = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>,
    ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Float, ffi.Uint32);
typedef _AddD = void Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>,
    ffi.Pointer<ffi.Uint8>, double, double, double, double, double, double, int);

typedef _NameF3C = ffi.Void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, ffi.Float, ffi.Float, ffi.Float);
typedef _NameF3D = void Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Uint8>, double, double, double);

typedef _CamC = ffi.Void Function(ffi.Pointer<ffi.Void>, ffi.Float, ffi.Float,
    ffi.Float, ffi.Float, ffi.Float, ffi.Float);
typedef _CamD = void Function(
    ffi.Pointer<ffi.Void>, double, double, double, double, double, double);

typedef _RenderC = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _RenderD = int Function(ffi.Pointer<ffi.Void>);

typedef _PixC = ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>);
typedef _PixD = ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>);

typedef _Int1C = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _Int1D = int Function(ffi.Pointer<ffi.Void>);

/// 轻量封装：一个引擎实例
class Gal3D {
  final ffi.Pointer<ffi.Void> _h;
  final int width;
  final int height;

  late final _AddD _add;
  late final _NameF3D _setPos;
  late final _NameF3D _setRot;
  late final _CamD _setCam;
  late final _RenderD _render;
  late final _PixD _pixels;
  late final _Void1D _clear;

  Gal3D._(this._h, this.width, this.height, ffi.DynamicLibrary lib) {
    _add = lib.lookupFunction<_AddC, _AddD>('g3d_add');
    _setPos = lib.lookupFunction<_NameF3C, _NameF3D>('g3d_set_position');
    _setRot = lib.lookupFunction<_NameF3C, _NameF3D>('g3d_set_rotation');
    _setCam = lib.lookupFunction<_CamC, _CamD>('g3d_set_camera');
    _render = lib.lookupFunction<_RenderC, _RenderD>('g3d_render');
    _pixels = lib.lookupFunction<_PixC, _PixD>('g3d_pixels');
    _clear = lib.lookupFunction<_Void1C, _Void1D>('g3d_clear');
  }

  static ffi.DynamicLibrary? _lib;

  static bool get available => _lib != null;

  /// 尝试加载原生库；失败返回 null（UI 侧要能优雅退化成占位）
  static Gal3D? create(int width, int height) {
    final lib = _lib ??= _open();
    if (lib == null) return null;
    final f = lib.lookupFunction<_NewC, _NewD>('g3d_new');
    final h = f(width, height);
    if (h == ffi.nullptr) return null;
    return Gal3D._(h, width, height, lib);
  }

  static ffi.DynamicLibrary? _open() {
    const candidates = [
      'libgalatea_3d.so',
      'libgalatea_3d.dylib',
      'galatea_3d.dll',
    ];
    for (final name in candidates) {
      try {
        return ffi.DynamicLibrary.open(name);
      } catch (_) {
        continue;
      }
    }
    // 桌面开发时直接指 target/debug
    if (!Platform.isAndroid && !Platform.isIOS) {
      for (final p in [
        'target/debug/libgalatea_3d.so',
        'target/release/libgalatea_3d.so',
        '../target/release/libgalatea_3d.so',
      ]) {
        try {
          return ffi.DynamicLibrary.open(p);
        } catch (_) {
          continue;
        }
      }
    }
    return null;
  }

  void clear() => _clear(_h);

  /// 加一个物体：kind = cube / sphere / plane，rgba 为 0xRRGGBBAA
  void add(String name, String kind, double x, double y, double z,
      {double sx = 1, double sy = 1, double sz = 1, int rgba = 0xE8E8E8FF}) {
    final n = _alloc(name);
    final k = _alloc(kind);
    _add(_h, n, k, x, y, z, sx, sy, sz, rgba);
    ffi.malloc.free(n);
    ffi.malloc.free(k);
  }

  void setPosition(String name, double x, double y, double z) {
    final n = _alloc(name);
    _setPos(_h, n, x, y, z);
    ffi.malloc.free(n);
  }

  void setRotation(String name, double rx, double ry, double rz) {
    final n = _alloc(name);
    _setRot(_h, n, rx, ry, rz);
    ffi.malloc.free(n);
  }

  void setCamera(double ex, double ey, double ez, double tx, double ty, double tz) {
    _setCam(_h, ex, ey, ez, tx, ty, tz);
  }

  /// 渲染并取回 RGBA 像素（拷贝一份，原生缓冲下次就失效）
  Uint8List? renderRgba() {
    if (_render(_h) == 0) return null;
    final p = _pixels(_h);
    if (p == ffi.nullptr) return null;
    final len = width * height * 4;
    return Uint8List.fromList(p.asTypedList(len));
  }

  void dispose() {
    try {
      _lib?.lookupFunction<_Void1C, _Void1D>('g3d_free')(_h);
    } catch (_) {}
  }

  static ffi.Pointer<ffi.Uint8> _alloc(String s) {
    final bytes = Uint8List.fromList([...s.codeUnits, 0]);
    final p = ffi.malloc.allocate<ffi.Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    return p;
  }
}

// ---------------------------------------------------------------- Widget

/// 把 3D 画面当成 Flutter 的一个普通 Widget 来用。
///
/// 显示层只有 Flutter：这个 Widget 拿到 RGBA 后自己 decode 成
/// `ui.Image`，再用 `RawImage` 画出来。Godot 那边不需要任何 Surface。
class Scene3DView extends StatefulWidget {
  /// 每帧回调：在这里驱动场景（转物体、移相机）
  final void Function(Gal3D engine, double t)? onFrame;

  /// 渲染分辨率（小一点更省，Flutter 会拉伸）
  final int width;
  final int height;

  const Scene3DView({
    super.key,
    this.onFrame,
    this.width = 480,
    this.height = 270,
  });

  @override
  State<Scene3DView> createState() => _Scene3DViewState();
}

class _Scene3DViewState extends State<Scene3DView>
    with SingleTickerProviderStateMixin {
  Gal3D? _engine;
  late final Ticker _ticker;
  ui.Image? _image;
  bool _busy = false;
  final Stopwatch _clock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _engine = Gal3D.create(widget.width, widget.height);
    if (_engine != null) {
      _seedScene();
      _ticker = createTicker(_tick)..start();
    } else {
      _ticker = createTicker((_) {});
    }
  }

  void _seedScene() {
    final e = _engine!;
    e.clear();
    e.add('ground', 'plane', 0, 0, 0, sx: 9, sy: 1, sz: 9, rgba: 0x1B2029FF);
    e.add('main', 'cube', -1.4, 0.6, 0, rgba: 0xE8E8E8FF);
    e.add('script', 'cube', 0.2, 0.5, -0.6, sx: .85, sy: .85, sz: .85, rgba: 0xE4032EFF);
    e.add('todo', 'sphere', 1.5, .55, .3, rgba: 0x7BE3CBFF);
    e.setCamera(3.4, 2.6, 5.0, 0, 0.6, 0);
  }

  void _tick(Duration _) {
    if (_engine == null || _busy) return;
    _busy = true;
    final t = _clock.elapsedMilliseconds / 1000.0;
    widget.onFrame?.call(_engine!, t);
    final rgba = _engine!.renderRgba();
    if (rgba == null) {
      _busy = false;
      return;
    }
    ui.decodeImageFromPixels(
      rgba,
      widget.width,
      widget.height,
      ui.PixelFormat.rgba8888,
      (img) {
        if (!mounted) {
          img.dispose();
          _busy = false;
          return;
        }
        setState(() {
          _image?.dispose();
          _image = img;
        });
        _busy = false;
      },
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _image?.dispose();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_engine == null) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF14171F),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Text(
            '3D 后端未加载\n（需要 libgalatea_3d.so）',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.6),
          ),
        ),
      );
    }
    final img = _image;
    if (img == null) {
      return Container(color: const Color(0xFF0B0D12));
    }
    return RawImage(image: img, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
  }
}