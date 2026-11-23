import 'dart:io' show Platform;

/// 客户端等级：主机端功能完整，移动端受限。
/// 遵循 RULES.md 第 5 条——受限能力**根本不存在**，不是灰掉或静默降级。
enum EngineTier { host, mobile }

/// 当前等级。可用 --dart-define=GALATEA_TIER=host|mobile 显式覆盖（测试/特殊设备）。
EngineTier currentTier() {
  const override = String.fromEnvironment('GALATEA_TIER');
  if (override == 'host') return EngineTier.host;
  if (override == 'mobile') return EngineTier.mobile;
  if (Platform.isAndroid || Platform.isIOS) return EngineTier.mobile;
  return EngineTier.host;
}

/// 能力表。mobile 没有 godot_script / export_godot / scene3d_edit。
const Map<EngineTier, Set<String>> _caps = {
  EngineTier.host: {
    'edit', 'rust_script', 'godot_script', 'preview',
    'import_play', 'pack', 'export_godot', 'scene3d_edit',
  },
  EngineTier.mobile: {
    'edit', 'rust_script', 'preview', 'import_play', 'pack',
  },
};

/// 查询某能力在当前（或指定）等级下是否存在。
bool can(String capability, [EngineTier? tier]) =>
    (_caps[tier ?? currentTier()] ?? const <String>{}).contains(capability);
