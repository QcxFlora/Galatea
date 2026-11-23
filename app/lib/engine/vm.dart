/// 剧情解释器（Dart 实现）—— 与 Rust `galatea-core/src/vm.rs` 行为对齐。
///
/// 编辑器内嵌的"试玩"用它，因为要即时响应、还能随时改图重跑；
/// 发布版播放器会换成通过 FFI 调 Rust 的那一份，接口保持一致。
library;

import '../models/graph.dart';
import 'expr.dart';

class OptionView {
  final int index;
  final String text;
  final String target;
  const OptionView(this.index, this.text, this.target);
}

sealed class VmEvent {
  const VmEvent();
}

class SayEvent extends VmEvent {
  final String node;
  final String? speaker;
  final String speakerName;
  final String? color;
  final String text;
  final String? bg;
  final String? portrait;
  /// 多人同框时除第一张外的立绘
  final List<String> extraPortraits;
  const SayEvent({
    required this.node,
    required this.speaker,
    required this.speakerName,
    required this.color,
    required this.text,
    this.bg,
    this.portrait,
    this.extraPortraits = const <String>[],
  });
}

class ChoicesEvent extends VmEvent {
  final String node;
  final String prompt;
  final List<OptionView> options;
  const ChoicesEvent(this.node, this.prompt, this.options);
}

class EndingEvent extends VmEvent {
  final String node;
  final String ending;
  final String text;
  const EndingEvent(this.node, this.ending, this.text);
}

class HaltEvent extends VmEvent {
  final String reason;
  const HaltEvent(this.reason);
}

/// 走到音频块：播放/切换音频
class AudioEvent extends VmEvent {
  final String node;
  final String key;
  final String path;
  final String kind; // bgm | sfx | voice
  final bool looping;
  final double volume;
  const AudioEvent({
    required this.node,
    required this.key,
    required this.path,
    required this.kind,
    required this.looping,
    required this.volume,
  });
}

/// 确定性随机数（xorshift64*），与 Rust 侧同算法：
/// 同一种子 + 同样调用次数 = 同样结果，所以存档里存下 state 就能复现。
class Rng {
  int state;
  Rng(int seed) : state = seed == 0 ? 0x9E3779B97F4A7C15 : seed;

  int nextU64() {
    var x = state;
    x ^= x >>> 12;
    x ^= x << 25;
    x ^= x >>> 27;
    state = x;
    return x * 0x2545F4914F6CDD1D;
  }

  /// [0, 1)
  double nextF64() => (nextU64() >>> 11) / 9007199254740992.0;
}

class _Pending {
  final String node;
  final String prompt;
  final List<OptionView> options;
  final List<Choice> originals;
  _Pending(this.node, this.prompt, this.options, this.originals);
}

class _Snap {
  final String? pc;
  final Map<String, Object?> vars;
  final List<String?> stack;
  final Map<String, int> visited;
  final Set<String> taken;
  final int logLen;
  _Snap(this.pc, this.vars, this.stack, this.visited, this.taken, this.logLen);
}

const int _maxSnapshots = 256;
const int _maxAutoSteps = 4096;
const int _maxCallDepth = 64;

class Vm {
  final Story story;
  String? pc;
  Map<String, Object?> vars;
  final List<String?> stack = <String?>[];
  final Map<String, int> visited = <String, int>{};
  final Set<String> taken = <String>{};
  final List<String> log = <String>[];
  final List<_Snap> _snapshots = <_Snap>[];
  _Pending? _pending;
  String? endedEnding;
  String? endedText;
  int autoSteps = 0;
  Rng rng = Rng(DateTime.now().microsecondsSinceEpoch);

  Vm(this.story)
      : pc = story.start.isEmpty ? null : story.start,
        vars = Map<String, Object?>.from(story.vars);

  void restart() {
    // 每局换种子，一局之内确定
    rng = Rng(rng.nextU64() ^ 0x5DEECE66D);
    pc = story.start.isEmpty ? null : story.start;
    vars = Map<String, Object?>.from(story.vars);
    stack.clear();
    visited.clear();
    taken.clear();
    log.clear();
    _snapshots.clear();
    _pending = null;
    endedEnding = null;
    endedText = null;
  }

  // ------------------------------------------------------------- 变量

  Object? varValue(String path) {
    final parts = path.split('.').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    Object? cur = vars[parts.first];
    for (var i = 1; i < parts.length; i++) {
      if (cur is Map) {
        cur = cur[parts[i]];
      } else {
        return null;
      }
    }
    return cur;
  }

  void setVar(String path, Object? v) {
    final parts = path.split('.').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return;
    if (parts.length == 1) {
      vars[parts.first] = v;
      return;
    }
    var cur = vars[parts.first];
    if (cur is! Map) {
      cur = <String, Object?>{};
      vars[parts.first] = cur;
    }
    for (var i = 1; i < parts.length - 1; i++) {
      var next = (cur as Map)[parts[i]];
      if (next is! Map) {
        next = <String, Object?>{};
        cur[parts[i]] = next;
      }
      cur = next;
    }
    (cur as Map)[parts.last] = v;
  }

  bool evalCond(String src) {
    if (src.trim().isEmpty) return true;
    final e = parseExpr(src);
    if (e == null) return false;
    return truthy(evalExprTree(e, varValue));
  }

  void _apply(List<Effect> effects) {
    for (final e in effects) {
      final rhs = evalExpr(e.expr, varValue) ?? 0;
      final cur = varValue(e.target);
      Object? next;
      switch (e.op) {
        case EffectOp.set:
          next = rhs;
          break;
        case EffectOp.add:
          if (cur is String) {
            next = '$cur${display(rhs)}';
          } else {
            next = toNum(cur) + toNum(rhs);
          }
          break;
        case EffectOp.sub:
          next = toNum(cur) - toNum(rhs);
          break;
        case EffectOp.mul:
          next = toNum(cur) * toNum(rhs);
          break;
        case EffectOp.max:
          next = toNum(cur) > toNum(rhs) ? toNum(cur) : toNum(rhs);
          break;
        case EffectOp.min:
          next = toNum(cur) < toNum(rhs) ? toNum(cur) : toNum(rhs);
          break;
        case EffectOp.toggle:
          next = !truthy(cur);
          break;
      }
      setVar(e.target, next);
    }
  }

  // ------------------------------------------------------------- 快照

  void _pushSnapshot() {
    if (_snapshots.length >= _maxSnapshots) _snapshots.removeAt(0);
    _snapshots.add(_Snap(
      pc,
      Map<String, Object?>.from(vars),
      List<String?>.from(stack),
      Map<String, int>.from(visited),
      Set<String>.from(taken),
      log.length,
    ));
  }

  bool get canUndo => _snapshots.length >= 2;

  bool undo() {
    if (_snapshots.length < 2) return false;
    _snapshots.removeLast(); // 当前停顿点
    final s = _snapshots.removeLast(); // 目标停顿点
    pc = s.pc;
    vars = s.vars;
    stack
      ..clear()
      ..addAll(s.stack);
    visited
      ..clear()
      ..addAll(s.visited);
    taken
      ..clear()
      ..addAll(s.taken);
    if (log.length > s.logLen) log.removeRange(s.logLen, log.length);
    _pending = null;
    endedEnding = null;
    endedText = null;
    return true;
  }

  // ------------------------------------------------------------- 驱动

  VmEvent step() {
    final p = _pending;
    if (p != null) {
      return ChoicesEvent(p.node, p.prompt, p.options);
    }
    autoSteps = 0;
    while (true) {
      autoSteps++;
      if (autoSteps > _maxAutoSteps) {
        return const HaltEvent('连续执行了太多节点，可能是死循环（检查跳转有没有绕圈）');
      }
      final id = pc;
      if (id == null) return const HaltEvent('剧情结束');
      final node = story.nodeById(id);
      if (node == null) {
        return HaltEvent('找不到节点 `$id`（连线指向了不存在的东西）');
      }
      visited[id] = (visited[id] ?? 0) + 1;

      switch (node.type) {
        case NodeType.say:
          _pushSnapshot();

          // art 端口（多值）→ 立绘方块里的资源路径
          final artPaths = <String>[];
          for (final id in node.arts) {
            final an = story.nodeById(id);
            if (an != null && (an.type == NodeType.portrait || an.type == NodeType.image) && an.asset != null) {
              artPaths.add(an.asset!);
            }
          }

          // cast 端口（多值）→ 每个人的显示名
          final names = <String>[];
          String? firstKey;
          for (final id in node.casts) {
            final cn = story.nodeById(id);
            if (cn == null) {
              // 兼容：cast 里直接写了 characters 表的 key
              final info = _speakerInfo(id, null);
              if (info.name.isNotEmpty && !names.contains(info.name)) {
                names.add(info.name);
              }
              firstKey ??= id;
              continue;
            }
            if (cn.type == NodeType.label) {
              if (cn.text.isNotEmpty && !names.contains(cn.text)) names.add(cn.text);
              firstKey ??= cn.id;
              continue;
            }
            final key = cn.tag;
            if (key == null || key.isEmpty) continue;
            final info = _speakerInfo(key, null);
            if (info.name.isNotEmpty && !names.contains(info.name)) {
              names.add(info.name);
            }
            firstKey ??= key;
          }

          // bg 端口（取第一个）
          String? bgPath;
          if (node.bgs.isNotEmpty) {
            final bn = story.nodeById(node.bgs.first);
            if (bn != null && (bn.type == NodeType.background || bn.type == NodeType.image)) bgPath = bn.asset;
          }

          final display = names.join('、');
          final info = _speakerInfo(firstKey, artPaths.isNotEmpty ? artPaths.first : node.portrait);
          log.add(display.isEmpty ? node.text : '$display：${node.text}');
          pc = node.next;
          return SayEvent(
            node: id,
            speaker: firstKey,
            speakerName: display,
            color: info.color,
            text: node.text,
            bg: bgPath ?? node.bg,
            portrait: artPaths.isNotEmpty ? artPaths.first : info.portrait,
            extraPortraits:
                artPaths.length > 1 ? artPaths.sublist(1) : const <String>[],
          );
        case NodeType.choice:
          final views = <OptionView>[];
          for (var i = 0; i < node.options.length; i++) {
            final o = node.options[i];
            if (o.cond.trim().isNotEmpty && !evalCond(o.cond)) continue;
            if (o.once && taken.contains('$id#$i')) continue;
            if (o.to.isEmpty) continue;
            views.add(OptionView(i, o.text, o.to));
          }
          if (views.isEmpty) {
            pc = null;
            return HaltEvent('选项节点 `$id` 没有任何可选项（条件全不满足？）');
          }
          _pushSnapshot();
          _pending = _Pending(id, node.prompt, views, node.options);
          return ChoicesEvent(id, node.prompt, views);
        case NodeType.branch:
          pc = evalCond(node.cond) ? node.yes : node.no;
          if (pc == null) {
            return HaltEvent('条件节点 `$id` 有一条分支没连线');
          }
          break;
        case NodeType.set:
          _apply(node.effects);
          pc = node.next;
          break;
        case NodeType.variable:
          // 变量块：把 add 端口连着的值块累加进变量
          for (final vid in node.varAdd) {
            final vn = story.nodeById(vid);
            if (vn != null && vn.type == NodeType.value) {
              final delta = toNum(evalExpr(vn.text, varValue) ?? 0);
              final cur = toNum(varValue(node.text));
              setVar(node.text, cur + delta);
            }
          }
          pc = node.next;
          break;
        case NodeType.value:
          // 值块是数据，不进流程
          pc = null;
          break;
        case NodeType.weighted:
          final pool = <List<Object>>[]; // [weight, to]
          for (final b in node.branches) {
            if (b.cond.trim().isNotEmpty && !evalCond(b.cond)) continue;
            if (b.to.isEmpty) continue;
            final w = toNum(evalExpr(b.weight, varValue) ?? 0);
            if (w > 0) pool.add([w, b.to]);
          }
          if (pool.isEmpty) {
            pc = null;
            return HaltEvent('加权分支 `$id` 没有可用路线（权重全为 0 或条件全不满足）');
          }
          final total = pool.fold<double>(0, (a, e) => a + (e[0] as double));
          var r = rng.nextF64() * total;
          var chosen = pool.last[1] as String;
          for (final e in pool) {
            final w = e[0] as double;
            if (r <= w) {
              chosen = e[1] as String;
              break;
            }
            r -= w;
          }
          pc = chosen;
          break;
        case NodeType.jump:
          pc = node.to;
          break;
        case NodeType.call:
          if (stack.length >= _maxCallDepth) {
            return const HaltEvent('子图调用嵌套太深（是不是递归了？）');
          }
          stack.add(node.next);
          pc = node.to;
          break;
        case NodeType.ret:
          pc = stack.isEmpty ? null : stack.removeLast();
          break;
        case NodeType.marker:
        case NodeType.label:
        case NodeType.character:
        case NodeType.portrait:
        case NodeType.image:
        case NodeType.background:
          // 资源 / 标记方块：不进演出流程，直接跳过
          pc = node.next;
          break;
        case NodeType.audio:
          pc = node.next;
          return AudioEvent(
            node: id,
            key: node.tag ?? '',
            path: node.asset ?? '',
            kind: node.audioKind,
            looping: node.audioLoop,
            volume: node.audioVolume,
          );
        case NodeType.script:
          // 编辑器内不执行自定义脚本（Rust 沙箱与 GDScript 都不跑），
          // 只留一条记录，保证图还能玩通。
          if (node.scriptEngine == 'godot') {
            log.add('（⚙ GDScript 节点 ${node.entry}()：需要 Godot 运行时）');
          } else {
            log.add('（⚙ Rust 脚本节点 ${node.entry}()：编辑器内跳过）');
          }
          pc = node.next;
          break;
        case NodeType.end:
          pc = null;
          endedEnding = node.ending;
          endedText = node.endText;
          return EndingEvent(id, node.ending, node.endText);
      }
    }
  }

  _SpeakerInfo _speakerInfo(String? key, String? portrait) {
    if (key == null || key.isEmpty) return _SpeakerInfo('', null, null);

    // 1. 标记名方块 → 顺着 next 找「显示名」方块
    for (final n in story.nodes) {
      if (n.type == NodeType.marker && (n.tag == key || n.id == key)) {
        final labelNode = story.nodeById(n.next);
        if (labelNode != null && labelNode.type == NodeType.label) {
          return _SpeakerInfo(labelNode.text, null, portrait);
        }
        return _SpeakerInfo(n.tag ?? key, null, portrait);
      }
    }
    // 2. 角色方块（v0.2）
    for (final n in story.nodes) {
      if (n.type == NodeType.character && (n.tag == key || n.id == key)) {
        return _SpeakerInfo(
          n.text.isEmpty ? (n.tag ?? key) : n.text,
          null,
          portrait ?? (n.portraits.isNotEmpty ? n.portraits.first : null),
        );
      }
    }
    // 3. 传统 characters 表
    final c = story.characters[key];
    if (c == null) return _SpeakerInfo(key, null, portrait);
    return _SpeakerInfo(
      c.name.isEmpty ? key : c.name,
      c.color,
      portrait ?? c.avatar,
    );
  }

  /// 玩家选了第 visibleIndex 个（0 起）选项
  VmEvent choose(int visibleIndex) {
    final p = _pending;
    if (p == null) return const HaltEvent('现在没有等待选择');
    if (visibleIndex < 0 || visibleIndex >= p.options.length) {
      return HaltEvent('选项下标 $visibleIndex 越界');
    }
    final view = p.options[visibleIndex];
    _pending = null;
    if (view.index < p.originals.length) {
      _apply(p.originals[view.index].effects);
    }
    taken.add('${p.node}#${view.index}');
    pc = view.target.isEmpty ? null : view.target;
    return step();
  }

  // ------------------------------------------------------------- 存档

  Map<String, dynamic> saveJson() => <String, dynamic>{
        'pc': pc,
        'vars': vars,
        'stack': stack,
        'visited': visited,
        'taken': taken.toList(),
        'log': log,
        if (endedEnding != null)
          'ended': {'ending': endedEnding, 'text': endedText ?? ''},
        // u64 超出 JSON double 精度，存字符串
        'rng': rng.state.toString(),
      };

  void loadJson(Map<String, dynamic> j) {
    pc = j['pc'] as String?;
    vars = <String, Object?>{};
    if (j['vars'] is Map) {
      (j['vars'] as Map).forEach((k, v) => vars['$k'] = v);
    }
    stack
      ..clear()
      ..addAll((j['stack'] is List)
          ? (j['stack'] as List).map((e) => e as String?)
          : const <String?>[]);
    visited.clear();
    if (j['visited'] is Map) {
      (j['visited'] as Map)
          .forEach((k, v) => visited['$k'] = v is num ? v.toInt() : 0);
    }
    taken
      ..clear()
      ..addAll((j['taken'] is List)
          ? (j['taken'] as List).map((e) => '$e')
          : const <String>[]);
    log
      ..clear()
      ..addAll(
          (j['log'] is List) ? (j['log'] as List).map((e) => '$e') : const <String>[]);
    final rngRaw = j['rng'];
    if (rngRaw is String) {
      final v = int.tryParse(rngRaw);
      if (v != null) rng = Rng(v);
    } else if (rngRaw is num) {
      rng = Rng(rngRaw.toInt());
    }
    final ended = j['ended'];
    if (ended is Map) {
      endedEnding = ended['ending'] as String?;
      endedText = ended['text'] as String?;
    } else {
      endedEnding = null;
      endedText = null;
    }
    _pending = null;
    _snapshots.clear();
  }

  (int, int) progress() => (visited.length, story.nodes.length);
}

class _SpeakerInfo {
  final String name;
  final String? color;
  final String? portrait;
  const _SpeakerInfo(this.name, this.color, this.portrait);
}