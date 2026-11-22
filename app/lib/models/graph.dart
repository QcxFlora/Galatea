/// 剧情图模型 —— 必须与 Rust 侧 `galatea-core/src/graph.rs` 的 JSON 完全同构。
///
/// 一份 `.gala.json` 文件既是编辑器的工作文件，也是玩家端的剧本，
/// 也是 Rust 打包器 / 校验器读的输入。所以这里的字段名不要随便改。
library;

import 'dart:convert';

// ------------------------------------------------------------------ 节点类型

enum NodeType { say, choice, branch, set, jump, call, ret, end, script }

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

  // 台词
  String? speaker;
  String text;
  String? bg;
  String? portrait;

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

  // 结局
  String ending;
  String endText;

  // 自定义 Rust 脚本（src 路径 或 code 内联，二选一）
  String? src;
  String? code;
  String entry;

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
  })  : options = options ?? <Choice>[],
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
      text: asString(m['text']),
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
        if (speaker != null && speaker!.isNotEmpty) m['speaker'] = speaker;
        m['text'] = text;
        if (bg != null && bg!.isNotEmpty) m['bg'] = bg;
        if (portrait != null && portrait!.isNotEmpty) m['portrait'] = portrait;
        if (next != null && next!.isNotEmpty) m['next'] = next;
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
        if (src != null && src!.isNotEmpty) m['src'] = src;
        if (code != null && code!.isNotEmpty) m['code'] = code;
        m['entry'] = entry.isEmpty ? 'main' : entry;
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
      case NodeType.set:
      case NodeType.script:
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
        return '${src ?? '内联脚本'} → ${entry}()';
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

  Story({
    this.title = '未命名',
    this.author = '',
    this.desc = '',
    this.version = '0.1.0',
    this.start = '',
    Map<String, Character>? characters,
    Map<String, Object?>? vars,
    List<StoryNode>? nodes,
  })  : characters = characters ?? <String, Character>{},
        vars = vars ?? <String, Object?>{},
        nodes = nodes ?? <StoryNode>[];

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
    };
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
      );

  /// 思维导图式自动布局：从入口往下长，兄弟横向排开，孤岛扔到一边。
  void autoLayout() {
    const colWidth = 300.0;
    const rowHeight = 190.0;
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