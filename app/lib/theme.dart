/// 瑞士国际主义风格（Swiss Style / International Typographic Style）
///
/// 三条硬规则，任何组件都不许破：
///   1. 只用 黑 / 白 / 灰阶 + **一个**强调色（瑞士红 #E4032E），彩色面积 < 3%
///   2. 零圆角、零阴影、零渐变；层级靠 1px 细线与灰阶差
///   3. 一切尺寸来自 8px 栅格（8 / 16 / 24 / 32 / 48）
///
/// 字体：不内嵌字体文件，用系统无衬线（Roboto / HarmonyOS Sans / MiSans），
/// 靠字重（400/600/800）与字号阶梯建立层级——瑞士风格的骨架是网格，不是某款字形。
library;

import 'package:flutter/material.dart';

class GColors {
  // ── 浅色底（参考《来自星尘》：白到浅灰蓝的渐变，大量留白）
  static const ink = Color(0xFFEDEFF1); // 底色（浅灰白）
  static const paper = Color(0xFFFFFFFF); // 卡片
  static const bg = Color(0xFFF4F5F7);
  static const panel = Color(0xFFFFFFFF);
  static const panel2 = Color(0xFFF7F8FA);
  static const line = Color(0xFFD9DCE1); // 细线
  static const lineLight = Color(0xFFE9EBEE);

  // ── 青色点缀（截图里的高亮色）
  static const accent = Color(0xFF2FC8A8);
  static const accent2 = Color(0xFF7BE3CB);
  static const ok = Color(0xFF2FC8A8);
  static const warn = Color(0xFFE0A458);
  static const err = Color(0xFFD9534F);

  // ── 文字（深炭灰，不是纯黑）
  static const text = Color(0xFF23272E);
  static const textStrong = Color(0xFF111318);
  static const dim = Color(0xFF7A828E);

  /// 节点类型：浅色底上用低饱和的色相区分
  static Color forNodeType(String type) {
    switch (type) {
      case 'say':
        return const Color(0xFF3C6E8F);
      case 'choice':
        return const Color(0xFF7A5AA8);
      case 'branch':
        return const Color(0xFFB07D2B);
      case 'set':
        return const Color(0xFF2F8F5B);
      case 'call':
        return const Color(0xFF35707D);
      case 'jump':
      case 'return':
        return const Color(0xFF8A8F98);
      case 'end':
        return const Color(0xFFA8443C);
      case 'script':
        return const Color(0xFFD4763A);
      case 'character':
        return const Color(0xFF4A6FA5);
      case 'portrait':
        return const Color(0xFF7E6BA8);
      case 'background':
        return const Color(0xFF3E8E7E);
      case 'marker':
        return const Color(0xFFB08A2E);
      case 'label':
        return const Color(0xFF3A3F47);
      case 'weight':
        return const Color(0xFF2F8F5B);
      case 'weighted':
        return const Color(0xFF9A5B8F);
      default:
        return const Color(0xFF8A8F98);
    }
  }

  static String typeCode(String type) {
    switch (type) {
      case 'say':
        return 'SAY';
      case 'choice':
        return 'CHOICE';
      case 'branch':
        return 'BRANCH';
      case 'set':
        return 'SET';
      case 'call':
        return 'CALL';
      case 'jump':
        return 'JUMP';
      case 'return':
        return 'RET';
      case 'end':
        return 'END';
      case 'script':
        return 'SCRIPT';
      case 'character':
        return 'CHAR';
      case 'portrait':
        return 'ART';
      case 'background':
        return 'BG';
      case 'marker':
        return 'TAG';
      case 'label':
        return 'NAME';
      case 'weight':
        return 'WEIGHT';
      case 'weighted':
        return 'DICE';
      default:
        return type.toUpperCase();
    }
  }
}

/// 8px 栅格
class GSpace {
  static const double unit = 8;
  static const double s1 = 8;
  static const double s2 = 16;
  static const double s3 = 24;
  static const double s4 = 32;
  static const double s5 = 40;
  static const double s6 = 48;
}

/// 字号阶梯（8px 基线）
class GType {
  static const double micro = 9.5;
  static const double label = 10.5;
  static const double caption = 12;
  static const double body = 13;
  static const double bodyLg = 15;
  static const double title = 18;
  static const double headline = 22;
  static const double display = 34;
  static const double huge = 64;

  /// 小标签字距（大写）
  static const double wide = 1.6;
  static const double wideEm = 0.14;
}

/// 圆角（参考图是 8~14 的大圆角）
class GRadius {
  static const sm = BorderRadius.all(Radius.circular(6));
  static const md = BorderRadius.all(Radius.circular(10));
  static const lg = BorderRadius.all(Radius.circular(14));
  static const zero = BorderRadius.zero;
  static const all0 = Radius.zero;
}

/// 统一的安全区读取（3 按钮导航 / 手势导航 / 刘海都走这里）
EdgeInsets viewInsetsOf(BuildContext context) {
  final mq = MediaQuery.of(context);
  // viewPadding 不像 padding 会被键盘压缩，底部导航栏高度始终准确
  return EdgeInsets.only(
    bottom: mq.viewPadding.bottom,
    left: mq.viewPadding.left,
    right: mq.viewPadding.right,
    top: mq.viewPadding.top,
  );
}

/// 小号大写标签样式（瑞士风格里最常见的元素）
TextStyle labelStyle({Color? color, double? size, FontWeight? weight}) {
  return TextStyle(
    fontSize: size ?? GType.label,
    fontWeight: weight ?? FontWeight.w600,
    letterSpacing: GType.wide,
    color: color ?? GColors.dim,
    height: 1.2,
  );
}

/// 数据/代码：等宽 + 表格数字
TextStyle monoStyle({Color? color, double? size}) {
  return TextStyle(
    fontSize: size ?? GType.caption,
    fontFamily: 'monospace',
    fontFeatures: const [FontFeature.tabularFigures()],
    color: color ?? GColors.text,
    height: 1.45,
  );
}

ThemeData buildGalateaTheme(Brightness brightness) {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: GColors.bg,
    canvasColor: GColors.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    colorScheme: base.colorScheme.copyWith(
      primary: GColors.accent,
      secondary: GColors.text,
      surface: GColors.panel,
      error: GColors.err,
      onPrimary: GColors.paper,
      onSurface: GColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: GColors.paper,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 12,
      shape: Border(bottom: BorderSide(color: GColors.line, width: 1)),
      titleTextStyle: TextStyle(
        color: GColors.textStrong,
        fontSize: GType.bodyLg,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      iconTheme: IconThemeData(color: GColors.dim, size: 20),
    ),
    textTheme: base.textTheme
        .apply(bodyColor: GColors.text, displayColor: GColors.textStrong)
        .copyWith(
          bodyMedium: const TextStyle(fontSize: GType.body, height: 1.5),
          bodySmall: const TextStyle(fontSize: GType.caption, color: GColors.dim),
          titleMedium: const TextStyle(
              fontSize: GType.bodyLg,
              fontWeight: FontWeight.w600,
              color: GColors.textStrong),
        ),
    dividerTheme: const DividerThemeData(
      color: GColors.line,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: GColors.dim, size: 20),
    // 全部输入控件：方角、无阴影、1px 线
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GColors.panel2,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: const OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: GColors.line, width: 1),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: GColors.line, width: 1),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: GColors.accent, width: 1),
      ),
      labelStyle: labelStyle(),
      hintStyle: TextStyle(fontSize: GType.caption, color: GColors.dim.withOpacity(0.7)),
    ),
    // 按钮：方角、1px 线、无阴影
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: GColors.text,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: GType.caption, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: GColors.text,
        side: const BorderSide(color: GColors.line),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GColors.accent,
        foregroundColor: GColors.paper,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(fontSize: GType.caption, fontWeight: FontWeight.w600),
      ),
    ),
    dialogTheme: const DialogTheme(
      backgroundColor: GColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: GColors.line),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: GColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: GRadius.zero),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: GColors.paper,
      contentTextStyle: const TextStyle(color: GColors.ink, fontSize: GType.caption),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: GColors.lineLight),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? GColors.accent : GColors.dim),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? GColors.accent.withOpacity(0.25) : GColors.panel2),
      trackOutlineColor: const WidgetStatePropertyAll(GColors.line),
    ),
  );
}