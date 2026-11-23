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

  /// 原生库是否就绪（**只用于 UI 上的状态标签**，不用于决定要不要渲染）
  static bool get available => _lib != null;

  /// 创建引擎。**加载失败就抛**——不允许返回 null 让调用方去画占位框。
  static Gal3D create(int width, int height) {
    final lib = _lib ??= _open();
    final f = lib.lookupFunction<_NewC, _NewD>('g3d_new');
    final h = f(width, height);
    if (h == ffi.nullptr) {
      throw StateError(
          'g3d_new($width,$height) 返回空指针：3D 后端初始化失败');
    }
    return Gal3D._(h, width, height, lib);
  }

  /// 按顺序找库；**全部失败时把每条失败原因拼起来抛出去**
  static ffi.DynamicLibrary _open() {
    final tried = <String>[];
    final candidates = <String>[
      'libgalatea_3d.so',
      'libgalatea_3d.dylib',
      'galatea_3d.dll',
      if (!Platform.isAndroid && !Platform.isIOS) ...const [
        'target/debug/libgalatea_3d.so',
        'target/release/libgalatea_3d.so',
        '../target/release/libgalatea_3d.so',
      ],
    ];
    for (final name in candidates) {
      try {
        return ffi.DynamicLibrary.open(name);
      } on ArgumentError catch (e) {
        tried.add('$name → $e');
      }
    }
    throw StateError(
      '加载 galatea-3d 原生库失败。已尝试：\n${tried.join("\n")}\n'
      '修法：cargo ndk -t arm64-v8a -o android/app/src/main/jniLibs build --release -p galatea-3d',
    );
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
  Uint8List renderRgba() {
    if (_render(_h) == 0) {
      throw StateError('g3d_render 失败（引擎句柄失效？）');
    }
    final p = _pixels(_h);
    if (p == ffi.nullptr) {
      throw StateError('g3d_pixels 返回空指针');
    }
    final len = width * height * 4;
    return Uint8List.fromList(p.asTypedList(len));
  }

  void dispose() {
    _lib?.lookupFunction<_Void1C, _Void1D>('g3d_free')(_h);
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
    // 这里不兜底：库没编出来就让这页直接炸，炸得越早越好
    _engine = Gal3D.create(widget.width, widget.height);
    _seedScene();
    _ticker = createTicker(_tick)..start();
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
    final img = _image;
    if (img == null) {
      // 只可能是"第一帧还没渲染完"，不是错误状态
      return const ColoredBox(color: Color(0xFF0B0D12));
    }
    return RawImage(
        image: img, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
  }
}