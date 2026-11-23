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
                // cast 端口允许直接写 characters 表的 key —— VM 明确支持这种旧剧本写法
                // （见 vm.rs「兼容：cast 里直接写了 characters 表的 key」）。
                // lint 不能比运行时更严，否则合法剧本会被误判成错误。
                if port == "cast" && story.characters.contains_key(target) {
                    continue;
                }
                out.push(Issue {
                    level: Level::Error,
                    node: Some(n.id.clone()),
                    kind: "dangling",
                    msg: format!("`{}` 端口连向了不存在的节点 `{}`", port, target),
                });
            }
        }
        match &n.kind {
            NodeKind::Loop { expr, body, max_iters, .. } => {
                if expr.trim().is_empty() {
                    out.push(Issue { level: Level::Error, node: Some(n.id.clone()), kind: "loop-expr",
                        msg: "循环块缺少 expr（次数/条件/列表变量名）".into() });
                }
                if body.is_none() {
                    out.push(Issue { level: Level::Error, node: Some(n.id.clone()), kind: "loop-body",
                        msg: "循环块没有 body 连线。怎么修：从 body 端口拖线到要循环的子图入口".into() });
                }
                if *max_iters == 0 {
                    out.push(Issue { level: Level::Error, node: Some(n.id.clone()), kind: "loop-max",
                        msg: "maxIters 为 0，循环一次都不会跑".into() });
                }
            }
            NodeKind::Image { key, path, .. } => {
                if key.trim().is_empty() {
                    out.push(Issue { level: Level::Error, node: Some(n.id.clone()), kind: "image-key",
                        msg: "图块缺少 key（资源标识）。怎么修：填一个唯一名字，供连线引用".into() });
                }
                if path.trim().is_empty() {
                    out.push(Issue { level: Level::Error, node: Some(n.id.clone()), kind: "image-path",
                        msg: "图块缺少 path（图片路径）。怎么修：指向 .webp/.png/.jpg 资源".into() });
                }
            }
            NodeKind::Audio { key, path, volume, .. } => {
                if key.trim().is_empty() {
                    out.push(Issue { level: Level::Error, node: Some(n.id.clone()), kind: "audio-key",
                        msg: "音频块缺少 key".into() });
                }
                if path.trim().is_empty() {
                    out.push(Issue { level: Level::Error, node: Some(n.id.clone()), kind: "audio-path",
                        msg: "音频块缺少 path。怎么修：指向 .ogg/.mp3/.wav 资源".into() });
                }
                if !(0.0..=1.0).contains(volume) {
                    out.push(Issue { level: Level::Error, node: Some(n.id.clone()), kind: "audio-volume",
                        msg: format!("音量 {} 超出 0.0..1.0", volume) });
                }
            }
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
            NodeKind::Script { engine, src, entry, next, .. } => {
                if cfg!(target_os = "android") && matches!(engine, crate::graph::ScriptEngine::Godot) {
                    out.push(Issue { level: Level::Error, node: Some(n.id.clone()), kind: "mobile-godot",
                        msg: "移动端引擎不支持 godot 脚本块。怎么修：在主机端（桌面）编辑，或改用 rust 引擎".into() });
                }
                if matches!(engine, crate::graph::ScriptEngine::Godot) {
                    match src {
                        None => out.push(Issue { level: Level::Error, node: Some(n.id.clone()),
                            kind: "godot-src",
                            msg: "Godot 脚本块没填引用路径（src）。怎么修：指定一个 .gd 文件，如 res://scripts/minigame.gd".into() }),
                        Some(p) if p.trim().is_empty() => out.push(Issue { level: Level::Error, node: Some(n.id.clone()),
                            kind: "godot-src",
                            msg: "Godot 脚本块的引用路径是空的".into() }),
                        Some(p) if !p.trim_end_matches('/').ends_with(".gd") => out.push(Issue { level: Level::Error, node: Some(n.id.clone()),
                            kind: "godot-src",
                            msg: format!("Godot 脚本引用应是 .gd 文件，实际 `{}`", p) }),
                        _ => {}
                    }
                    if entry.trim().is_empty() {
                        out.push(Issue { level: Level::Warning, node: Some(n.id.clone()),
                            kind: "godot-entry",
                            msg: "入口函数名为空，运行时会回落到 run()".into() });
                    }
                }
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
            NodeKind::Variable { name, add, next } => {
                if name.trim().is_empty() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "var-name",
                        msg: "变量块没有写变量名".into(),
                    });
                }
                if add.is_empty() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "var-add",
                        msg: format!("变量 `{}` 没有连值块（不会加到任何值）", name),
                    });
                }
                for vid in add {
                    match story.node(vid) {
                        Some(vn) => {
                            if !matches!(vn.kind, NodeKind::Value { .. }) {
                                out.push(Issue {
                                    level: Level::Warning,
                                    node: Some(n.id.clone()),
                                    kind: "var-add-target",
                                    msg: "变量块的 add 端口应该连「值块」".into(),
                                });
                            }
                        }
                        None => out.push(Issue {
                            level: Level::Error,
                            node: Some(n.id.clone()),
                            kind: "dangling",
                            msg: format!("add 端口连向了不存在的方块 `{}`", vid),
                        }),
                    }
                }
                if next.is_none() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "dead-end",
                        msg: "变量块后面没有连线".into(),
                    });
                }
            }
            NodeKind::Value { expr } => {
                if expr.trim().is_empty() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "value-empty",
                        msg: "值块是空的".into(),
                    });
                } else if expr::parse(expr).is_err() {
                    out.push(Issue {
                        level: Level::Error,
                        node: Some(n.id.clone()),
                        kind: "bad-expr",
                        msg: format!("值块表达式写错了：{}", expr),
                    });
                }
            }
            NodeKind::Weighted { branches, .. } => {
                if branches.is_empty() {
                    out.push(Issue {
                        level: Level::Error,
                        node: Some(n.id.clone()),
                        kind: "weighted-empty",
                        msg: "加权分支一条路都没有".into(),
                    });
                }
                let mut all_zero = true;
                for (i, b) in branches.iter().enumerate() {
                    if b.to.trim().is_empty() {
                        out.push(Issue {
                            level: Level::Error,
                            node: Some(n.id.clone()),
                            kind: "dangling",
                            msg: format!("第 {} 条加权路线没有连线", i + 1),
                        });
                    }
                    if expr::parse(&b.weight).is_err() {
                        out.push(Issue {
                            level: Level::Error,
                            node: Some(n.id.clone()),
                            kind: "bad-expr",
                            msg: format!("第 {} 条路线的权重写错了：{}", i + 1, b.weight),
                        });
                    } else if let Ok(e) = expr::parse(&b.weight) {
                        if e.is_const() {
                            let v = crate::expr::to_num(&e.eval(&|_| crate::json::Json::Null));
                            if v > 0.0 {
                                all_zero = false;
                            }
                        } else {
                            all_zero = false; // 动态权重，无法静态判断
                        }
                    }
                }
                if !branches.is_empty() && all_zero {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "weighted-zero",
                        msg: "所有路线的权重都是 0，永远走不出去".into(),
                    });
                }
            }
            NodeKind::Label { tag, text, next } => {
                if text.trim().is_empty() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "label-text",
                        msg: "显示块是空的".into(),
                    });
                }
                if let Some(t) = tag {
                    if t.trim().is_empty() {
                        out.push(Issue {
                            level: Level::Warning,
                            node: Some(n.id.clone()),
                            kind: "label-tag",
                            msg: "显示块的 tag 是空的".into(),
                        });
                    }
                }
                let _ = next;
            }
            NodeKind::Label { text, .. } => {
                if text.trim().is_empty() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "label-text",
                        msg: "显示名方块是空的".into(),
                    });
                }
            }
            NodeKind::Character { key, next, .. } => {
                if key.trim().is_empty() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "char-key",
                        msg: "角色方块缺 key".into(),
                    });
                }
                let _ = next;
            }
            NodeKind::Portrait { asset, .. } | NodeKind::Background { asset, .. } => {
                if asset.trim().is_empty() {
                    out.push(Issue {
                        level: Level::Warning,
                        node: Some(n.id.clone()),
                        kind: "asset",
                        msg: "资源方块没有填资源路径".into(),
                    });
                }
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
            // 资源方块（角色/立绘/背景）不参与流程，不需要"可达"
            if is_asset_kind(&n.kind) {
                continue;
            }
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

    // ---- 分组 / 合并显示
    let mut seen_in_group: BTreeMap<String, String> = BTreeMap::new();
    for g in &story.groups {
        for nid in &g.nodes {
            if story.node(nid).is_none() {
                out.push(Issue {
                    level: Level::Error,
                    node: Some(g.id.clone()),
                    kind: "group-dangling",
                    msg: format!("分组 `{}` 里包含不存在的方块 `{}`", g.title, nid),
                });
            }
            if let Some(prev) = seen_in_group.get(nid) {
                out.push(Issue {
                    level: Level::Warning,
                    node: Some(g.id.clone()),
                    kind: "group-dup",
                    msg: format!("方块 `{}` 同时属于分组 `{}` 和 `{}`", nid, prev, g.title),
                });
            } else {
                seen_in_group.insert(nid.clone(), g.title.clone());
            }
        }
        if let Some(p) = &g.parent {
            if !story.groups.iter().any(|x| &x.id == p) {
                out.push(Issue {
                    level: Level::Error,
                    node: Some(g.id.clone()),
                    kind: "group-parent",
                    msg: format!("分组 `{}` 的父分组 `{}` 不存在", g.title, p),
                });
            }
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
    use crate::graph::AudioKind;
    use super::*;
    use crate::graph::{Effect, Node, NodeKind, Op, ScriptEngine, Story};

    #[test]
    fn image_audio_validation() {
        let mut s = Story::new("t", "a");
        s.add_node(Node { id: "img".into(), x: 0.0, y: 0.0, title: None,
            kind: NodeKind::Image { key: "".into(), path: "".into(), label: None, next: Some("a".into()) } });
        s.add_node(Node { id: "aud".into(), x: 0.0, y: 0.0, title: None,
            kind: NodeKind::Audio { key: "b".into(), path: "x.ogg".into(),
                kind: AudioKind::Sfx, looping: false, volume: 1.5, next: Some("a".into()) } });
        s.add_node(Story::mk_say("a", 0.0, 0.0, None, "hi"));
        s.add_node(Story::mk_end("e", 0.0, 0.0, "g", "完"));
        s.node_mut("a").unwrap().set_port("next", Some("e".into()));
        let issues = lint(&s);
        assert!(issues.iter().any(|i| i.kind == "image-key"), "缺 key 要报错");
        assert!(issues.iter().any(|i| i.kind == "image-path"), "缺 path 要报错");
        assert!(issues.iter().any(|i| i.kind == "audio-volume"), "音量越界要报错");
        assert!(is_asset_kind(&NodeKind::Image { key: "k".into(), path: "p".into(), label: None, next: None }),
            "图块是资源块");
    }

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

    #[test]
    fn godot_script_must_reference_a_gd_file() {
        let mut s = Story::new("t", "a");
        s.add_node(Node {
            id: "a".into(), x: 0.0, y: 0.0, title: None,
            kind: NodeKind::Script {
                engine: ScriptEngine::Godot, code: None, src: None,
                entry: "run".into(), next: Some("e".into()),
            },
        });
        s.add_node(Story::mk_end("e", 0.0, 100.0, "good", "完"));
        assert!(lint(&s).iter().any(|i| i.kind == "godot-src"),
            "缺 src 必须报错，实际 {:?}", lint(&s));
        s.node_mut("a").unwrap().kind = NodeKind::Script {
            engine: ScriptEngine::Godot, code: None,
            src: Some("scripts/x.txt".into()), entry: "run".into(), next: Some("e".into()),
        };
        assert!(lint(&s).iter().any(|i| i.kind == "godot-src"), "非 .gd 必须报错");
        s.node_mut("a").unwrap().kind = NodeKind::Script {
            engine: ScriptEngine::Godot, code: None,
            src: Some("res://scripts/x.gd".into()), entry: "run".into(), next: Some("e".into()),
        };
        assert!(!lint(&s).iter().any(|i| i.kind == "godot-src"), "正确引用不该报 godot-src");
    }
}

/// 资源方块：只声明素材，不进剧情流程
pub fn is_asset_kind(kind: &NodeKind) -> bool {
    matches!(
        kind,
        NodeKind::Character { .. }
            | NodeKind::Portrait { .. }
            | NodeKind::Background { .. }
            | NodeKind::Label { .. }
            | NodeKind::Image { .. }
            | NodeKind::Value { .. }
    )
}
