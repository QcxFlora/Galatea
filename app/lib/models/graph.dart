/// 剧情图模型 —— 必须与 Rust 侧 `galatea-core/src/graph.rs` 的 JSON 完全同构。
///
/// 一份 `.gala.json` 文件既是编辑器的工作文件，也是玩家端的剧本，
/// 也是 Rust 打包器 / 校验器读的输入。所以这里的字段名不要随便改。
library;

import 'dart:convert';

// ------------------------------------------------------------------ 节点类型

enum NodeType { say, choice, branch, set, jump, call, ret, end, script,
  // v0.2：资源方块 + 标记名/显示名
  character, portrait, background, marker, label,
  // v0.3 加权（值块 / 变量块 / 加权分支）
  value, variable, weighted, image, audio }

String nodeTypeId(NodeType t) {
  switch (t) {
    case NodeType.say:
      return 'say';
    case NodeType.choice:
      return 'choice';
    case NodeType.branch:
      return 'branch';
    case NodeType.set:
      return 'set';
    case NodeType.jump:
      return 'jump';
    case NodeType.call:
      return 'call';
    case NodeType.ret:
      return 'return';
    case NodeType.end:
      return 'end';
    case NodeType.script:
      return 'script';
    case NodeType.character:
      return 'character';
    case NodeType.portrait:
      return 'portrait';
    case NodeType.background:
      return 'background';
    case NodeType.marker:
      return 'marker';
    case NodeType.label:
      return 'label';
    case NodeType.value:
      return 'value';
    case NodeType.variable:
      return 'variable';
    case NodeType.weighted:
      return 'weighted';
    case NodeType.image:
      return 'image';
    case NodeType.audio:
      return 'audio';
  }
}

NodeType nodeTypeFrom(String? s) {
  switch (s) {
    case 'choice':
      return NodeType.choice;
    case 'branch':
      return NodeType.branch;
    case 'set':
      return NodeType.set;
    case 'jump':
      return NodeType.jump;
    case 'call':
      return NodeType.call;
    case 'return':
      return NodeType.ret;
    case 'end':
      return NodeType.end;
    case 'script':
      return NodeType.script;
    case 'character':
      return NodeType.character;
    case 'portrait':
      return NodeType.portrait;
    case 'background':
      return NodeType.background;
    case 'marker':
      return NodeType.marker;
    case 'label':
      return NodeType.label;
    case 'value':
      return NodeType.value;
    case 'variable':
      return NodeType.variable;
    case 'weighted':
      return NodeType.weighted;
    case 'image':
      return NodeType.image;
    case 'audio':
      return NodeType.audio;
    default:
      return NodeType.say;
  }
}

String nodeTypeLabel(NodeType t) {
  switch (t) {
    case NodeType.say:
      return '台词';
    case NodeType.choice:
      return '选择';
    case NodeType.branch:
      return '条件';
    case NodeType.set:
      return '变量';
    case NodeType.jump:
      return '跳转';
    case NodeType.call:
      return '子图';
    case NodeType.ret:
      return '返回';
    case NodeType.end:
      return '结局';
    case NodeType.script:
      return '脚本';
    case NodeType.character:
      return '角色';
    case NodeType.portrait:
      return '立绘';
    case NodeType.background:
      return '背景';
    case NodeType.marker:
      return '标记名';
    case NodeType.label:
      return '显示名';
    case NodeType.value:
      return '值';
    case NodeType.variable:
      return '变量';
    case NodeType.weighted:
      return '加权分支';
    case NodeType.image:
      return '图块';
    case NodeType.audio:
      return '音频';
  }
}

String nodeTypeIcon(NodeType t) {
  switch (t) {
    case NodeType.say:
      return '💬';
    case NodeType.choice:
      return '🔀';
    case NodeType.branch:
      return '❓';
    case NodeType.set:
      return '🎚️';
    case NodeType.jump:
      return '↪️';
    case NodeType.call:
      return '📦';
    case NodeType.ret:
      return '↩️';
    case NodeType.end:
      return '🎬';
    case NodeType.script:
      return '⚙️';
    case NodeType.character:
      return '👤';
    case NodeType.portrait:
      return '🖼️';
    case NodeType.background:
      return '🏙️';
    case NodeType.marker:
      return '🏷️';
    case NodeType.label:
      return 'Ａ';
    case NodeType.value:
      return '#';
    case NodeType.variable:
      return '𝑥';
    case NodeType.weighted:
      return '🎲';
    case NodeType.image:
      return '🖼';
    case NodeType.audio:
      return '🔊';
  }
}

// ------------------------------------------------------------------ 效果

enum EffectOp { set, add, sub, mul, max, min, toggle }

String effectOpId(EffectOp op) {
  switch (op) {
    case EffectOp.set:
      return 'set';
    case EffectOp.add:
      return 'add';
    case EffectOp.sub:
      return 'sub';
    case EffectOp.mul:
      return 'mul';
    case EffectOp.max:
      return 'max';
    case EffectOp.min:
      return 'min';
    case EffectOp.toggle:
      return 'toggle';
  }
}

EffectOp effectOpFrom(String? s) {
  switch (s) {
    case 'add':
      return EffectOp.add;
    case 'sub':
      return EffectOp.sub;
    case 'mul':
      return EffectOp.mul;
    case 'max':
      return EffectOp.max;
    case 'min':
      return EffectOp.min;
    case 'toggle':
      return EffectOp.toggle;
    default:
      return EffectOp.set;
  }
}

String effectSymbol(EffectOp op) {
  switch (op) {
    case EffectOp.set:
      return '=';
    case EffectOp.add:
      return '+=';
    case EffectOp.sub:
      return '-=';
    case EffectOp.mul:
      return '*=';
    case EffectOp.max:
      return '↑';
    case EffectOp.min:
      return '↓';
    case EffectOp.toggle:
      return '!';
  }
}

class Effect {
  String target;
  EffectOp op;
  String expr;

  Effect({this.target = '', this.op = EffectOp.set, this.expr = '0'});

  factory Effect.fromJson(dynamic j) {
    final m = (j is Map) ? j : const {};
    return Effect(
      target: asString(m['target']),
      op: effectOpFrom(m['op'] as String?),
      expr: asString(m['expr'], fallback: '0'),
    );
  }

  Map<String, dynamic> toJson() => {
        'target': target,
        'op': effectOpId(op),
        'expr': expr,
      };

  Effect copy() => Effect(target: target, op: op, expr: expr);

  String get display => '$target ${effectSymbol(op)} $expr';
}

// ------------------------------------------------------------------ 选项

/// 加权分支的一条路
class WeightedBranch {
  String to;
  /// 权重表达式（可动态，如 `好感 * 2`；<=0 视为不可达）
  String weight;
  String cond;

  WeightedBranch({this.to = '', this.weight = '1', this.cond = ''});

  factory WeightedBranch.fromJson(dynamic j) {
    final m = (j is Map) ? j : const {};
    return WeightedBranch(
      to: asString(m['to']),
      weight: asString(m['weight'], fallback: '1'),
      cond: asString(m['cond']),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'to': to, 'weight': weight};
    if (cond.trim().isNotEmpty) m['cond'] = cond;
    return m;
  }

  WeightedBranch copy() => WeightedBranch(to: to, weight: weight, cond: cond);
}

class Choice {
  String text;
  String to;
  String cond;
  List<Effect> effects;
  bool once;

  Choice({
    this.text = '',
    this.to = '',
    this.cond = '',
    List<Effect>? effects,
    this.once = false,
  }) : effects = effects ?? <Effect>[];

  factory Choice.fromJson(dynamic j) {
    final m = (j is Map) ? j : const {};
    final effs = (m['effects'] is List)
        ? (m['effects'] as List).map(Effect.fromJson).toList()
        : <Effect>[];
    return Choice(
      text: asString(m['text']),
      to: asString(m['to']),
      cond: asString(m['cond']),
      effects: effs,
      once: m['once'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'text': text, 'to': to};
    if (cond.trim().isNotEmpty) m['cond'] = cond;
    if (once) m['once'] = true;
    if (effects.isNotEmpty) {
      m['effects'] = effects.map((e) => e.toJson()).toList();
    }
    return m;
  }

  Choice copy() => Choice(
        text: text,
        to: to,
        cond: cond,
        effects: effects.map((e) => e.copy()).toList(),
        once: once,
      );
}

// ------------------------------------------------------------------ 节点

class StoryNode {
  String id;
  NodeType type;
  double x;
  double y;
  String? title;

  // 台词（v0.2：不再内嵌说话人/立绘，全部走连线）
  String? speaker; // 仅兼容旧剧本，新数据不写
  String text;
  String? bg;
  String? portrait;
  /// 说话人连线（可多个：多人同声）
  List<String> casts;
  /// 立绘连线（可多个：多人同框）
  List<String> arts;
  /// 背景连线（可多个，取第一个）
  List<String> bgs;

  // 流程
  String? next; // say / set / call 的返回点
  String? yes; // branch
  String? no; // branch
  String? to; // jump / call

  // 选择
  String prompt;
  List<Choice> options;

  // 条件
  String cond;

  // 变量
  List<Effect> effects;

  // 变量块的 add 端口（连值块，可多个）
  List<String> varAdd;

  // 加权分支
  List<WeightedBranch> branches;

  // 音频块（image 复用 tag=key / asset=path / text=label）
  String audioKind; // bgm | sfx | voice
  bool audioLoop;
  double audioVolume;

  // 结局
  String ending;
  String endText;

  // 自定义 Rust 脚本（src 路径 或 code 内联，二选一）
  String? src;
  String? code;
  String entry;
  /// 脚本引擎：'rust'（内置沙箱解释器）或 'godot'（GDScript，需 Godot 运行时）
  String scriptEngine;

  // v0.2 资源方块
  String? tag; // marker：标记名
  String? asset; // portrait/background：资源路径
  String? character; // portrait：所属角色
  String? expr; // portrait：表情名
  String? scene; // background：场景名
  List<String> portraits; // character：立绘集合

  StoryNode({
    required this.id,
    required this.type,
    this.x = 0,
    this.y = 0,
    this.title,
    this.speaker,
    this.text = '',
    this.bg,
    this.portrait,
    this.next,
    this.yes,
    this.no,
    this.to,
    this.prompt = '',
    List<Choice>? options,
    this.cond = '',
    List<Effect>? effects,
    this.ending = '',
    this.endText = '',
    this.src,
    this.code,
    this.entry = 'main',
    this.scriptEngine = 'rust',
    this.tag,
    List<String>? varAdd,
    List<WeightedBranch>? branches,
    List<String>? casts,
    List<String>? arts,
    List<String>? bgs,
    this.asset,
    this.character,
    this.expr,
    this.scene,
    this.audioKind = 'bgm',
    this.audioLoop = true,
    this.audioVolume = 1.0,
    List<String>? portraits,
  })  : portraits = portraits ?? <String>[],
        varAdd = varAdd ?? <String>[],
        branches = branches ?? <WeightedBranch>[],
        casts = casts ?? <String>[],
        arts = arts ?? <String>[],
        bgs = bgs ?? <String>[],
        options = options ?? <Choice>[],
        effects = effects ?? <Effect>[];

  factory StoryNode.fromJson(Map<String, dynamic> m) {
    final type = nodeTypeFrom(m['type'] as String?);
    return StoryNode(
      id: asString(m['id']),
      type: type,
      x: asDouble(m['x']),
      y: asDouble(m['y']),
      title: asOptString(m['title']),
      speaker: asOptString(m['speaker']),
      // 变量块的变量名存在 name 里，其他块用 text
      text: nodeTypeFrom(m['type'] as String?) == NodeType.variable
          ? asString(m['name'])
          : nodeTypeFrom(m['type'] as String?) == NodeType.image
              ? asString(m['label'])
              : asString(m['text']),
      bg: asOptString(m['bg']),
      portrait: asOptString(m['portrait']),
      next: asOptString(m['next']),
      yes: asOptString(m['yes']),
      no: asOptString(m['no']),
      to: asOptString(m['to']),
      prompt: asString(m['prompt']),
      options: (m['options'] is List)
          ? (m['options'] as List).map(Choice.fromJson).toList()
          : <Choice>[],
      cond: asString(m['cond']),
      effects: (m['effects'] is List)
          ? (m['effects'] as List).map(Effect.fromJson).toList()
          : <Effect>[],
      ending: asString(m['ending'], fallback: 'end'),
      endText: asString(m['text']),
      src: asOptString(m['src']),
      code: asOptString(m['code']),
      entry: asString(m['entry'], fallback: 'main'),
      scriptEngine: asString(m['engine'], fallback: 'rust'),
      tag: asOptString(m['tag']) ?? asOptString(m['key']),
      varAdd: _strList(m['add']),
      branches: (m['branches'] is List)
          ? (m['branches'] as List).map(WeightedBranch.fromJson).toList()
          : <WeightedBranch>[],
      casts: _strList(m['cast']),
      arts: _strList(m['art']),
      bgs: _strList(m['bg']),
      asset: asOptString(m['asset']) ?? asOptString(m['path']),
      character: asOptString(m['character']),
      expr: asOptString(m['expr']),
      scene: asOptString(m['scene']),
      audioKind: asString(m['kind'], fallback: 'bgm'),
      audioLoop: m['loop'] is bool ? m['loop'] as bool : asString(m['kind'], fallback: 'bgm') == 'bgm',
      audioVolume: (m['volume'] is num) ? (m['volume'] as num).toDouble() : 1.0,
      portraits: (m['portraits'] is List)
          ? (m['portraits'] as List).map((e) => '$e').toList()
          : <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'type': nodeTypeId(type),
      'x': _round1(x),
      'y': _round1(y),
    };
    if (title != null && title!.trim().isNotEmpty) m['title'] = title;
    switch (type) {
      case NodeType.say:
        m['text'] = text;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        if (casts.isNotEmpty) m['cast'] = casts;
        if (arts.isNotEmpty) m['art'] = arts;
        if (bgs.isNotEmpty) m['bg'] = bgs;
        break;
      case NodeType.choice:
        m['prompt'] = prompt;
        m['options'] = options.map((o) => o.toJson()).toList();
        break;
      case NodeType.branch:
        m['cond'] = cond;
        if (yes != null && yes!.isNotEmpty) m['yes'] = yes;
        if (no != null && no!.isNotEmpty) m['no'] = no;
        break;
      case NodeType.set:
        m['effects'] = effects.map((e) => e.toJson()).toList();
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
      case NodeType.value:
        // 值块的表达式统一走 expr 字段（与 fromJson / Rust Value{expr} 一致）
        m['expr'] = (expr ?? '').isEmpty ? '1' : expr!;
        break;
      case NodeType.variable:
        m['name'] = text;
        if (varAdd.isNotEmpty) m['add'] = varAdd;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
      case NodeType.weighted:
        m['prompt'] = prompt;
        m['branches'] = branches.map((b) => b.toJson()).toList();
        break;
      case NodeType.image:
        m['key'] = tag ?? '';
        m['path'] = asset ?? '';
        if (text.isNotEmpty) m['label'] = text;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
      case NodeType.audio:
        m['key'] = tag ?? '';
        m['path'] = asset ?? '';
        m['kind'] = audioKind;
        m['loop'] = audioLoop;
        m['volume'] = audioVolume;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
      case NodeType.jump:
        if (to != null && to!.isNotEmpty) m['to'] = to;
        break;
      case NodeType.call:
        if (to != null && to!.isNotEmpty) m['to'] = to;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
      case NodeType.ret:
        break;
      case NodeType.end:
        m['ending'] = ending.isEmpty ? 'end' : ending;
        if (endText.isNotEmpty) m['text'] = endText;
        break;
      case NodeType.script:
        m['engine'] = scriptEngine;
        if (src != null && src!.isNotEmpty) m['src'] = src;
        if (code != null && code!.isNotEmpty) m['code'] = code;
        m['entry'] = entry.isEmpty ? 'main' : entry;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
      case NodeType.marker:
        m['tag'] = tag ?? id;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
      case NodeType.label:
        m['text'] = text;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
      case NodeType.character:
        m['key'] = tag ?? id;
        m['name'] = text.isEmpty ? (title ?? '角色') : text;
        if (portraits.isNotEmpty) m['portraits'] = portraits;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
      case NodeType.portrait:
        if (character != null && character!.isNotEmpty) m['character'] = character;
        m['asset'] = asset ?? '';
        if (expr != null && expr!.isNotEmpty) m['expr'] = expr;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
      case NodeType.background:
        m['asset'] = asset ?? '';
        if (scene != null && scene!.isNotEmpty) m['scene'] = scene;
        if (next != null && next!.isNotEmpty) m['next'] = next;
        break;
    }
    return m;
  }

  StoryNode copy() => StoryNode(
        id: id,
        type: type,
        x: x,
        y: y,
        title: title,
        speaker: speaker,
        text: text,
        bg: bg,
        portrait: portrait,
        next: next,
        yes: yes,
        no: no,
        to: to,
        prompt: prompt,
        options: options.map((o) => o.copy()).toList(),
        cond: cond,
        effects: effects.map((e) => e.copy()).toList(),
        ending: ending,
        endText: endText,
        src: src,
        code: code,
        entry: entry,
        scriptEngine: scriptEngine,
        tag: tag,
        varAdd: List<String>.from(varAdd),
        branches: branches.map((b) => b.copy()).toList(),
        audioKind: audioKind,
        audioLoop: audioLoop,
        audioVolume: audioVolume,
        casts: List<String>.from(casts),
        arts: List<String>.from(arts),
        bgs: List<String>.from(bgs),
        asset: asset,
        character: character,
        expr: expr,
        scene: scene,
        portraits: List<String>.from(portraits),
      );

  /// 所有出口：(端口名, 目标节点 id)
  List<MapEntry<String, String>> ports() {
    final out = <MapEntry<String, String>>[];
    void add(String port, String? target) {
      if (target != null && target.isNotEmpty) {
        out.add(MapEntry(port, target));
      }
    }

    switch (type) {
      case NodeType.say:
        add('next', next);
        for (final c in casts) {
          add('cast', c);
        }
        for (final a in arts) {
          add('art', a);
        }
        for (final b in bgs) {
          add('bg', b);
        }
        break;
      case NodeType.set:
      case NodeType.script:
        add('next', next);
        break;
      case NodeType.value:
        break; // 值块没有出口
      case NodeType.variable:
        for (final a in varAdd) {
          add('add', a);
        }
        add('next', next);
        break;
      case NodeType.weighted:
        for (var i = 0; i < branches.length; i++) {
          add('w$i', branches[i].to);
        }
        break;
      case NodeType.marker:
        // marker 的连线 = 指向「显示名」方块
        add('label', next);
        break;
      case NodeType.label:
      case NodeType.character:
      case NodeType.portrait:
      case NodeType.background:
      case NodeType.image:
      case NodeType.audio:
        add('next', next);
        break;
      case NodeType.branch:
        add('yes', yes);
        add('no', no);
        break;
      case NodeType.choice:
        for (var i = 0; i < options.length; i++) {
          add('opt$i', options[i].to);
        }
        break;
      case NodeType.jump:
        add('to', to);
        break;
      case NodeType.call:
        add('to', to);
        add('back', next);
        break;
      case NodeType.ret:
      case NodeType.end:
        break;
    }
    return out;
  }

  String? portTarget(String port) {
    for (final p in ports()) {
      if (p.key == port) return p.value;
    }
    return null;
  }

  void setPort(String port, String? target) {
    final t = (target != null && target.isEmpty) ? null : target;
    if (port == 'opt' || port.startsWith('opt')) {
      final i = int.tryParse(port.substring(port.startsWith('opt') ? 3 : 0));
      if (i != null && i >= 0 && i < options.length) {
        options[i].to = t ?? '';
      }
      return;
    }
    if (port.startsWith('w') && port.length > 1) {
      final i = int.tryParse(port.substring(1));
      if (i != null && i >= 0 && i < branches.length) {
        branches[i].to = t ?? '';
      }
      return;
    }
    if (port == 'add') {
      if (t == null) {
        varAdd.clear();
      } else if (!varAdd.contains(t)) {
        varAdd.add(t);
      }
      return;
    }
    if (port == 'cast') {
      if (t == null) {
        casts.clear();
      } else if (!casts.contains(t)) {
        casts.add(t);
      }
      return;
    }
    if (port == 'art') {
      if (t == null) {
        arts.clear();
      } else if (!arts.contains(t)) {
        arts.add(t);
      }
      return;
    }
    if (port == 'bg') {
      if (t == null) {
        bgs.clear();
      } else if (!bgs.contains(t)) {
        bgs.add(t);
      }
      return;
    }
    switch (port) {
      case 'next':
        next = t;
        break;
      case 'yes':
        yes = t;
        break;
      case 'no':
        no = t;
        break;
      case 'to':
        to = t;
        break;
      case 'back':
        next = t;
        break;
      default:
        break;
    }
  }

  /// 删掉指向 `dead` 的所有线
  void dropTargets(String dead) {
    for (final p in ports()) {
      if (p.value == dead) setPort(p.key, null);
    }
  }

  /// 卡片上显示的一行摘要
  String get summary {
    switch (type) {
      case NodeType.say:
        return text.replaceAll('\n', ' ');
      case NodeType.choice:
        return options.isEmpty
            ? '（还没有选项）'
            : '$prompt  ·  ${options.length} 个选项';
      case NodeType.branch:
        return cond.isEmpty ? '（没有条件）' : cond;
      case NodeType.set:
        return effects.isEmpty
            ? '（没有改动）'
            : effects.map((e) => e.display).join('，');
      case NodeType.jump:
        return to == null ? '（没连）' : '→ $to';
      case NodeType.call:
        return to == null ? '（没连）' : '进入 $to';
      case NodeType.ret:
        return '回到调用处';
      case NodeType.end:
        return endText.isEmpty ? ending : endText;
      case NodeType.script:
        final tag = scriptEngine == 'godot' ? 'GD' : 'RS';
        return '[$tag] ${src ?? '内联'} → ${entry}()';
      case NodeType.character:
        return '角色 $title · ${portraits.length} 张立绘';
      case NodeType.portrait:
        return '${asset ?? '（未选图）'}${expr != null ? ' · $expr' : ''}';
      case NodeType.background:
        return '${asset ?? '（未选图）'}${scene != null ? ' · $scene' : ''}';
      case NodeType.marker:
        return '标记 ${tag ?? '（未命名）'}';
      case NodeType.label:
        return text.isEmpty ? '（显示名为空）' : text;
      case NodeType.value:
        final e = expr ?? '';
        return e.isEmpty ? '（空值）' : '= $e';
      case NodeType.variable:
        return varAdd.isEmpty ? '${text}（没连值块）' : '${text} ← ${varAdd.length} 个值';
      case NodeType.image:
        return text.isEmpty ? (asset ?? '（图块）') : '$text · ${asset ?? ''}';
      case NodeType.audio:
        return '${tag ?? '音频'} [${audioKind}] ${asset ?? ''}';
      case NodeType.weighted:
        if (branches.isEmpty) return '（还没有路线）';
        return branches
            .map((b) => '${b.weight}:${b.to.isEmpty ? "?" : b.to}')
            .join('  ');
    }
  }

  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) return title!;
    switch (type) {
      case NodeType.say:
        return speaker == null || speaker!.isEmpty ? '旁白' : speaker!;
      case NodeType.choice:
        return '选择';
      case NodeType.branch:
        return '条件';
      case NodeType.set:
        return '变量';
      case NodeType.jump:
        return '跳转';
      case NodeType.call:
        return '子图调用';
      case NodeType.ret:
        return '返回';
      case NodeType.end:
        return '结局 · $ending';
      case NodeType.script:
        return '脚本';
      case NodeType.character:
        return '角色';
      case NodeType.portrait:
        return '立绘';
      case NodeType.background:
        return '背景';
      case NodeType.marker:
        return '标记名';
      case NodeType.label:
        return '显示名';
      case NodeType.value:
        return '值';
      case NodeType.variable:
        return '变量';
      case NodeType.weighted:
        return '加权分支';
      case NodeType.image:
        return '图块';
      case NodeType.audio:
        return '音频';
    }
  }
}

// ------------------------------------------------------------------ 角色

class Character {
  String name;
  String? color;
  String? avatar;

  Character({this.name = '', this.color, this.avatar});

  factory Character.fromJson(String key, dynamic j) {
    final m = (j is Map) ? j : const {};
    return Character(
      name: asString(m['name'], fallback: key),
      color: asOptString(m['color']),
      avatar: asOptString(m['avatar']),
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'name': name};
    if (color != null && color!.isNotEmpty) m['color'] = color;
    if (avatar != null && avatar!.isNotEmpty) m['avatar'] = avatar;
    return m;
  }

  Character copy() => Character(name: name, color: color, avatar: avatar);
}

// ------------------------------------------------------------------ 剧本

class Story {
  String title;
  String author;
  String desc;
  String version;
  String start;
  Map<String, Character> characters;
  Map<String, Object?> vars;
  List<StoryNode> nodes;
  /// 支线分组（折叠成合并块的数据层；画布渲染见 PLAN）
  List<Map<String, Object?>> groups;

  /// 完成度：节点 id -> wip/done（缺省 todo，不存储）
  Map<String, String> status;

  Story({
    this.title = '未命名',
    this.author = '',
    this.desc = '',
    this.version = '0.1.0',
    this.start = '',
    Map<String, Character>? characters,
    Map<String, Object?>? vars,
    List<StoryNode>? nodes,
    List<Map<String, Object?>>? groups,
    Map<String, String>? status,
  })  : characters = characters ?? <String, Character>{},
        vars = vars ?? <String, Object?>{},
        nodes = nodes ?? <StoryNode>[],
        groups = groups ?? <Map<String, Object?>>[],
        status = status ?? <String, String>{};

  factory Story.blank(String title) {
    final s = Story(title: title);
    s.characters['hero'] = Character(name: '我', color: '#9ECBFF');
    s.characters['yuki'] = Character(name: '雪', color: '#C3A6FF');
    final open = StoryNode(
      id: 'opening',
      type: NodeType.say,
      x: 0,
      y: 0,
      speaker: 'yuki',
      text: '……你终于来了。',
      next: 'end_1',
    );
    final end = StoryNode(
      id: 'end_1',
      type: NodeType.end,
      x: 0,
      y: 170,
      ending: 'first',
      endText: '故事从这里开始。',
    );
    s.nodes.addAll([open, end]);
    s.start = 'opening';
    return s;
  }

  StoryNode? nodeById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  bool get isEmpty => nodes.isEmpty;

  String freshId(String prefix) {
    var i = 1;
    while (nodeById('${prefix}_$i') != null) {
      i++;
    }
    return '${prefix}_$i';
  }

  void addNode(StoryNode n) {
    nodes.add(n);
    if (start.isEmpty) start = n.id;
  }

  void removeNode(String id) {
    nodes.removeWhere((n) => n.id == id);
    for (final n in nodes) {
      n.dropTargets(id);
    }
    if (start == id) {
      start = nodes.isEmpty ? '' : nodes.first.id;
    }
  }

  /// 直接后继 id（去重）
  List<String> successors(String id) {
    final n = nodeById(id);
    if (n == null) return const [];
    final out = <String>[];
    for (final p in n.ports()) {
      if (nodeById(p.value) != null && !out.contains(p.value)) {
        out.add(p.value);
      }
    }
    return out;
  }

  /// 从入口开始能走到的节点
  Set<String> reachable() {
    final seen = <String>{};
    final queue = <String>[];
    if (start.isNotEmpty) queue.add(start);
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      if (!seen.add(id)) continue;
      for (final s in successors(id)) {
        if (!seen.contains(s)) queue.add(s);
      }
    }
    return seen;
  }

  int get logicNodeCount => nodes.length;

  int get charCount {
    var n = 0;
    for (final node in nodes) {
      if (node.type == NodeType.say) n += node.text.length;
      if (node.type == NodeType.end) n += node.endText.length;
    }
    return n;
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'format': 'galatea.graph/1',
      'meta': {
        'title': title,
        'author': author,
        'desc': desc,
        'version': version,
        'start': start,
      },
      'characters': characters.map((k, v) => MapEntry(k, v.toJson())),
      'vars': vars,
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'groups': groups,
    };
    if (status.isNotEmpty) m['status'] = status;
    return m;
  }

  String toPrettyJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert(toJson())}\n';
  }

  factory Story.fromJson(Map<String, dynamic> m) {
    final meta = (m['meta'] is Map) ? m['meta'] as Map : const {};
    final chars = <String, Character>{};
    if (m['characters'] is Map) {
      (m['characters'] as Map).forEach((k, v) {
        chars['$k'] = Character.fromJson('$k', v);
      });
    }
    final vars = <String, Object?>{};
    if (m['vars'] is Map) {
      (m['vars'] as Map).forEach((k, v) {
        vars['$k'] = v is num || v is String || v is bool ? v : v?.toString();
      });
    }
    final groups = <Map<String, Object?>>[];
    if (m['groups'] is List) {
      for (final g in (m['groups'] as List)) {
        if (g is Map) groups.add(Map<String, Object?>.from(g));
      }
    }
    final status = <String, String>{};
    if (m['status'] is Map) {
      (m['status'] as Map).forEach((k, v) {
        if (v == 'wip' || v == 'done') status['$k'] = v as String;
      });
    }
    final nodes = <StoryNode>[];
    if (m['nodes'] is List) {
      for (final raw in (m['nodes'] as List)) {
        if (raw is Map) {
          nodes.add(StoryNode.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }
    return Story(
      title: asString(meta['title'], fallback: '未命名'),
      author: asString(meta['author']),
      desc: asString(meta['desc']),
      version: asString(meta['version'], fallback: '0.1.0'),
      start: asString(meta['start']),
      characters: chars,
      vars: vars,
      nodes: nodes,
      groups: groups,
      status: status,
    );
  }

  Story copy() => Story(
        title: title,
        author: author,
        desc: desc,
        version: version,
        start: start,
        characters: characters.map((k, v) => MapEntry(k, v.copy())),
        vars: Map<String, Object?>.from(vars),
        nodes: nodes.map((n) => n.copy()).toList(),
        groups: groups.map((g) => Map<String, Object?>.from(g)).toList(),
        status: Map<String, String>.from(status),
      );

  /// 完成度统计 (todo, wip, done)
  (int, int, int) progress() {
    var t = 0, w = 0, d = 0;
    for (final n in nodes) {
      switch (status[n.id] ?? 'todo') {
        case 'done': d++;
        case 'wip': w++;
        default: t++;
      }
    }
    return (t, w, d);
  }

  /// 分支级完成度：能顺着连线走到 End 的节点集合（反向 BFS）。
  Set<String> reachesEnd() {
    final rev = <String, List<String>>{};
    final ends = <String>[];
    for (final n in nodes) {
      if (n.type == NodeType.end) ends.add(n.id);
      for (final e in n.ports()) {
        rev.putIfAbsent(e.value, () => <String>[]).add(n.id);
      }
    }
    final reach = <String>{...ends};
    final queue = <String>[...ends];
    while (queue.isNotEmpty) {
      final v = queue.removeLast();
      for (final u in rev[v] ?? const <String>[]) {
        if (reach.add(u)) queue.add(u);
      }
    }
    return reach;
  }

  /// (以结尾收尾的节点数, 总节点数)
  (int, int) completion() {
    final r = reachesEnd();
    final done = nodes.where((n) => r.contains(n.id)).length;
    return (done, nodes.length);
  }

  void setStatus(String id, String value) {
    if (value == 'todo' || value.isEmpty) {
      status.remove(id);
    } else {
      status[id] = value;
    }
  }

  /// 思维导图式自动布局：从入口往下长，兄弟横向排开，孤岛扔到一边。
  void autoLayout() {
    // 竖屏屏幕窄：分支横向收紧，纵向照旧
    const colWidth = 220.0;
    const rowHeight = 180.0;
    final depth = <String, int>{};
    final byDepth = <int, List<String>>{};

    void visit(String id, int d) {
      final prev = depth[id];
      if (prev != null) {
        if (prev <= d) return;
      }
      depth[id] = d;
      byDepth.putIfAbsent(d, () => <String>[]).add(id);
      if (byDepth[d]!.where((e) => e == id).length > 1) {
        byDepth[d]!.removeLast();
      }
      for (final s in successors(id)) {
        visit(s, d + 1);
      }
    }

    if (start.isNotEmpty && nodeById(start) != null) {
      visit(start, 0);
    }
    var orphanDepth = (byDepth.keys.isEmpty ? 0 : byDepth.keys.reduce((a, b) => a > b ? a : b)) + 1;
    for (final n in nodes) {
      if (!depth.containsKey(n.id)) {
        depth[n.id] = orphanDepth;
        byDepth.putIfAbsent(orphanDepth, () => <String>[]).add(n.id);
      }
    }

    for (final entry in byDepth.entries) {
      final list = entry.value;
      for (var i = 0; i < list.length; i++) {
        final n = nodeById(list[i]);
        if (n == null) continue;
        n.x = (i - (list.length - 1) / 2.0) * colWidth;
        n.y = entry.key * rowHeight;
      }
    }
  }
}

// ------------------------------------------------------------------ 小工具

String asString(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  if (v is String) return v;
  return '$v';
}

String? asOptString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  return '$v';
}

double asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

double _round1(double v) =>
    double.parse(v.toStringAsFixed(1)) == v ? v : (v * 10).roundToDouble() / 10;

/// JSON 里的端口值可能是字符串也可能是数组
List<String> _strList(dynamic v) {
  if (v == null) return <String>[];
  if (v is String) return v.isEmpty ? <String>[] : <String>[v];
  if (v is List) {
    return v.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  }
  return <String>[];
}
