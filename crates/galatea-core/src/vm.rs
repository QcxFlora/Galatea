//! 剧情解释器。
//!
//! 它是纯逻辑的：只负责"下一个该发生什么"，不碰任何 UI。
//! 编辑器内嵌的试玩、独立播放器、以及导出的可执行游戏，跑的都是同一个 VM。

use crate::expr;
use crate::graph::{Effect, NodeKind, Op, Story};
use crate::json::Json;
use crate::script::{Script, Value as ScriptValue};
use std::collections::{BTreeMap, BTreeSet};
use std::rc::Rc;

/// 给 UI 展示的一个选项（已经过条件/一次性过滤）
#[derive(Debug, Clone, PartialEq)]
pub struct OptionView {
    /// 在原始 options 数组里的下标
    pub index: usize,
    pub text: String,
    pub target: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Say {
        node: String,
        /// 角色 key（旁白为 None）
        speaker: Option<String>,
        /// 显示名
        speaker_name: String,
        color: Option<String>,
        text: String,
        bg: Option<String>,
        portrait: Option<String>,
    },
    Choices {
        node: String,
        prompt: String,
        options: Vec<OptionView>,
    },
    Ending {
        node: String,
        ending: String,
        text: String,
    },
    /// 跑不下去了（剧情结束 / 断线 / 死循环）
    Halt {
        reason: String,
    },
    /// 执行了一个自定义 Rust 脚本节点
    Script {
        node: String,
        entry: String,
        /// 脚本返回值
        ret: Json,
        /// 脚本里 emit 出来的演出指令
        emits: BTreeMap<String, Json>,
    },
}

impl Event {
    pub fn is_halt(&self) -> bool {
        matches!(self, Event::Halt { .. })
    }
}

#[derive(Debug, Clone)]
struct Pending {
    node: String,
    prompt: String,
    options: Vec<OptionView>,
    /// 原始选项，用于取 effects
    originals: Vec<crate::graph::Choice>,
}

#[derive(Debug, Clone)]
struct Snapshot {
    pc: Option<String>,
    vars: BTreeMap<String, Json>,
    stack: Vec<Option<String>>,
    visited: BTreeMap<String, u32>,
    taken: BTreeSet<String>,
    log_len: usize,
}

const MAX_SNAPSHOTS: usize = 256;
const MAX_AUTO_STEPS: u32 = 4096;
const MAX_CALL_DEPTH: usize = 64;

#[derive(Debug, Clone)]
pub struct Vm {
    story: Story,
    pub pc: Option<String>,
    pub vars: BTreeMap<String, Json>,
    stack: Vec<Option<String>>,
    pub visited: BTreeMap<String, u32>,
    taken: BTreeSet<String>,
    pub log: Vec<String>,
    pending: Option<Pending>,
    pub ended: Option<(String, String)>,
    snapshots: Vec<Snapshot>,
    /// 本次运行中自动执行的节点数（用于诊断）
    pub auto_steps: u32,
    /// 已编译的自定义脚本缓存
    scripts: BTreeMap<String, Rc<Script>>,
    /// 脚本相对路径的基准目录（默认为当前工作目录）
    pub script_base: std::path::PathBuf,
}

impl Vm {
    pub fn new(story: Story) -> Self {
        let vars = story.vars.clone();
        let pc = if story.meta.start.is_empty() {
            None
        } else {
            Some(story.meta.start.clone())
        };
        Vm {
            story,
            pc,
            vars,
            stack: Vec::new(),
            visited: BTreeMap::new(),
            taken: BTreeSet::new(),
            log: Vec::new(),
            pending: None,
            ended: None,
            snapshots: Vec::new(),
            auto_steps: 0,
            scripts: BTreeMap::new(),
            script_base: std::env::current_dir()
                .unwrap_or_else(|_| std::path::PathBuf::from(".")),
        }
    }

    /// 从剧本的第一个节点开始
    pub fn restart(&mut self) {
        self.pc = if self.story.meta.start.is_empty() {
            None
        } else {
            Some(self.story.meta.start.clone())
        };
        self.vars = self.story.vars.clone();
        self.stack.clear();
        self.visited.clear();
        self.taken.clear();
        self.log.clear();
        self.pending = None;
        self.ended = None;
        self.snapshots.clear();
    }

    pub fn story(&self) -> &Story {
        &self.story
    }

    // ---------------------------------------------------------- 变量

    /// 读变量，支持 `flags.seen` 这种点号路径
    pub fn var(&self, path: &str) -> Json {
        let mut parts = path.split('.').filter(|s| !s.is_empty());
        let Some(head) = parts.next() else {
            return Json::Null;
        };
        let mut cur = self.vars.get(head).cloned().unwrap_or(Json::Null);
        for p in parts {
            cur = cur.get(p).cloned().unwrap_or(Json::Null);
        }
        cur
    }

    pub fn set_var(&mut self, path: &str, v: Json) {
        let parts: Vec<&str> = path.split('.').filter(|s| !s.is_empty()).collect();
        if parts.is_empty() {
            return;
        }
        if parts.len() == 1 {
            self.vars.insert(parts[0].to_string(), v);
            return;
        }
        let entry = self
            .vars
            .entry(parts[0].to_string())
            .or_insert_with(Json::obj);
        set_path(entry, &parts[1..], v);
    }

    pub fn eval_expr(&self, src: &str) -> Result<Json, String> {
        let e = expr::parse(src)?;
        Ok(e.eval(&|name| self.var(name)))
    }

    pub fn eval_cond(&self, src: &str) -> bool {
        if src.trim().is_empty() {
            return true;
        }
        match self.eval_expr(src) {
            Ok(v) => v.truthy(),
            Err(_) => false,
        }
    }

    fn apply(&mut self, effects: &[Effect]) {
        for e in effects {
            let rhs = self.eval_expr(&e.expr).unwrap_or(Json::Num(0.0));
            let cur = self.var(&e.target);
            let newv = match e.op {
                Op::Set => rhs,
                Op::Add => match (&cur, &rhs) {
                    (Json::Str(s), _) => Json::Str(format!("{}{}", s, rhs.as_display())),
                    _ => Json::Num(expr::to_num(&cur) + expr::to_num(&rhs)),
                },
                Op::Sub => Json::Num(expr::to_num(&cur) - expr::to_num(&rhs)),
                Op::Mul => Json::Num(expr::to_num(&cur) * expr::to_num(&rhs)),
                Op::Max => Json::Num(expr::to_num(&cur).max(expr::to_num(&rhs))),
                Op::Min => Json::Num(expr::to_num(&cur).min(expr::to_num(&rhs))),
                Op::Toggle => Json::Bool(!cur.truthy()),
            };
            self.set_var(&e.target, newv);
        }
    }

    // ---------------------------------------------------------- 驱动

    fn push_snapshot(&mut self) {
        if self.snapshots.len() >= MAX_SNAPSHOTS {
            self.snapshots.remove(0);
        }
        self.snapshots.push(Snapshot {
            pc: self.pc.clone(),
            vars: self.vars.clone(),
            stack: self.stack.clone(),
            visited: self.visited.clone(),
            taken: self.taken.clone(),
            log_len: self.log.len(),
        });
    }

    pub fn can_undo(&self) -> bool {
        !self.snapshots.is_empty()
    }

    /// 退回上一个"停顿点"（一句台词 / 一个选择）。
    /// 语义：丢掉当前停顿点的状态，回到上一个停顿点的入口重新播放。
    pub fn undo(&mut self) -> bool {
        if self.snapshots.len() < 2 {
            return false;
        }
        self.snapshots.pop(); // 当前停顿点
        match self.snapshots.pop() {
            Some(s) => {
                self.pc = s.pc;
                self.vars = s.vars;
                self.stack = s.stack;
                self.visited = s.visited;
                self.taken = s.taken;
                self.log.truncate(s.log_len);
                self.pending = None;
                self.ended = None;
                true
            }
            None => false,
        }
    }

    /// 推进到下一个需要玩家看到的事件
    pub fn step(&mut self) -> Event {
        if let Some(p) = &self.pending {
            return Event::Choices {
                node: p.node.clone(),
                prompt: p.prompt.clone(),
                options: p.options.clone(),
            };
        }
        self.auto_steps = 0;
        loop {
            self.auto_steps += 1;
            if self.auto_steps > MAX_AUTO_STEPS {
                return Event::Halt {
                    reason: format!(
                        "连续执行了 {} 个节点都没停下来，可能是死循环（检查 jump / next 有没有绕圈）",
                        MAX_AUTO_STEPS
                    ),
                };
            }
            let Some(pc) = self.pc.clone() else {
                return Event::Halt {
                    reason: "剧情结束".to_string(),
                };
            };
            let Some(node) = self.story.node(&pc).cloned() else {
                return Event::Halt {
                    reason: format!("找不到节点 `{}`（连线指向了不存在的东西）", pc),
                };
            };
            *self.visited.entry(pc.clone()).or_insert(0) += 1;

            match node.kind {
                NodeKind::Say {
                    speaker,
                    text,
                    bg,
                    portrait,
                    next,
                    ..
                } => {
                    self.push_snapshot();
                    let (name, color, portrait) = self.speaker_info(&speaker, portrait);
                    self.log.push(if name.is_empty() {
                        text.clone()
                    } else {
                        format!("{}：{}", name, text)
                    });
                    self.pc = next;
                    return Event::Say {
                        node: pc,
                        speaker,
                        speaker_name: name,
                        color,
                        text,
                        bg,
                        portrait,
                    };
                }
                NodeKind::Choice { prompt, options } => {
                    let mut views = Vec::new();
                    for (i, o) in options.iter().enumerate() {
                        if !o.cond.trim().is_empty() && !self.eval_cond(&o.cond) {
                            continue;
                        }
                        if o.once && self.taken.contains(&format!("{}#{}", pc, i)) {
                            continue;
                        }
                        if o.to.is_empty() {
                            continue;
                        }
                        views.push(OptionView {
                            index: i,
                            text: o.text.clone(),
                            target: o.to.clone(),
                        });
                    }
                    if views.is_empty() {
                        self.pc = None;
                        return Event::Halt {
                            reason: format!("选项节点 `{}` 没有任何可选项（条件全部不满足？）", pc),
                        };
                    }
                    self.push_snapshot();
                    self.pending = Some(Pending {
                        node: pc.clone(),
                        prompt: prompt.clone(),
                        options: views.clone(),
                        originals: options,
                    });
                    return Event::Choices {
                        node: pc,
                        prompt,
                        options: views,
                    };
                }
                NodeKind::Branch { cond, yes, no } => {
                    self.pc = if self.eval_cond(&cond) { yes } else { no };
                    if self.pc.is_none() {
                        return Event::Halt {
                            reason: format!("条件节点 `{}` 有一条分支没连线", pc),
                        };
                    }
                }
                NodeKind::Set { effects, next } => {
                    self.apply(&effects);
                    self.pc = next;
                }
                // 资源声明方块（角色/立绘/背景）：不进演出流程，直接跳过
                NodeKind::Character { next, .. }
                | NodeKind::Portrait { next, .. }
                | NodeKind::Background { next, .. } => {
                    self.pc = next;
                }
                NodeKind::Jump { to } => {
                    self.pc = to;
                }
                NodeKind::Call { to, next } => {
                    if self.stack.len() >= MAX_CALL_DEPTH {
                        return Event::Halt {
                            reason: format!("子图调用嵌套超过 {} 层（是不是递归了？）", MAX_CALL_DEPTH),
                        };
                    }
                    self.stack.push(next);
                    self.pc = to;
                }
                NodeKind::Return => {
                    self.pc = self.stack.pop().flatten();
                }
                NodeKind::Script {
                    code,
                    src,
                    entry,
                    next,
                } => {
                    let key = match (&src, &code) {
                        (Some(s), _) => format!("file:{}", s),
                        (None, Some(c)) => {
                            let head: String = c.chars().take(48).collect();
                            format!("inline:{}:{}", c.len(), head)
                        }
                        (None, None) => {
                            return Event::Halt {
                                reason: format!("脚本节点 `{}` 既没有 src 也没有 code", pc),
                            }
                        }
                    };
                    if !self.scripts.contains_key(&key) {
                        let compiled = match (&src, &code) {
                            (Some(path), _) => {
                                Script::from_file(&self.script_base.join(path))
                            }
                            (None, Some(c)) => Script::compile("<inline>", c),
                            (None, None) => unreachable!(),
                        };
                        match compiled {
                            Ok(s) => {
                                self.scripts.insert(key.clone(), Rc::new(s));
                            }
                            Err(e) => {
                                return Event::Halt {
                                    reason: format!("节点 `{}` 的脚本编译失败：{}", pc, e),
                                }
                            }
                        }
                    }
                    let script = self.scripts.get(&key).cloned().unwrap();
                    let res = {
                        let getter = |n: &str| ScriptValue::from_json(&self.var(n));
                        script.call(&entry, Vec::new(), &getter)
                    };
                    match res {
                        Ok(r) => {
                            for (k, v) in &r.vars {
                                self.set_var(k, v.to_json());
                            }
                            let emits: BTreeMap<String, Json> =
                                r.emits.iter().map(|(k, v)| (k.clone(), v.to_json())).collect();
                            let ret = r.ret.clone().map(|v| v.to_json()).unwrap_or(Json::Null);
                            self.pc = next;
                            return Event::Script {
                                node: pc,
                                entry,
                                ret,
                                emits,
                            };
                        }
                        Err(e) => {
                            return Event::Halt {
                                reason: format!("脚本 `{}` 执行失败：{}", entry, e),
                            }
                        }
                    }
                }
                NodeKind::End { ending, text } => {
                    self.pc = None;
                    self.ended = Some((ending.clone(), text.clone()));
                    return Event::Ending {
                        node: pc,
                        ending,
                        text,
                    };
                }
            }
        }
    }

    fn speaker_info(
        &self,
        key: &Option<String>,
        portrait: Option<String>,
    ) -> (String, Option<String>, Option<String>) {
        match key {
            None => (String::new(), None, None),
            Some(k) => match self.story.characters.get(k) {
                Some(c) => (
                    c.name.clone(),
                    c.color.clone(),
                    portrait.or_else(|| c.avatar.clone()),
                ),
                None => (k.clone(), None, portrait),
            },
        }
    }

    /// 玩家点了第 `visible_index` 个选项，返回下一个事件
    pub fn choose(&mut self, visible_index: usize) -> Result<Event, String> {
        let Some(p) = self.pending.take() else {
            return Err("现在没有等待选择".to_string());
        };
        let Some(view) = p.options.get(visible_index).cloned() else {
            return Err(format!("选项下标 {} 越界", visible_index));
        };
        if let Some(orig) = p.originals.get(view.index) {
            let effs = orig.effects.clone();
            self.apply(&effs);
        }
        self.taken.insert(format!("{}#{}", p.node, view.index));
        self.pc = if view.target.is_empty() {
            None
        } else {
            Some(view.target)
        };
        Ok(self.step())
    }

    // ---------------------------------------------------------- 存档

    pub fn save_json(&self) -> Json {
        let mut o = Json::obj();
        o.set(
            "pc",
            match &self.pc {
                Some(p) => Json::s(p.clone()),
                None => Json::Null,
            },
        );
        let mut vars = Json::obj();
        for (k, v) in &self.vars {
            vars.set(k, v.clone());
        }
        o.set("vars", vars);
        let stack = Json::Arr(self.stack.iter().map(|s| match s {
            Some(x) => Json::s(x.clone()),
            None => Json::Null,
        }).collect());
        o.set("stack", stack);
        let mut visited = Json::obj();
        for (k, v) in &self.visited {
            visited.set(k, Json::n(*v as f64));
        }
        o.set("visited", visited);
        o.set(
            "taken",
            Json::Arr(self.taken.iter().map(|s| Json::s(s.clone())).collect()),
        );
        o.set(
            "log",
            Json::Arr(self.log.iter().map(|s| Json::s(s.clone())).collect()),
        );
        if let Some((e, t)) = &self.ended {
            let mut end = Json::obj();
            end.set("ending", Json::s(e.clone()));
            end.set("text", Json::s(t.clone()));
            o.set("ended", end);
        }
        o
    }

    pub fn save(&self) -> String {
        self.save_json().to_pretty()
    }

    pub fn load(&mut self, j: &Json) -> Result<(), String> {
        self.pc = j.opt_str("pc");
        self.vars.clear();
        if let Some(m) = j.get("vars").and_then(|v| v.as_obj()) {
            for (k, v) in m {
                self.vars.insert(k.clone(), v.clone());
            }
        }
        self.stack = j
            .arr_or_empty("stack")
            .iter()
            .map(|v| v.as_str().map(|s| s.to_string()))
            .collect();
        self.visited.clear();
        if let Some(m) = j.get("visited").and_then(|v| v.as_obj()) {
            for (k, v) in m {
                self.visited.insert(k.clone(), v.as_f64().unwrap_or(0.0) as u32);
            }
        }
        self.taken = j
            .arr_or_empty("taken")
            .iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect();
        self.log = j
            .arr_or_empty("log")
            .iter()
            .filter_map(|v| v.as_str().map(|s| s.to_string()))
            .collect();
        self.ended = j
            .get("ended")
            .map(|e| (e.s_or("ending", ""), e.s_or("text", "")));
        self.pending = None;
        self.snapshots.clear();
        Ok(())
    }

    /// 已读节点数 / 总节点数，给"剧本完成度"用
    pub fn progress(&self) -> (usize, usize) {
        (self.visited.len(), self.story.nodes.len())
    }
}

fn set_path(obj: &mut Json, parts: &[&str], v: Json) {
    if parts.len() == 1 {
        if !matches!(obj, Json::Obj(_)) {
            *obj = Json::obj();
        }
        obj.set(parts[0], v);
        return;
    }
    if !matches!(obj, Json::Obj(_)) {
        *obj = Json::obj();
    }
    if obj.get(parts[0]).is_none() {
        obj.set(parts[0], Json::obj());
    }
    if let Json::Obj(m) = obj {
        if let Some(child) = m.get_mut(parts[0]) {
            set_path(child, &parts[1..], v);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graph::{Choice, Node, Story};

    fn build() -> Story {
        let mut s = Story::new("demo", "s1");
        s.characters.insert(
            "yuki".into(),
            crate::graph::Character {
                name: "雪".into(),
                color: Some("#7aa2f7".into()),
                avatar: None,
            },
        );
        s.vars.insert("aff".into(), Json::Num(0.0));
        s.add_node(Story::mk_say("s1", 0.0, 0.0, Some("yuki"), "早上好。"));
        s.add_node(Node {
            id: "c1".into(),
            x: 0.0,
            y: 100.0,
            title: None,
            kind: NodeKind::Choice {
                prompt: "怎么回答？".into(),
                options: vec![
                    Choice {
                        text: "早上好".into(),
                        to: "s2".into(),
                        cond: "".into(),
                        effects: vec![Effect::new("aff", Op::Add, "1")],
                        once: false,
                    },
                    Choice {
                        text: "……".into(),
                        to: "s3".into(),
                        cond: "".into(),
                        effects: vec![],
                        once: true,
                    },
                ],
            },
        });
        s.add_node(Story::mk_say("s2", -100.0, 200.0, Some("yuki"), "今天也很早呢。"));
        s.add_node(Story::mk_say("s3", 100.0, 200.0, None, "沉默。"));
        s.add_node(Story::mk_end("e1", 0.0, 300.0, "good", "完"));
        s.node_mut("s1").unwrap().set_port("next", Some("c1".into()));
        s.node_mut("c1").unwrap().set_port("opt0", Some("s2".into()));
        s.node_mut("c1").unwrap().set_port("opt1", Some("s3".into()));
        s.node_mut("s2").unwrap().set_port("next", Some("e1".into()));
        s.node_mut("s3").unwrap().set_port("next", Some("e1".into()));
        s
    }

    #[test]
    fn happy_path() {
        let mut vm = Vm::new(build());
        match vm.step() {
            Event::Say { text, speaker_name, .. } => {
                assert_eq!(text, "早上好。");
                assert_eq!(speaker_name, "雪");
            }
            other => panic!("期望台词，实际 {:?}", other),
        }
        match vm.step() {
            Event::Choices { options, .. } => assert_eq!(options.len(), 2),
            other => panic!("期望选项，实际 {:?}", other),
        }
        match vm.choose(0).unwrap() {
            Event::Say { text, .. } => assert_eq!(text, "今天也很早呢。"),
            other => panic!("期望台词，实际 {:?}", other),
        }
        assert_eq!(vm.var("aff"), Json::Num(1.0));
        assert!(matches!(vm.step(), Event::Ending { .. }));
        assert!(vm.step().is_halt());
    }

    #[test]
    fn undo_restores_vars() {
        let mut vm = Vm::new(build());
        vm.step();
        vm.step();
        vm.choose(0).unwrap();
        assert_eq!(vm.var("aff"), Json::Num(1.0));
        assert!(vm.undo());
        assert_eq!(vm.var("aff"), Json::Num(0.0));
    }

    #[test]
    fn save_load() {
        let mut vm = Vm::new(build());
        vm.step();
        vm.step();
        vm.choose(0).unwrap();
        let snap = vm.save();
        let mut vm2 = Vm::new(build());
        let j = crate::json::parse(&snap).unwrap();
        vm2.load(&j).unwrap();
        assert_eq!(vm2.var("aff"), Json::Num(1.0));
        assert!(matches!(vm2.step(), Event::Ending { .. }));
    }

    #[test]
    fn branch_and_effects() {
        let mut s = Story::new("t", "a");
        s.vars.insert("aff".into(), Json::Num(5.0));
        s.add_node(Node {
            id: "a".into(),
            x: 0.0,
            y: 0.0,
            title: None,
            kind: NodeKind::Branch {
                cond: "aff >= 5 && 真".into(),
                yes: Some("y".into()),
                no: Some("n".into()),
            },
        });
        s.add_node(Story::mk_say("y", 0.0, 50.0, None, "yes"));
        s.add_node(Story::mk_say("n", 0.0, 50.0, None, "no"));
        let mut vm = Vm::new(s);
        match vm.step() {
            Event::Say { text, .. } => assert_eq!(text, "yes"),
            other => panic!("{:?}", other),
        }
    }
}