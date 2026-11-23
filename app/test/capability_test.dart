import 'package:flutter_test/flutter_test.dart';
import 'package:galatea_studio/engine/capability.dart';

void main() {
  test('主机端拥有完整能力', () {
    for (final c in ['edit', 'rust_script', 'godot_script', 'preview',
        'import_play', 'pack', 'export_godot', 'scene3d_edit']) {
      expect(can(c, EngineTier.host), true, reason: 'host 应有 $c');
    }
  });
  test('移动端禁用 godot 脚本与自主打包', () {
    expect(can('godot_script', EngineTier.mobile), false);
    expect(can('export_godot', EngineTier.mobile), false);
    expect(can('scene3d_edit', EngineTier.mobile), false);
    // 但核心编辑/预览/导入游玩仍在
    expect(can('edit', EngineTier.mobile), true);
    expect(can('rust_script', EngineTier.mobile), true);
    expect(can('import_play', EngineTier.mobile), true);
  });
  test('未知能力一律不存在', () {
    expect(can('nonsense', EngineTier.host), false);
    expect(can('nonsense', EngineTier.mobile), false);
  });
}
