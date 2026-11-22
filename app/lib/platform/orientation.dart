/// 方向策略：**竖屏设计，横屏游玩**
///
/// - 首界面 / 编辑器：`portraitUp` —— 单手可操作，画布纵向长出来更符合思维导图的心智
/// - 播放器：`landscapeLeft / landscapeRight` —— 16:9 演出才是 galgame 该有的样子
///
/// 页面在 initState 声明自己的方向，dispose 时交还竖屏，
/// 这样从播放器返回编辑器不会残留横屏。
library;

import 'package:flutter/services.dart';

/// 竖屏（设计态）
Future<void> lockPortrait() {
  return SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
}

/// 横屏（游玩态）
Future<void> lockLandscape() {
  return SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}

/// 是否处于横向（用于布局分支）
bool isLandscapeOf(double width, double height) => width > height;