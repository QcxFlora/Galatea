import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/home_page.dart';
import 'platform/orientation.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 方向策略：竖屏设计 / 横屏游玩（各页面自己声明）
  await lockPortrait();

  // 3 按钮导航 / 手势导航都走 edge-to-edge，底部避让交给 viewPadding
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: GColors.ink,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const GalateaApp());
}

class GalateaApp extends StatelessWidget {
  const GalateaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Galatea Studio',
      debugShowCheckedModeBanner: false,
      theme: buildGalateaTheme(Brightness.dark),
      home: const HomePage(),
      builder: (context, child) {
        // 全局锁死文字缩放，避免系统字号把瑞士栅格撑破
        final mq = MediaQuery.of(context);
        if (child == null) {
          throw StateError('MaterialApp.builder 收到空 child：路由没挂上');
        }
        return MediaQuery(
          data: mq.copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child,
        );
      },
    );
  }
}
