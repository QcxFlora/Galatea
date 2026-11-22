//! 剧情图的数据模型 —— 整个引擎的"世界形状"。
//!
//! 一张图 = 一堆节点（台词 / 选择 / 条件 / 变量 / 跳转 / 结局…）+ 节点之间的连线。
//! 编辑器（Flutter）只改这份模型，播放器只读这份模型，导出/导入都是同一个 JSON。

use crate::json::Json;
use std::collections::{BTreeMap, HashMap};

pub const FORMAT: &str = "galatea.graph/1";

#[derive(Debug, Clone)]
pub struct Meta {
    pub title: String,
    pub author: String,
    pub desc: String,
    pub version: String,
    /// 入口节点 id
    pub start: String,
    pub cover: Option<String>,
}

impl Default for Meta {
    fn default() -> Self {
        Meta {
            title: "未命名".to_string(),
            author: String::new(),
            desc: String::new(),
            version: "0.1.0".to_string(),
            start: String::new(),
            cover: None,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct Character {
    pub name: String,
    pub color: Option<String>,
    pub avatar: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Op {
    Set,
    Add,
    Sub,
    Mul,
    Max,
    Min,
    Toggle,
}

impl Op {
    pub fn as_str(self) -> &'static str {
        match self {
            Op::Set => "set",
            Op::Add => "add",
            Op::Sub => "sub",
            Op::Mul => "mul",
            Op::Max => "max",
            Op::Min => "min",
            Op::Toggle => "toggle",
        }
    }
    pub fn from_str(s: &str) -> Op {
        match s {
            "add" | "+" => Op::Add,
            "sub" | "-" => Op::Sub,
            "mul" | "*" => Op::Mul,
            "max" => Op::Max,
            "min" => Op::Min,
            "toggle" => Op::Toggle,
            _ => Op::Set,
        }
    }
    /// 效果面板上显示的符号
    pub fn symbol(self) -> &'static str {
        match self {
            Op::Set => "=",
            Op::Add => "+=",
            Op::Sub => "-=",
            Op::Mul => "*=",
            Op::Max => "↑",
            Op::Min => "↓",
            Op::Toggle => "!",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Effect {
    pub target: String,
    pub op: Op,
    /// 右值表达式源码，例如 `aff + 1`
    pub expr: String,
}

impl Effect {
    pub fn new(target: &str, op: Op, expr: &str) -> Self {
        Effect {
            target: target.to_string(),
            op,
            expr: expr.to_string(),
        }
    }
    pub fn to_json(&self) -> Json {
        let mut o = Json::obj();
        o.set("target", Json::s(self.target.clone()));
        o.set("op", Json::s(self.op.as_str()));
        o.set("expr", Json::s(self.expr.clone()));
        o
    }
    pub fn from_json(j: &Json) -> Self {
        Effect {
            target: j.s_or("target", ""),
            op: Op::from_str(&j.s_or("op", "set")),
            expr: j.s_or("expr", "0"),
        }
    }
    pub fn display(&self) -> String {
        format!("{} {} {}", self.target, self.op.symbol(), self.expr)
    }
}

#[derive(Debug, Clone)]
pub struct Choice {
    pub text: String,
    pub to: String,
    /// 为空表示无条件可选
    pub cond: String,
    pub effects: Vec<Effect>,
    /// 只能选一次的选项（走过后隐藏）
    pub once: bool,
}

impl std::fmt::Display for Choice {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.text)
    }
}

#[derive(Debug, Clone)]
pub enum NodeKind {
    /// 一句台词（旁白则 speaker 为空）
    Say {
        speaker: Option<String>,
        text: String,
        bg: Option<String>,
        portrait: Option<String>,
        next: Option<String>,
    },
    /// 选项分支
    Choice {
        prompt: String,
        options: Vec<Choice>,
    },
    /// 条件分支：cond 为真走 yes，否则走 no
    Branch { cond: String, yes: Option<String>, no: Option<String> },
    /// 改变量，然后继续
    Set {
        effects: Vec<Effect>,
        next: Option<String>,
    },
    /// 无条件跳转（用来跨很远的地方连线，避免线绕成一团）
    Jump { to: Option<String> },
    /// 进入子图，执行完返回（组件化：把一段剧情做成可复用节点）
    /// `next` 是返回之后继续的位置。
    Call {
        to: Option<String>,
        next: Option<String>,
    },
    /// 从子图返回
    Return,
    /// 结局
    End { ending: String, text: String },
}

impl NodeKind {
    pub fn type_name(&self) -> &'static str {
        match self {
            NodeKind::Say { .. } => "say",
            NodeKind::Choice { .. } => "choice",
            NodeKind::Branch { .. } => "branch",
            NodeKind::Set { .. } => "set",
            NodeKind::Jump { .. } => "jump",
            NodeKind::Call { .. } => "call",
            NodeKind::Return => "return",
            NodeKind::End { .. } => "end",
        }
    }

    pub fn palette_color(&self) -> &'static str {
        match self {
            NodeKind::Say { .. } => "#4f7cff",
            NodeKind::Choice { .. } => "#c46bff",
            NodeKind::Branch { .. } => "#ffb02e",
            NodeKind::Set { .. } => "#22c08a",
            NodeKind::Jump { .. } => "#8892a8",
            NodeKind::Call { .. } => "#00b8d9",
            NodeKind::Return => "#8892a8",
            NodeKind::End { .. } => "#ff5c74",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Node {
    pub id: String,
    /// 画布坐标（思维导图布局）
    pub x: f64,
    pub y: f64,
    /// 作者给节点起的别名，显示在卡片标题上
    pub title: Option<String>,
    pub kind: NodeKind,
}

impl Node {
    pub fn type_name(&self) -> &'static str {
        self.kind.type_name()
    }

    /// 所有出边：(端口名, 目标节点 id)。端口名供编辑器画连线用。
    pub fn ports(&self) -> Vec<(String, String)> {
        let mut v = Vec::new();
        match &self.kind {
            NodeKind::Say { next, .. } | NodeKind::Set { next, .. } => {
                if let Some(n) = next {
                    v.push(("next".to_string(), n.clone()));
                }
            }
            NodeKind::Branch { yes, no, .. } => {
                if let Some(y) = yes {
                    v.push(("yes".to_string(), y.clone()));
                }
                if let Some(n) = no {
                    v.push(("no".to_string(), n.clone()));
                }
            }
            NodeKind::Choice { options, .. } => {
                for (i, o) in options.iter().enumerate() {
                    if !o.to.is_empty() {
                        v.push((format!("opt{}", i), o.to.clone()));
                    }
                }
            }
            NodeKind::Jump { to } => {
                if let Some(t) = to {
                    v.push(("to".to_string(), t.clone()));
                }
            }
            NodeKind::Call { to, next } => {
                if let Some(t) = to {
                    v.push(("to".to_string(), t.clone()));
                }
                if let Some(n) = next {
                    v.push(("back".to_string(), n.clone()));
                }
            }
            NodeKind::Return | NodeKind::End { .. } => {}
        }
        v
    }

    /// 编辑器拖线用：设置某个端口的出口
    pub fn set_port(&mut self, port: &str, target: Option<String>) {
        match (&mut self.kind, port) {
            (NodeKind::Say { next, .. }, "next") => *next = target,
            (NodeKind::Set { next, .. }, "next") => *next = target,
            (NodeKind::Branch { yes, .. }, "yes") => *yes = target,
            (NodeKind::Branch { no, .. }, "no") => *no = target,
            (NodeKind::Jump { to }, "to") => *to = target,
            (NodeKind::Call { to, .. }, "to") => *to = target,
            (NodeKind::Call { next, .. }, "back") => *next = target,
            (NodeKind::Choice { options, .. }, p) if p.starts_with("opt") => {
                if let Ok(i) = p[3..].parse::<usize>() {
                    if let Some(o) = options.get_mut(i) {
                        o.to = target.unwrap_or_default();
                    }
                }
            }
            _ => {}
        }
    }

    /// 某端口指向的目标
    pub fn port_target(&self, port: &str) -> Option<String> {
        self.ports()
            .into_iter()
            .find(|(p, _)| p == port)
            .map(|(_, t)| t)
    }

    /// 删节点时把指向它的线都剪掉
    pub fn drop_targets(&mut self, dead: &str) {
        let ports: Vec<String> = self
            .ports()
            .into_iter()
            .filter(|(_, t)| t == dead)
            .map(|(p, _)| p)
            .collect();
        for p in ports {
            self.set_port(&p, None);
        }
    }
}

#[derive(Debug, Clone)]
pub struct Story {
    pub format: String,
    pub meta: Meta,
    pub characters: BTreeMap<String, Character>,
    pub vars: BTreeMap<String, Json>,
    pub nodes: Vec<Node>,
    #[allow(dead_code)]
    index: HashMap<String, usize>,
}

impl Story {
    pub fn new(title: &str, start: &str) -> Self {
        Story {
            format: FORMAT.to_string(),
            meta: Meta {
                title: title.to_string(),
                start: start.to_string(),
                ..Default::default()
            },
            characters: BTreeMap::new(),
            vars: BTreeMap::new(),
            nodes: Vec::new(),
            index: HashMap::new(),
        }
    }

    pub fn node(&self, id: &str) -> Option<&Node> {
        self.index.get(id).and_then(|&i| self.nodes.get(i))
    }

    pub fn node_mut(&mut self, id: &str) -> Option<&mut Node> {
        let i = *self.index.get(id)?;
        self.nodes.get_mut(i)
    }

    pub fn add_node(&mut self, node: Node) {
        let idx = self.nodes.len();
        self.index.insert(node.id.clone(), idx);
        self.nodes.push(node);
    }

    pub fn remove_node(&mut self, id: &str) -> bool {
        let Some(pos) = self.index.get(id).copied() else {
            return false;
        };
        self.nodes.remove(pos);
        self.reindex();
        for n in self.nodes.iter_mut() {
            n.drop_targets(id);
        }
        if self.meta.start == id {
            self.meta.start.clear();
        }
        true
    }

    pub fn reindex(&mut self) {
        self.index = self
            .nodes
            .iter()
            .enumerate()
            .map(|(i, n)| (n.id.clone(), i))
            .collect();
    }

    /// 生成一个没被占用的 id，形如 `say_7`
    pub fn fresh_id(&self, prefix: &str) -> String {
        for i in 1.. {
            let id = format!("{}_{}", prefix, i);
            if self.node(&id).is_none() {
                return id;
            }
        }
        unreachable!()
    }

    // ------------------------------------------------------------ JSON

    pub fn effect_list_to_json(effects: &[Effect]) -> Json {
        Json::Arr(effects.iter().map(|e| e.to_json()).collect())
    }

    pub fn effects_from_json(j: &Json) -> Vec<Effect> {
        j.as_arr()
            .map(|a| a.iter().map(Effect::from_json).collect())
            .unwrap_or_default()
    }

    pub fn node_to_json(&self, n: &Node) -> Json {
        let mut o = Json::obj();
        o.set("id", Json::s(n.id.clone()));
        o.set("type", Json::s(n.type_name()));
        o.set("x", Json::n(n.x));
        o.set("y", Json::n(n.y));
        if let Some(t) = &n.title {
            if !t.is_empty() {
                o.set("title", Json::s(t.clone()));
            }
        }
        let opt = |v: &Option<String>, key: &str, o: &mut Json| {
            if let Some(s) = v {
                if !s.is_empty() {
                    o.set(key, Json::s(s.clone()));
                }
            }
        };
        match &n.kind {
            NodeKind::Say {
                speaker,
                text,
                bg,
                portrait,
                next,
            } => {
                opt(speaker, "speaker", &mut o);
                o.set("text", Json::s(text.clone()));
                opt(bg, "bg", &mut o);
                opt(portrait, "portrait", &mut o);
                opt(next, "next", &mut o);
            }
            NodeKind::Choice { prompt, options } => {
                o.set("prompt", Json::s(prompt.clone()));
                let mut arr = Json::arr();
                for c in options {
                    let mut co = Json::obj();
                    co.set("text", Json::s(c.text.clone()));
                    co.set("to", Json::s(c.to.clone()));
                    if !c.cond.trim().is_empty() {
                        co.set("cond", Json::s(c.cond.clone()));
                    }
                    if c.once {
                        co.set("once", Json::b(true));
                    }
                    if !c.effects.is_empty() {
                        co.set("effects", Story::effect_list_to_json(&c.effects));
                    }
                    arr.push(co);
                }
                o.set("options", arr);
            }
            NodeKind::Branch { cond, yes, no } => {
                o.set("cond", Json::s(cond.clone()));
                opt(yes, "yes", &mut o);
                opt(no, "no", &mut o);
            }
            NodeKind::Set { effects, next } => {
                o.set("effects", Story::effect_list_to_json(effects));
                opt(next, "next", &mut o);
            }
            NodeKind::Jump { to } => opt(to, "to", &mut o),
            NodeKind::Call { to, next } => {
                opt(to, "to", &mut o);
                opt(next, "next", &mut o);
            }
            NodeKind::Return => {}
            NodeKind::End { ending, text } => {
                o.set("ending", Json::s(ending.clone()));
                if !text.is_empty() {
                    o.set("text", Json::s(text.clone()));
                }
            }
        }
        o
    }

    pub fn to_json(&self) -> Json {
        let mut root = Json::obj();
        root.set("format", Json::s(self.format.clone()));

        let mut meta = Json::obj();
        meta.set("title", Json::s(self.meta.title.clone()));
        meta.set("author", Json::s(self.meta.author.clone()));
        meta.set("desc", Json::s(self.meta.desc.clone()));
        meta.set("version", Json::s(self.meta.version.clone()));
        meta.set("start", Json::s(self.meta.start.clone()));
        if let Some(c) = &self.meta.cover {
            meta.set("cover", Json::s(c.clone()));
        }
        root.set("meta", meta);

        let mut chars = Json::obj();
        for (k, c) in &self.characters {
            let mut co = Json::obj();
            co.set("name", Json::s(c.name.clone()));
            if let Some(v) = &c.color {
                co.set("color", Json::s(v.clone()));
            }
            if let Some(v) = &c.avatar {
                co.set("avatar", Json::s(v.clone()));
            }
            chars.set(k, co);
        }
        root.set("characters", chars);

        let mut vars = Json::obj();
        for (k, v) in &self.vars {
            vars.set(k, v.clone());
        }
        root.set("vars", vars);

        let mut nodes = Json::arr();
        for n in &self.nodes {
            nodes.push(self.node_to_json(n));
        }
        root.set("nodes", nodes);
        root
    }

    pub fn from_json(j: &Json) -> Result<Story, String> {
        if j.get("nodes").and_then(|v| v.as_arr()).is_none() {
            return Err("缺少 nodes 数组，不像是 Galatea 剧本".to_string());
        }
        let mut s = Story::new("未命名", "");
        s.format = j.s_or("format", FORMAT);
        if let Some(m) = j.get("meta") {
            s.meta.title = m.s_or("title", "未命名");
            s.meta.author = m.s_or("author", "");
            s.meta.desc = m.s_or("desc", "");
            s.meta.version = m.s_or("version", "0.1.0");
            s.meta.start = m.s_or("start", "");
            s.meta.cover = m.opt_str("cover");
        }
        if let Some(chars) = j.get("characters").and_then(|v| v.as_obj()) {
            for (k, v) in chars {
                s.characters.insert(
                    k.clone(),
                    Character {
                        name: v.s_or("name", k),
                        color: v.opt_str("color"),
                        avatar: v.opt_str("avatar"),
                    },
                );
            }
        }
        if let Some(vars) = j.get("vars").and_then(|v| v.as_obj()) {
            for (k, v) in vars {
                s.vars.insert(k.clone(), v.clone());
            }
        }
        for nj in j.arr_or_empty("nodes") {
            let id = nj.s_or("id", "");
            if id.is_empty() {
                return Err("有节点缺少 id".to_string());
            }
            if s.node(&id).is_some() {
                return Err(format!("节点 id 重复：{}", id));
            }
            let kind = match nj.s_or("type", "say").as_str() {
                "choice" => {
                    let mut options = Vec::new();
                    for oj in nj.arr_or_empty("options") {
                        options.push(Choice {
                            text: oj.s_or("text", ""),
                            to: oj.s_or("to", ""),
                            cond: oj.s_or("cond", ""),
                            effects: Story::effects_from_json(&oj.get("effects").cloned().unwrap_or(Json::Null)),
                            once: oj.bool_or("once", false),
                        });
                    }
                    NodeKind::Choice {
                        prompt: nj.s_or("prompt", ""),
                        options,
                    }
                }
                "branch" => NodeKind::Branch {
                    cond: nj.s_or("cond", ""),
                    yes: nj.opt_str("yes").filter(|s| !s.is_empty()),
                    no: nj.opt_str("no").filter(|s| !s.is_empty()),
                },
                "set" => NodeKind::Set {
                    effects: Story::effects_from_json(&nj.get("effects").cloned().unwrap_or(Json::Null)),
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
                "jump" => NodeKind::Jump {
                    to: nj.opt_str("to").filter(|s| !s.is_empty()),
                },
                "call" => NodeKind::Call {
                    to: nj.opt_str("to").filter(|s| !s.is_empty()),
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
                "return" => NodeKind::Return,
                "end" => NodeKind::End {
                    ending: nj.s_or("ending", "end"),
                    text: nj.s_or("text", ""),
                },
                _ => NodeKind::Say {
                    speaker: nj.opt_str("speaker").filter(|s| !s.is_empty()),
                    text: nj.s_or("text", ""),
                    bg: nj.opt_str("bg").filter(|s| !s.is_empty()),
                    portrait: nj.opt_str("portrait").filter(|s| !s.is_empty()),
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
            };
            let node = Node {
                id,
                x: nj.num_or("x", 0.0),
                y: nj.num_or("y", 0.0),
                title: nj.opt_str("title").filter(|s| !s.is_empty()),
                kind,
            };
            s.add_node(node);
        }
        Ok(s)
    }

    pub fn to_json_string_pretty(&self) -> String {
        self.to_json().to_pretty()
    }

    pub fn from_json_str(src: &str) -> Result<Story, String> {
        let j = crate::json::parse(src)?;
        Story::from_json(&j)
    }
}

/// 新建各种节点的便捷构造器（编辑器 & 测试都用）
impl Story {
    pub fn mk_say(id: &str, x: f64, y: f64, speaker: Option<&str>, text: &str) -> Node {
        Node {
            id: id.to_string(),
            x,
            y,
            title: None,
            kind: NodeKind::Say {
                speaker: speaker.map(|s| s.to_string()),
                text: text.to_string(),
                bg: None,
                portrait: None,
                next: None,
            },
        }
    }
    pub fn mk_choice(id: &str, x: f64, y: f64, prompt: &str, opts: &[(&str, &str)]) -> Node {
        Node {
            id: id.to_string(),
            x,
            y,
            title: None,
            kind: NodeKind::Choice {
                prompt: prompt.to_string(),
                options: opts
                    .iter()
                    .map(|(t, to)| Choice {
                        text: t.to_string(),
                        to: to.to_string(),
                        cond: String::new(),
                        effects: Vec::new(),
                        once: false,
                    })
                    .collect(),
            },
        }
    }
    pub fn mk_end(id: &str, x: f64, y: f64, ending: &str, text: &str) -> Node {
        Node {
            id: id.to_string(),
            x,
            y,
            title: None,
            kind: NodeKind::End {
                ending: ending.to_string(),
                text: text.to_string(),
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Story {
        let mut s = Story::new("测试", "n1");
        s.vars.insert("aff".to_string(), Json::Num(0.0));
        s.add_node(Story::mk_say("n1", 0.0, 0.0, Some("雪"), "你好"));
        let mut n = Story::mk_choice("n2", 0.0, 100.0, "要回答吗？", &[("要", "n3"), ("不要", "n4")]);
        if let NodeKind::Choice { options, .. } = &mut n.kind {
            options[0].effects.push(Effect::new("aff", Op::Add, "1"));
        }
        s.add_node(n);
        s.add_node(Story::mk_say("n3", -100.0, 200.0, Some("我"), "嗯"));
        s.add_node(Story::mk_say("n4", 100.0, 200.0, None, "我沉默着"));
        s.add_node(Story::mk_end("e1", 0.0, 300.0, "good", "结束了"));
        // 连线
        s.node_mut("n1").unwrap().set_port("next", Some("n2".into()));
        s.node_mut("n2").unwrap().set_port("opt0", Some("n3".into()));
        s.node_mut("n2").unwrap().set_port("opt1", Some("n4".into()));
        s.node_mut("n3").unwrap().set_port("next", Some("e1".into()));
        s.node_mut("n4").unwrap().set_port("next", Some("e1".into()));
        s
    }

    #[test]
    fn json_roundtrip() {
        let s = sample();
        let text = s.to_json_string_pretty();
        let s2 = Story::from_json_str(&text).unwrap();
        assert_eq!(s.nodes.len(), s2.nodes.len());
        assert_eq!(s.meta.start, s2.meta.start);
        assert_eq!(s.to_json(), s2.to_json());
    }

    #[test]
    fn ports_and_prune() {
        let mut s = sample();
        assert_eq!(s.node("n2").unwrap().ports().len(), 2);
        s.remove_node("n3");
        assert_eq!(s.node("n2").unwrap().port_target("opt0"), None);
        assert_eq!(s.node("n2").unwrap().port_target("opt1"), Some("n4".into()));
    }

    #[test]
    fn fresh_id() {
        let s = sample();
        assert_eq!(s.fresh_id("say"), "say_1");
    }

    #[test]
    fn duplicate_id_rejected() {
        let mut s = sample();
        s.add_node(Story::mk_say("n1", 0.0, 0.0, None, "重复"));
        let txt = s.to_json_string_pretty();
        assert!(Story::from_json_str(&txt).is_err());
    }
}