/// 右侧/底部属性面板：选中一个节点，就在这里改它。
library;

import '../engine/capability.dart';
import 'package:flutter/material.dart';

import '../models/graph.dart';
import '../theme.dart';

class Inspector extends StatelessWidget {
  final Story story;
  final String nodeId;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;

  const Inspector({
    super.key,
    required this.story,
    required this.nodeId,
    required this.onChanged,
    required this.onClose,
    required this.onDelete,
    required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    final node = story.nodeById(nodeId);
    if (node == null) {
      return const SizedBox.shrink();
    }
    final accent = GColors.forNodeType(nodeTypeId(node.type));
    return Container(
      key: ValueKey('inspector-${node.id}'),
      decoration: const BoxDecoration(
        color: GColors.panel,
        border: Border(top: BorderSide(color: GColors.line)),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('${nodeTypeIcon(node.type)} ${nodeTypeLabel(node.type)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(node.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: GColors.dim)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: '复制节点',
                  onPressed: onDuplicate,
                  icon: const Icon(Icons.copy_all, color: GColors.dim),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: '删除节点',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: GColors.err),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: GColors.dim),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              children: [
                _text('节点别名（显示在卡片标题上）', node.title ?? '', (v) {
                  node.title = v.isEmpty ? null : v;
                  onChanged();
                }),
                const SizedBox(height: 10),
                ..._body(node),
                const SizedBox(height: 12),
                _ports(node),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(StoryNode node) {
    switch (node.type) {
      case NodeType.image:
        return [
          _text('资源标识 key', node.tag ?? '', (v) {
            node.tag = v.isEmpty ? null : v;
            onChanged();
          }, hint: '唯一名字，供 say 的 art/bg 端口连线引用'),
          const SizedBox(height: 10),
          _text('图片路径', node.asset ?? '', (v) {
            node.asset = v.isEmpty ? null : v;
            onChanged();
          }, hint: '.webp/.png/.jpg，相对资源根'),
          const SizedBox(height: 10),
          _text('显示名（可空）', node.text, (v) {
            node.text = v;
            onChanged();
          }),
        ];
      case NodeType.audio:
        return [
          _text('资源标识 key', node.tag ?? '', (v) {
            node.tag = v.isEmpty ? null : v;
            onChanged();
          }),
          const SizedBox(height: 10),
          _text('音频路径', node.asset ?? '', (v) {
            node.asset = v.isEmpty ? null : v;
            onChanged();
          }, hint: '.ogg/.mp3/.wav'),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: node.audioKind,
            decoration: const InputDecoration(labelText: '用途'),
            items: const [
              DropdownMenuItem(value: 'bgm', child: Text('BGM（循环铺底）')),
              DropdownMenuItem(value: 'sfx', child: Text('音效（一次性）')),
              DropdownMenuItem(value: 'voice', child: Text('配音'))
            ],
            onChanged: (v) {
              node.audioKind = v ?? 'bgm';
              node.audioLoop = v == 'bgm';
              onChanged();
            },
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            title: const Text('循环播放'),
            value: node.audioLoop,
            onChanged: (v) {
              node.audioLoop = v;
              onChanged();
            },
          ),
          _text('音量（0.0–1.0）', node.audioVolume.toString(), (v) {
            node.audioVolume = double.tryParse(v) ?? 1.0;
            onChanged();
          }),
        ];
      case NodeType.value:
        return [
          _text('表达式', node.expr ?? '0', (v) {
            node.expr = v;
            onChanged();
          }, hint: '值块：算出一个数，供变量块 / 加权块连线引用'),
        ];
      case NodeType.variable:
        return [
          _text('变量名', node.text, (v) {
            node.text = v;
            onChanged();
          }, hint: '变量块：给这个变量累加 add 端口连进来的值'),
          const SizedBox(height: 10),
          _text('add 端口（值块 id，逗号分隔）', node.varAdd.join(', '), (v) {
            node.varAdd = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
            onChanged();
          }, hint: '也可在画布上从值块拖线到这里'),
        ];
      case NodeType.weighted:
        return [
          _text('提示', node.prompt, (v) {
            node.prompt = v;
            onChanged();
          }),
          const SizedBox(height: 10),
          for (var i = 0; i < node.branches.length; i++) ...[
            _text('分支 ${i + 1} 权重', node.branches[i].weight, (v) {
              node.branches[i].weight = v;
              onChanged();
            }, hint: '权重表达式，<=0 视为不可达'),
            const SizedBox(height: 6),
          ],
        ];
      case NodeType.say:
        return [
          _speakerPicker(node),
          const SizedBox(height: 10),
          _text('台词', node.text, (v) {
            node.text = v;
            onChanged();
          }, maxLines: 5, hint: '支持换行；{变量名} 会在播放时替换成当前值'),
          const SizedBox(height: 10),
          _text('背景图（资源路径，可空）', node.bg ?? '', (v) {
            node.bg = v.isEmpty ? null : v;
            onChanged();
          }),
          const SizedBox(height: 10),
          _text('立绘（资源路径，可空）', node.portrait ?? '', (v) {
            node.portrait = v.isEmpty ? null : v;
            onChanged();
          }),
        ];
      case NodeType.choice:
        return [
          _text('提示语', node.prompt, (v) {
            node.prompt = v;
            onChanged();
          }),
          const SizedBox(height: 10),
          for (var i = 0; i < node.options.length; i++) ...[
            _optionEditor(node, i),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: () {
              node.options.add(Choice(text: '新选项'));
              onChanged();
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('加一个选项'),
          ),
        ];
      case NodeType.branch:
        return [
          _text('条件表达式', node.cond, (v) {
            node.cond = v;
            onChanged();
          }, hint: '例如：好感 >= 3 && 见过面'),
        ];
      case NodeType.set:
        return [
          for (var i = 0; i < node.effects.length; i++) ...[
            _effectEditor(node.effects, i, () {
              node.effects.removeAt(i);
              onChanged();
            }),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () {
              node.effects.add(Effect(target: '好感', op: EffectOp.add, expr: '1'));
              onChanged();
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('加一条变量改动'),
          ),
        ];
      case NodeType.jump:
        return const [
          Text('从卡片右侧的圆点拖一条线到目标节点即可。',
              style: TextStyle(fontSize: 12, color: GColors.dim)),
        ];
      case NodeType.call:
        return const [
          Text('「→」进入子图，「回」是子图返回后继续的位置。',
              style: TextStyle(fontSize: 12, color: GColors.dim)),
        ];
      case NodeType.ret:
        return const [
          Text('执行到这里会回到调用它的「子图」节点。',
              style: TextStyle(fontSize: 12, color: GColors.dim)),
        ];
      case NodeType.script:
        return [
          // 移动端没有 godot_script 能力 → 引擎选择器根本不渲染（不是灰掉）
          if (can('godot_script')) ...[
            DropdownButtonFormField<String>(
              value: node.scriptEngine,
              decoration: const InputDecoration(labelText: '脚本引擎'),
              items: const [
                DropdownMenuItem(value: 'rust', child: Text('Rust（内置沙箱，预览即所得）')),
                DropdownMenuItem(value: 'godot', child: Text('Godot GDScript（引用外部 .gd）')),
              ],
              onChanged: (v) {
                node.scriptEngine = v ?? 'rust';
                onChanged();
              },
            ),
            const SizedBox(height: 10),
          ],
          _text(node.scriptEngine == 'godot' ? '引用的 .gd 路径' : '脚本路径（相对项目根）',
              node.src ?? '', (v) {
            node.src = v.isEmpty ? null : v;
            onChanged();
          }, hint: node.scriptEngine == 'godot' ? 'res://scripts/minigame.gd' : 'scripts/intro.rs'),
          const SizedBox(height: 10),
          _text('入口函数', node.entry, (v) {
            node.entry = v.isEmpty ? 'main' : v;
            onChanged();
          }, hint: node.scriptEngine == 'godot' ? 'run' : 'opening'),
          const SizedBox(height: 10),
          Text(
              node.scriptEngine == 'godot'
                  ? 'Godot 引擎本体需自行安装（godotengine.org/download）。Galatea 只引用脚本，export-godot 打包成工程。'
                  : '脚本用 Rust 安全子集（fn/let/if/while/return），内置 spring / ease / set / emit / get。',
              style: const TextStyle(fontSize: 11.5, color: GColors.dim, height: 1.6)),
        ];
      case NodeType.character:
        return [
          _text('角色 key（剧本里引用它）', node.tag ?? '', (v) {
            node.tag = v.isEmpty ? null : v;
            onChanged();
          }, hint: 'amiya'),
          const SizedBox(height: 10),
          _text('显示名', node.text, (v) {
            node.text = v;
            onChanged();
          }, hint: '阿米娅'),
          const SizedBox(height: 10),
          const Text('立绘集合由「立绘」方块通过 character 字段挂过来。',
              style: TextStyle(fontSize: 11.5, color: GColors.dim)),
        ];
      case NodeType.portrait:
        return [
          _text('资源路径', node.asset ?? '', (v) {
            node.asset = v.isEmpty ? null : v;
            onChanged();
          }, hint: 'assets/characters/amiya.webp'),
          const SizedBox(height: 10),
          _text('所属角色（选填）', node.character ?? '', (v) {
            node.character = v.isEmpty ? null : v;
            onChanged();
          }),
          const SizedBox(height: 10),
          _text('表情名（选填）', node.expr ?? '', (v) {
            node.expr = v.isEmpty ? null : v;
            onChanged();
          }, hint: 'smile'),
        ];
      case NodeType.background:
        return [
          _text('资源路径', node.asset ?? '', (v) {
            node.asset = v.isEmpty ? null : v;
            onChanged();
          }, hint: 'assets/bg/store.webp'),
          const SizedBox(height: 10),
          _text('场景名（选填）', node.scene ?? '', (v) {
            node.scene = v.isEmpty ? null : v;
            onChanged();
          }),
        ];
      case NodeType.marker:
        return [
          _text('标记名（剧本内部引用，不显示）', node.tag ?? '', (v) {
            node.tag = v.isEmpty ? null : v;
            onChanged();
          }, hint: 'amiya'),
          const SizedBox(height: 10),
          const Text('从右侧圆点拖一条线到「显示名」方块，播放时就用那个名字。',
              style: TextStyle(fontSize: 11.5, color: GColors.dim, height: 1.6)),
        ];
      case NodeType.label:
        return [
          _text('显示名（给玩家看的文字）', node.text, (v) {
            node.text = v;
            onChanged();
          }, hint: '阿米娅'),
        ];
      case NodeType.end:
        return [
          _text('结局代号', node.ending, (v) {
            node.ending = v;
            onChanged();
          }, hint: 'good / bad / true …… 用于统计与解锁'),
          const SizedBox(height: 10),
          _text('结局文字', node.endText, (v) {
            node.endText = v;
            onChanged();
          }, maxLines: 4),
        ];
    }
  }

  Widget _speakerPicker(StoryNode node) {
    final keys = <String?>[null, ...story.characters.keys];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('说话人', style: TextStyle(fontSize: 12, color: GColors.dim)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: GColors.panel2,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            border: Border.all(color: GColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: keys.contains(node.speaker) ? node.speaker : null,
              isExpanded: true,
              dropdownColor: GColors.panel2,
              style: const TextStyle(fontSize: 13, color: GColors.text),
              items: [
                for (final k in keys)
                  DropdownMenuItem<String?>(
                    value: k,
                    child: Text(k == null
                        ? '旁白'
                        : '${story.characters[k]?.name ?? k}（$k）'),
                  ),
              ],
              onChanged: (v) {
                node.speaker = v;
                onChanged();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionEditor(StoryNode node, int i) {
    final o = node.options[i];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: GColors.panel2,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(color: GColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: GColors.accent2, shape: BoxShape.circle),
                child: Text('${i + 1}',
                    style: const TextStyle(fontSize: 11, color: Colors.white)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  o.to.isEmpty ? '未连线' : '→ ${o.to}',
                  style: TextStyle(
                      fontSize: 11,
                      color: o.to.isEmpty ? GColors.err : GColors.dim),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: () {
                  node.options.removeAt(i);
                  onChanged();
                },
                icon: const Icon(Icons.close, color: GColors.dim),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _text('选项文字', o.text, (v) {
            o.text = v;
            onChanged();
          }, keyPrefix: 'opt$i-text'),
          const SizedBox(height: 8),
          _text('出现条件（可空）', o.cond, (v) {
            o.cond = v;
            onChanged();
          }, keyPrefix: 'opt$i-cond', hint: '例如：好感 >= 2'),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('只能选一次',
                  style: TextStyle(fontSize: 12, color: GColors.dim)),
              const Spacer(),
              Switch(
                value: o.once,
                onChanged: (v) {
                  o.once = v;
                  onChanged();
                },
              ),
            ],
          ),
          for (var j = 0; j < o.effects.length; j++)
            _effectEditor(o.effects, j, () {
              o.effects.removeAt(j);
              onChanged();
            }, keyPrefix: 'opt$i-eff$j'),
          TextButton.icon(
            onPressed: () {
              o.effects.add(Effect(target: '好感', op: EffectOp.add, expr: '1'));
              onChanged();
            },
            icon: const Icon(Icons.add, size: 14),
            label: const Text('选中后改变量', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _effectEditor(List<Effect> list, int i, VoidCallback onRemove,
      {String keyPrefix = 'eff'}) {
    final e = list[i];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: GColors.bg,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(color: GColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _text('变量', e.target, (v) {
              e.target = v;
              onChanged();
            }, keyPrefix: '$keyPrefix$i-target'),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: GColors.panel2,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              border: Border.all(color: GColors.line),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<EffectOp>(
                value: e.op,
                dropdownColor: GColors.panel2,
                style: const TextStyle(fontSize: 13, color: GColors.ok),
                items: [
                  for (final op in EffectOp.values)
                    DropdownMenuItem(
                        value: op, child: Text(effectSymbol(op))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  e.op = v;
                  onChanged();
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: _text('值/表达式', e.expr, (v) {
              e.expr = v;
              onChanged();
            }, keyPrefix: '$keyPrefix$i-expr'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            onPressed: onRemove,
            icon: const Icon(Icons.close, color: GColors.dim),
          ),
        ],
      ),
    );
  }

  Widget _ports(StoryNode node) {
    final ports = nodePortsOf(node);
    if (ports.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('连线', style: TextStyle(fontSize: 12, color: GColors.dim)),
        const SizedBox(height: 6),
        for (final p in ports)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 26,
                  alignment: Alignment.center,
                  child: Text(portLabelOf(p),
                      style: const TextStyle(fontSize: 11, color: GColors.dim)),
                ),
                Expanded(
                  child: Text(
                    node.portTarget(p) ?? '（未连接）',
                    style: TextStyle(
                        fontSize: 12,
                        color: node.portTarget(p) == null
                            ? GColors.err
                            : GColors.text),
                  ),
                ),
                if (node.portTarget(p) != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 15,
                    tooltip: '断开',
                    onPressed: () {
                      node.setPort(p, null);
                      onChanged();
                    },
                    icon: const Icon(Icons.link_off, color: GColors.dim),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _text(String label, String value, ValueChanged<String> onChanged,
      {int maxLines = 1, String? hint, String keyPrefix = 'f'}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: GColors.dim)),
        const SizedBox(height: 4),
        TextFormField(
          key: ValueKey('$keyPrefix-${nodeId}-$label'),
          initialValue: value,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13, color: GColors.text),
          decoration: InputDecoration(hintText: hint),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// 与 canvas.dart 里的端口定义保持一致（这里再声明一份，避免循环 import）
List<String> nodePortsOf(StoryNode n) {
  switch (n.type) {
    case NodeType.say:
    case NodeType.set:
    case NodeType.script:
    case NodeType.marker:
    case NodeType.label:
    case NodeType.character:
    case NodeType.portrait:
    case NodeType.background:
    case NodeType.value:
    case NodeType.variable:
    case NodeType.weighted:
    case NodeType.image:
    case NodeType.audio:
      return const ['next'];
    case NodeType.branch:
      return const ['yes', 'no'];
    case NodeType.choice:
      return [for (var i = 0; i < n.options.length; i++) 'opt$i'];
    case NodeType.jump:
      return const ['to'];
    case NodeType.call:
      return const ['to', 'back'];
    case NodeType.ret:
    case NodeType.end:
      return const [];
  }
}

String portLabelOf(String port) {
  if (port == 'yes') return '真';
  if (port == 'no') return '假';
  if (port == 'back') return '回';
  if (port.startsWith('opt')) return '${int.parse(port.substring(3)) + 1}';
  return '→';
}