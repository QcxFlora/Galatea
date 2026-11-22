//! 剧本体检：编辑器右侧会实时显示这些条目，CI 里也能跑。
//!
//! 关注四类问题：
//! - 结构性错误：入口不存在、连线指向空气、id 重复
//! - 断头路：节点没有出口、选项没有目标
//! - 死代码：从入口走不到的节点
//! - 状态错误：用了没定义的变量、条件永远为假

use crate::expr;
use crate::graph::{NodeKind, Story};
use crate::json::Json;
use std::collections::{BTreeMap, BTreeSet, VecDeque};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    Error,
    Warning,
    Info,
}

impl Level {
    pub fn tag(self) -> &'static str {
        match self {
            Level::Error => "错误",
            Level::Warning => "警告",
            Level::Info => "提示",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Issue {
    pub level: Level,
    pub node: Option<String>,
    pub kind: &'static str,
    pub msg: String,
}

impl std::fmt::Display for Issue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match &self.node {
            Some(n) => write!(f, "[{}] {} @{}", self.level.tag(), self.msg, n),
            None => write!(f, "[{}] {}", self.level.tag(), self.msg),
        }
    }
}

pub fn lint(story: &Story) -> Vec<Issue> {
    let mut out = Vec::new();

    // ---- 入口
    if story.meta.start.trim().is_empty() {
        out.push(Issue {
            level: Level::Error,
            node: None,
            kind: "start",
            msg: "还没有设置入口节点（meta.start 为空）".into(),
        });
    } else if story.node(&story.meta.start).is_none() {
        out.push(Issue {
            level: Level::Error,
            node: None,
            kind: "start",
            msg: format!("入口节点 `{}` 不存在", story.meta.start),
        });
    }

    if story.nodes.is_empty() {
        out.push(Issue {
            level: Level::Error,
            node: None,
            kind: "empty",
            msg: "剧本里一个节点都没有".into(),
        });
        return out;
    }

    // ---- 每条连线的目标是否存在 / 出口是否缺失
    let mut has_end_reachable_graph = BTreeSet::new();
    for n in &story.nodes {
        let ports = n.ports();
        for (port, target) in &ports {
            if story.node(target).is_none() {
                out.push(Issue {
                    level: Level::Error,
                    node: Some(n.id.clone()),
                    kind: "dangling",
                    msg: format!("`{}` 端口连向了不存在的节点 `{}`", port, target),
                });
            }
        }
        match &n.kind {
            NodeKind::Say { next, .. } | NodeKind::Set { next, .. } => {
                if next.is_none() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "dead-end",
                        msg: "这句台词后面没有连线，剧情会在这里断掉".into(),
                    });
                }
            }
            NodeKind::Script { next, .. } => {
                if next.is_none() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "dead-end",
                        msg: "脚本执行完之后没有连线，剧情会在这里断掉".into(),
                    });
                }
            }
            NodeKind::Branch { yes, no, cond } => {
                if yes.is_none() || no.is_none() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "dead-end",
                        msg: format!(
                            "条件分支只连了{}条边（真={} 假={}）",
                            if yes.is_some() || no.is_some() { "一" } else { "零" },
                            yes.is_some(),
                            no.is_some()
                        ),
                    });
                }
                if cond.trim().is_empty() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "always-true",
                        msg: "条件为空，永远走「真」分支".into(),
                    });
                }
                if let Ok(e) = expr::parse(cond) {
                    if e.is_const() {
                        out.push(Issue {
                            level: Level::Info,
                            node: Some(n.id.clone()),
                            kind: "const-cond",
                            msg: "条件是常量，分支可以合并".into(),
                        });
                    }
                }
            }
            NodeKind::Choice { options, .. } => {
                if options.is_empty() {
                    out.push(Issue {
                        level: Level::Error,
                        node: Some(n.id.clone()),
                        kind: "empty-choice",
                        msg: "选项节点一个选项都没有".into(),
                    });
                }
                for (i, o) in options.iter().enumerate() {
                    if o.text.trim().is_empty() {
                        out.push(Issue {
                            level: Level::Warning,
                            node: Some(n.id.clone()),
                            kind: "empty-text",
                            msg: format!("第 {} 个选项没有文字", i + 1),
                        });
                    }
                    if o.to.trim().is_empty() {
                        out.push(Issue {
                            level: Level::Error,
                            node: Some(n.id.clone()),
                            kind: "dangling",
                            msg: format!("选项「{}」没有连线", o.text),
                        });
                    }
                }
            }
            NodeKind::Jump { to } | NodeKind::Call { to, .. } => {
                if to.is_none() {
                    out.push(Issue {
                        level: Level::Error,
                        node: Some(n.id.clone()),
                        kind: "dangling",
                        msg: "跳转目标为空".into(),
                    });
                }
            }
            NodeKind::End { .. } => {
                has_end_reachable_graph.insert(n.id.clone());
            }
            NodeKind::Return => {}
        }
    }

    // ---- 可达性
    if story.node(&story.meta.start).is_some() {
        let mut seen: BTreeSet<String> = BTreeSet::new();
        let mut q: VecDeque<String> = VecDeque::new();
        q.push_back(story.meta.start.clone());
        while let Some(id) = q.pop_front() {
            if !seen.insert(id.clone()) {
                continue;
            }
            if let Some(n) = story.node(&id) {
                for (_, t) in n.ports() {
                    if story.node(&t).is_some() && !seen.contains(&t) {
                        q.push_back(t);
                    }
                }
            }
        }
        for n in &story.nodes {
            if !seen.contains(&n.id) {
                out.push(Issue {
                    level: Level::Warning,
                    node: Some(n.id.clone()),
                    kind: "unreachable",
                    msg: format!("从入口走不到这个节点（{}）", n.type_name()),
                });
            }
        }
        let any_end = seen.iter().any(|id| has_end_reachable_graph.contains(id));
        if !any_end {
            out.push(Issue {
                level: Level::Error,
                node: None,
                kind: "no-ending",
                msg: "从入口出发走不到任何结局节点".into(),
            });
        }
    }

    // ---- 变量
    let mut defined: BTreeSet<String> = story.vars.keys().cloned().collect();
    let mut used: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let collect = |src: &str, node: &str, used: &mut BTreeMap<String, Vec<String>>| {
        if let Ok(e) = expr::parse(src) {
            let mut vars = Vec::new();
            e.vars(&mut vars);
            for v in vars {
                used.entry(v).or_default().push(node.to_string());
            }
        }
    };
    for n in &story.nodes {
        match &n.kind {
            NodeKind::Branch { cond, .. } => collect(cond, &n.id, &mut used),
            NodeKind::Choice { options, .. } => {
                for o in options {
                    collect(&o.cond, &n.id, &mut used);
                    for e in &o.effects {
                        defined.insert(e.target.clone());
                        collect(&e.expr, &n.id, &mut used);
                    }
                }
            }
            NodeKind::Set { effects, .. } => {
                for e in effects {
                    defined.insert(e.target.clone());
                    collect(&e.expr, &n.id, &mut used);
                }
            }
            _ => {}
        }
    }
    for (name, nodes) in used {
        if !defined.contains(&name) {
            out.push(Issue {
                level: Level::Warning,
                node: nodes.first().cloned(),
                kind: "undefined-var",
                msg: format!("变量 `{}` 从没被赋值过（会当成空值对待）", name),
            });
        }
    }

    // ---- 变量类型混用（数字 / 字符串 / 布尔）
    let mut kinds: BTreeMap<String, BTreeSet<&'static str>> = BTreeMap::new();
    for (k, v) in &story.vars {
        kinds.entry(k.clone()).or_default().insert(type_of(v));
    }
    for (name, ks) in kinds {
        if ks.len() > 1 {
            out.push(Issue {
                level: Level::Info,
                node: None,
                kind: "var-type",
                msg: format!("变量 `{}` 的初值类型有点混乱：{:?}", name, ks),
            });
        }
    }

    out.sort_by(|a, b| b.level.cmp(&a.level));
    out
}

fn type_of(v: &Json) -> &'static str {
    match v {
        Json::Num(_) => "数字",
        Json::Str(_) => "字符串",
        Json::Bool(_) => "布尔",
        Json::Null => "空",
        Json::Arr(_) => "数组",
        Json::Obj(_) => "对象",
    }
}

/// 汇总：有多少错误 / 警告 / 提示
pub fn summary(issues: &[Issue]) -> (usize, usize, usize) {
    let mut e = 0;
    let mut w = 0;
    let mut i = 0;
    for it in issues {
        match it.level {
            Level::Error => e += 1,
            Level::Warning => w += 1,
            Level::Info => i += 1,
        }
    }
    (e, w, i)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graph::{Effect, NodeKind, Op, Story};

    #[test]
    fn clean_story_has_no_errors() {
        let mut s = Story::new("t", "a");
        s.add_node(Story::mk_say("a", 0.0, 0.0, None, "你好"));
        s.add_node(Story::mk_end("e", 0.0, 100.0, "good", "完"));
        s.node_mut("a").unwrap().set_port("next", Some("e".into()));
        let issues = lint(&s);
        let (e, _, _) = summary(&issues);
        assert_eq!(e, 0, "{:?}", issues);
    }

    #[test]
    fn catches_dangling_and_unreachable() {
        let mut s = Story::new("t", "a");
        s.add_node(Story::mk_say("a", 0.0, 0.0, None, "你好"));
        s.add_node(Story::mk_end("e", 0.0, 100.0, "good", "完"));
        s.add_node(Story::mk_say("orphan", 0.0, 0.0, None, "孤岛"));
        s.node_mut("a").unwrap().set_port("next", Some("ghost".into()));
        let issues = lint(&s);
        assert!(issues.iter().any(|i| i.kind == "dangling"));
        assert!(issues.iter().any(|i| i.kind == "unreachable"));
        assert!(issues.iter().any(|i| i.kind == "no-ending"));
    }

    #[test]
    fn catches_undefined_var() {
        let mut s = Story::new("t", "a");
        s.add_node(Story::mk_say("a", 0.0, 0.0, None, "你好"));
        s.add_node(crate::graph::Node {
            id: "b".into(),
            x: 0.0,
            y: 0.0,
            title: None,
            kind: NodeKind::Set {
                effects: vec![Effect::new("aff_inner", Op::Add, "1")],
                next: Some("e".into()),
            },
        });
        s.add_node(crate::graph::Node {
            id: "c".into(),
            x: 0.0,
            y: 0.0,
            title: None,
            kind: NodeKind::Branch {
                cond: "aff > 3".into(),
                yes: Some("e".into()),
                no: Some("e".into()),
            },
        });
        s.add_node(Story::mk_end("e", 0.0, 100.0, "good", "完"));
        s.node_mut("a").unwrap().set_port("next", Some("b".into()));
        s.node_mut("b").unwrap().set_port("next", Some("c".into()));
        let issues = lint(&s);
        assert!(
            issues.iter().any(|i| i.kind == "undefined-var"),
            "{:?}",
            issues
        );
    }
}