/// 剧本体检（Dart 版，与 Rust `lint.rs` 规则一致）。
/// 编辑器里每改一下就重跑一次，右侧面板实时显示。
library;

import '../models/graph.dart';
import 'expr.dart';

enum IssueLevel { error, warning, info }

class Issue {
  final IssueLevel level;
  final String? node;
  final String kind;
  final String msg;
  const Issue(this.level, this.node, this.kind, this.msg);

  String get tag {
    switch (level) {
      case IssueLevel.error:
        return '错误';
      case IssueLevel.warning:
        return '警告';
      case IssueLevel.info:
        return '提示';
    }
  }
}

List<Issue> lintStory(Story story) {
  final out = <Issue>[];

  if (story.start.trim().isEmpty) {
    out.add(const Issue(
        IssueLevel.error, null, 'start', '还没有设置入口节点（点节点卡片上的 ★）'));
  } else if (story.nodeById(story.start) == null) {
    out.add(Issue(IssueLevel.error, null, 'start',
        '入口节点 `${story.start}` 不存在'));
  }

  if (story.nodes.isEmpty) {
    out.add(const Issue(IssueLevel.error, null, 'empty', '剧本里一个节点都没有'));
    return out;
  }

  final endIds = <String>{};
  for (final n in story.nodes) {
    for (final p in n.ports()) {
      if (story.nodeById(p.value) == null) {
        out.add(Issue(IssueLevel.error, n.id, 'dangling',
            '`${p.key}` 端口连向了不存在的节点 `${p.value}`'));
      }
    }
    switch (n.type) {
      case NodeType.say:
      case NodeType.set:
        if (n.next == null || n.next!.isEmpty) {
          out.add(Issue(IssueLevel.warning, n.id, 'dead-end',
              '这里后面没有连线，剧情会断掉'));
        }
        break;
      case NodeType.branch:
        if (n.yes == null || n.no == null) {
          out.add(Issue(IssueLevel.warning, n.id, 'dead-end',
              '条件分支有一条边没连（真=${n.yes != null} 假=${n.no != null}）'));
        }
        if (n.cond.trim().isEmpty) {
          out.add(Issue(IssueLevel.warning, n.id, 'always-true',
              '条件为空，永远走「真」分支'));
        }
        break;
      case NodeType.choice:
        if (n.options.isEmpty) {
          out.add(Issue(
              IssueLevel.error, n.id, 'empty-choice', '选项节点一个选项都没有'));
        }
        for (var i = 0; i < n.options.length; i++) {
          final o = n.options[i];
          if (o.text.trim().isEmpty) {
            out.add(Issue(IssueLevel.warning, n.id, 'empty-text',
                '第 ${i + 1} 个选项没有文字'));
          }
          if (o.to.trim().isEmpty) {
            out.add(Issue(IssueLevel.error, n.id, 'dangling',
                '选项「${o.text}」没有连线'));
          }
        }
        break;
      case NodeType.jump:
      case NodeType.call:
        if (n.to == null || n.to!.isEmpty) {
          out.add(Issue(IssueLevel.error, n.id, 'dangling', '跳转目标为空'));
        }
        break;
      case NodeType.end:
        endIds.add(n.id);
        break;
      case NodeType.ret:
        break;
    }
  }

  if (story.nodeById(story.start) != null) {
    final seen = story.reachable();
    for (final n in story.nodes) {
      if (!seen.contains(n.id)) {
        out.add(Issue(IssueLevel.warning, n.id, 'unreachable',
            '从入口走不到这个节点（${nodeTypeLabel(n.type)}）'));
      }
    }
    if (!seen.any(endIds.contains)) {
      out.add(const Issue(
          IssueLevel.error, null, 'no-ending', '从入口出发走不到任何结局节点'));
    }
  }

  // 变量
  final defined = <String>{...story.vars.keys};
  final used = <String, String>{};
  void collect(String src, String nodeId) {
    final e = parseExpr(src);
    if (e == null) {
      out.add(Issue(IssueLevel.error, nodeId, 'bad-expr', '表达式写错了：$src'));
      return;
    }
    for (final v in exprVars(e)) {
      used.putIfAbsent(v, () => nodeId);
    }
  }

  for (final n in story.nodes) {
    switch (n.type) {
      case NodeType.branch:
        collect(n.cond, n.id);
        break;
      case NodeType.choice:
        for (final o in n.options) {
          collect(o.cond, n.id);
          for (final e in o.effects) {
            defined.add(e.target);
            collect(e.expr, n.id);
          }
        }
        break;
      case NodeType.set:
        for (final e in n.effects) {
          defined.add(e.target);
          collect(e.expr, n.id);
        }
        break;
      default:
        break;
    }
  }
  used.forEach((name, nodeId) {
    if (!defined.contains(name)) {
      out.add(Issue(IssueLevel.warning, nodeId, 'undefined-var',
          '变量 `$name` 从没被赋值过（会当成空值）'));
    }
  });

  out.sort((a, b) => a.level.index.compareTo(b.level.index));
  return out;
}

(int, int, int) lintSummary(List<Issue> issues) {
  var e = 0, w = 0, i = 0;
  for (final it in issues) {
    switch (it.level) {
      case IssueLevel.error:
        e++;
        break;
      case IssueLevel.warning:
        w++;
        break;
      case IssueLevel.info:
        i++;
        break;
    }
  }
  return (e, w, i);
}