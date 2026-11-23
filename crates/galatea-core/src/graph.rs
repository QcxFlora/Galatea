//! 剧情图的数据模型 —— 整个引擎的"世界形状"。
//!
//! 一张图 = 一堆节点（台词 / 选择 / 条件 / 变量 / 跳转 / 结局…）+ 节点之间的连线。
//! 编辑器（Flutter）只改这份模型，播放器只读这份模型，导出/导入都是同一个 JSON。

use crate::json::Json;
use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};

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

/// 脚本块用哪个引擎跑
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScriptEngine {
    /// 引擎内置的 Rust 安全子集解释器：零依赖、可测试、任何运行时都能跑
    Rust,
    /// Godot 的 GDScript：完整能力（3D、物理、动画），只有 Godot 运行时能跑
    Godot,
}

impl ScriptEngine {
    pub fn as_str(self) -> &'static str {
        match self {
            ScriptEngine::Rust => "rust",
            ScriptEngine::Godot => "godot",
        }
    }
    pub fn from_str(s: &str) -> ScriptEngine {
        match s {
            "godot" | "gdscript" | "gd" => ScriptEngine::Godot,
            _ => ScriptEngine::Rust,
        }
    }
}

/// 加权分支的一条路
#[derive(Debug, Clone)]
pub struct WeightedBranch {
    pub to: String,
    /// 权重表达式（可动态，例如 `好感 * 2`；<=0 视为不可达）
    pub weight: String,
    /// 可选条件，不满足就直接排除
    pub cond: String,
}

impl WeightedBranch {
    pub fn new(to: &str, weight: &str) -> Self {
        WeightedBranch {
            to: to.to_string(),
            weight: weight.to_string(),
            cond: String::new(),
        }
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
    /// 台词。**不含任何说话人/立绘字段**——全部靠连线：
    /// `cast` 说这句话的人（可多个，多人同声）、`art` 这一格的立绘（可多个，多人同框）、
    /// `bg` 背景。没有任何 cast 连线 = 旁白。
    Say {
        text: String,
        next: Option<String>,
        cast: Vec<String>,
        art: Vec<String>,
        bg: Vec<String>,
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
    /// 值块：一个数值/表达式。两种用法：
    ///   · 连到「变量块」的 add 端口 → 给变量加这个值
    ///   · 连到「加权分支」的某个端口 → 这条路的权重
    Value {
        expr: String,
    },
    /// 变量块：一句「给这个变量加值」。`add` 端口连值块（可多个，累加）。
    Variable {
        name: String,
        add: Vec<String>,
        next: Option<String>,
    },
    /// 加权分支：按权重随机走一条
    Weighted {
        prompt: String,
        branches: Vec<WeightedBranch>,
    },
    /// 结局
    End { ending: String, text: String },
    /// 显示块：一个「名字」。
    /// `tag` 是剧本内部引用的标识（amiya），`text` 是显示的文字（阿米娅）。
    /// 它连到台词 = 说话人；连到立绘 = 角色名；连到背景 = 场景名——
    /// **同一个块可以充当任何一种名字，看它连到谁**。
    Label {
        tag: Option<String>,
        text: String,
        next: Option<String>,
    },
    /// 角色卡：这台机器上的「演员表」
    Character {
        key: String,
        name: String,
        color: Option<String>,
        portraits: Vec<String>,
        next: Option<String>,
    },
    /// 立绘资源
    Portrait {
        character: Option<String>,
        asset: String,
        expr: Option<String>,
        next: Option<String>,
    },
    /// 背景资源
    Background {
        asset: String,
        scene: Option<String>,
        next: Option<String>,
    },
    /// 自定义脚本：跑一段自己的逻辑（动画曲线 / 首界面 / 小游戏）
    /// `engine` 决定由谁来执行：Rust 沙箱解释器，还是 Godot 的 GDScript。
    /// `code` 是内联源码，`src` 是路径（二选一）
    Script {
        engine: ScriptEngine,
        code: Option<String>,
        src: Option<String>,
        entry: String,
        next: Option<String>,
    },
    /// 图块：统一的图片资源声明，承担背景/立绘等一切图片职责。
    /// say 的 art/bg 端口连到它，VM 取 path。一个图块可被多处引用，打包只存一份。
    Image {
        key: String,
        path: String,
        label: Option<String>,
        next: Option<String>,
    },
    /// 音频块：走到它就播放/切换音频（动作块，进流程）。
    Audio {
        key: String,
        path: String,
        kind: AudioKind,
        looping: bool,
        volume: f64,
        next: Option<String>,
    },
    /// 循环块：body 端口连出去的子图被反复执行；子图尾节点连回本块 = 下一次迭代。
    /// kind 决定判定方式、expr 提供计数/条件/列表变量 —— 三种模式共用一套帧栈，
    /// 新增模式只需加 LoopKind 变体 + VM 一个 match 臂，扩展点集中。
    Loop {
        kind: LoopKind,
        expr: String,
        body: Option<String>,
        next: Option<String>,
        max_iters: u64,
    },
    /// 排版块：组合块（group）的一次「单个渲染预览」排版结果。
    /// items 记录组内每个节点在预览画布上的位置/缩放/透明度/旋转；
    /// 由编辑器预览生成并连回组合块，播放器按 items 定位渲染。
    Layout {
        group: String,
        items: Vec<LayoutItem>,
        next: Option<String>,
    },
}

/// 排版块里一个元素的位置快照
#[derive(Debug, Clone, PartialEq)]
pub struct LayoutItem {
    pub node: String,
    pub x: f64,
    pub y: f64,
    pub scale: f64,
    pub opacity: f64,
    pub rot: f64,
}

/// 音频用途：BGM 循环铺底 / Sfx 一次性音效 / Voice 台词配音
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioKind {
    Bgm,
    Sfx,
    Voice,
}

impl AudioKind {
    pub fn as_str(self) -> &'static str {
        match self {
            AudioKind::Bgm => "bgm",
            AudioKind::Sfx => "sfx",
            AudioKind::Voice => "voice",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "sfx" => AudioKind::Sfx,
            "voice" => AudioKind::Voice,
            _ => AudioKind::Bgm,
        }
    }
    pub fn default_looping(self) -> bool {
        matches!(self, AudioKind::Bgm)
    }
}

/// 循环判定模式：Count=expr 为次数 / While=expr 为条件 / ForEach=expr 为列表变量名
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoopKind {
    Count,
    While,
    ForEach,
}

impl LoopKind {
    pub fn as_str(self) -> &'static str {
        match self {
            LoopKind::Count => "count",
            LoopKind::While => "while",
            LoopKind::ForEach => "foreach",
        }
    }
    pub fn from_str(s: &str) -> Self {
        match s {
            "while" => LoopKind::While,
            "foreach" => LoopKind::ForEach,
            _ => LoopKind::Count,
        }
    }
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
            NodeKind::Script { .. } => "script",
            NodeKind::Character { .. } => "character",
            NodeKind::Portrait { .. } => "portrait",
            NodeKind::Background { .. } => "background",
            NodeKind::Label { .. } => "label",
            NodeKind::Value { .. } => "value",
            NodeKind::Variable { .. } => "variable",
            NodeKind::Weighted { .. } => "weighted",
            NodeKind::Image { .. } => "image",
            NodeKind::Audio { .. } => "audio",
            NodeKind::Loop { .. } => "loop",
            NodeKind::Layout { .. } => "layout",
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
            NodeKind::Script { .. } => "#ff7a45",
            NodeKind::Character { .. } => "#7aa2f7",
            NodeKind::Portrait { .. } => "#c3a6ff",
            NodeKind::Background { .. } => "#68d5ba",
            NodeKind::Image { .. } => "#5ec8d8",
            NodeKind::Audio { .. } => "#f7c948",
            NodeKind::Loop { .. } => "#ff9f43",
            NodeKind::Layout { .. } => "#8ea2ff",
            NodeKind::Label { .. } => "#ffffff",
            NodeKind::Value { .. } => "#8fbcbb",
            NodeKind::Variable { .. } => "#a3be8c",
            NodeKind::Weighted { .. } => "#d08770",
        }
    }
}

/// 一组方块（用于合并显示 / 分组管理）
#[derive(Debug, Clone)]
pub struct Group {
    pub id: String,
    pub title: String,
    /// 这一组是否折叠成"一个合并方块"（每组的独立开关）
    pub collapsed: bool,
    pub nodes: Vec<String>,
    pub color: Option<String>,
    /// 父组 id（合并块可以再分组，v0.2 只做一层嵌套）
    pub parent: Option<String>,
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
            NodeKind::Say {
                next, cast, art, bg, ..
            } => {
                if let Some(n) = next {
                    v.push(("next".to_string(), n.clone()));
                }
                // 同一端口名出现多次 = 一对多（多个人连同一句台词）
                for c in cast {
                    v.push(("cast".to_string(), c.clone()));
                }
                for a in art {
                    v.push(("art".to_string(), a.clone()));
                }
                for b in bg {
                    v.push(("bg".to_string(), b.clone()));
                }
            }
            NodeKind::Set { next, .. } => {
                if let Some(n) = next {
                    v.push(("next".to_string(), n.clone()));
                }
            }
            NodeKind::Character { next, .. }
            | NodeKind::Portrait { next, .. }
            | NodeKind::Background { next, .. }
            | NodeKind::Label { next, .. }
            | NodeKind::Image { next, .. }
            | NodeKind::Audio { next, .. } => {
                if let Some(n) = next {
                    v.push(("next".to_string(), n.clone()));
                }
            }
            NodeKind::Layout { next, .. } => {
                if let Some(n) = next {
                    v.push(("next".to_string(), n.clone()));
                }
            }
            NodeKind::Loop { body, next, .. } => {
                if let Some(b) = body {
                    v.push(("body".to_string(), b.clone()));
                }
                if let Some(n) = next {
                    v.push(("next".to_string(), n.clone()));
                }
            }
            NodeKind::Value { .. } => {}
            NodeKind::Variable { add, next, .. } => {
                for a in add {
                    v.push(("add".to_string(), a.clone()));
                }
                if let Some(n) = next {
                    v.push(("next".to_string(), n.clone()));
                }
            }
            NodeKind::Script { next, .. } => {
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
            NodeKind::Weighted { branches, .. } => {
                for (i, b) in branches.iter().enumerate() {
                    if !b.to.is_empty() {
                        v.push((format!("w{}", i), b.to.clone()));
                    }
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
            (NodeKind::Say { cast, .. }, "cast") => match target {
                Some(t) => {
                    if !cast.contains(&t) {
                        cast.push(t);
                    }
                }
                None => cast.clear(),
            },
            (NodeKind::Say { art, .. }, "art") => match target {
                Some(t) => {
                    if !art.contains(&t) {
                        art.push(t);
                    }
                }
                None => art.clear(),
            },
            (NodeKind::Say { bg, .. }, "bg") => match target {
                Some(t) => {
                    if !bg.contains(&t) {
                        bg.push(t);
                    }
                }
                None => bg.clear(),
            },
            (NodeKind::Character { next, .. }, "next") => *next = target,
            (NodeKind::Portrait { next, .. }, "next") => *next = target,
            (NodeKind::Background { next, .. }, "next") => *next = target,
            (NodeKind::Image { next, .. }, "next") => *next = target,
            (NodeKind::Audio { next, .. }, "next") => *next = target,
            (NodeKind::Loop { body, .. }, "body") => *body = target,
            (NodeKind::Loop { next, .. }, "next") => *next = target,
            (NodeKind::Layout { next, .. }, "next") => *next = target,
            (NodeKind::Label { next, .. }, "next") => *next = target,
            (NodeKind::Variable { add, .. }, "add") => match target {
                Some(t) => {
                    if !add.contains(&t) {
                        add.push(t);
                    }
                }
                None => add.clear(),
            },
            (NodeKind::Variable { next, .. }, "next") => *next = target,
            (NodeKind::Set { next, .. }, "next") => *next = target,
            (NodeKind::Script { next, .. }, "next") => *next = target,
            (NodeKind::Branch { yes, .. }, "yes") => *yes = target,
            (NodeKind::Branch { no, .. }, "no") => *no = target,
            (NodeKind::Jump { to }, "to") => *to = target,
            (NodeKind::Call { to, .. }, "to") => *to = target,
            (NodeKind::Call { next, .. }, "back") => *next = target,
            (NodeKind::Weighted { branches, .. }, p) if p.starts_with('w') => {
                if let Ok(i) = p[1..].parse::<usize>() {
                    if let Some(b) = branches.get_mut(i) {
                        b.to = target.unwrap_or_default();
                    }
                }
            }
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
    /// 分组 / 合并显示
    pub groups: Vec<Group>,
    /// 完成度标记：节点 id -> "wip"/"done"（缺省 = todo，不存储以省体积）
    pub status: BTreeMap<String, String>,
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
            groups: Vec::new(),
            status: BTreeMap::new(),
            index: HashMap::new(),
        }
    }

    /// 完成度统计：(todo, wip, done)，按节点数计。
    pub fn progress(&self) -> (usize, usize, usize) {
        let (mut t, mut w, mut d) = (0, 0, 0);
        for n in &self.nodes {
            match self.status.get(&n.id).map(|s| s.as_str()).unwrap_or("todo") {
                "done" => d += 1,
                "wip" => w += 1,
                _ => t += 1,
            }
        }
        (t, w, d)
    }

    /// 分支级完成度：能从该节点顺着连线走到某个 End 的节点集合（反向 BFS）。
    /// 完成度不是节点手动标记，而是「这条分支是否以结尾收尾」。
    pub fn reaches_end(&self) -> BTreeSet<String> {
        let mut rev: BTreeMap<String, Vec<String>> = BTreeMap::new();
        let mut ends: Vec<String> = Vec::new();
        for n in &self.nodes {
            if matches!(n.kind, NodeKind::End { .. }) {
                ends.push(n.id.clone());
            }
            for (_port, t) in n.ports() {
                rev.entry(t).or_default().push(n.id.clone());
            }
        }
        let mut reach: BTreeSet<String> = ends.iter().cloned().collect();
        let mut queue: VecDeque<String> = ends.into_iter().collect();
        while let Some(v) = queue.pop_front() {
            if let Some(us) = rev.get(&v) {
                for u in us {
                    if reach.insert(u.clone()) {
                        queue.push_back(u.clone());
                    }
                }
            }
        }
        reach
    }

    /// (以结尾收尾的节点数, 总节点数)
    pub fn completion(&self) -> (usize, usize) {
        let reach = self.reaches_end();
        let done = self.nodes.iter().filter(|n| reach.contains(&n.id)).count();
        (done, self.nodes.len())
    }

    /// 设置节点完成度；"todo" 会移除记录（省体积）。
    pub fn set_status(&mut self, id: &str, status: &str) {
        if status == "todo" || status.is_empty() {
            self.status.remove(id);
        } else {
            self.status.insert(id.to_string(), status.to_string());
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
                text,
                next,
                cast,
                art,
                bg,
            } => {
                o.set("text", Json::s(text.clone()));
                opt(next, "next", &mut o);
                if !cast.is_empty() {
                    o.set(
                        "cast",
                        Json::Arr(cast.iter().map(|x| Json::s(x.clone())).collect()),
                    );
                }
                if !art.is_empty() {
                    o.set(
                        "art",
                        Json::Arr(art.iter().map(|x| Json::s(x.clone())).collect()),
                    );
                }
                if !bg.is_empty() {
                    o.set(
                        "bg",
                        Json::Arr(bg.iter().map(|x| Json::s(x.clone())).collect()),
                    );
                }
            }
            NodeKind::Weighted { prompt, branches } => {
                o.set("prompt", Json::s(prompt.clone()));
                let mut arr = Json::arr();
                for b in branches {
                    let mut bo = Json::obj();
                    bo.set("to", Json::s(b.to.clone()));
                    bo.set("weight", Json::s(b.weight.clone()));
                    if !b.cond.is_empty() {
                        bo.set("cond", Json::s(b.cond.clone()));
                    }
                    arr.push(bo);
                }
                o.set("branches", arr);
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
            NodeKind::Label { tag, text, next } => {
                if let Some(t) = tag {
                    o.set("tag", Json::s(t.clone()));
                }
                o.set("text", Json::s(text.clone()));
                opt(next, "next", &mut o);
            }
            NodeKind::Value { expr } => {
                o.set("expr", Json::s(expr.clone()));
            }
            NodeKind::Variable { name, add, next } => {
                o.set("name", Json::s(name.clone()));
                if !add.is_empty() {
                    o.set(
                        "add",
                        Json::Arr(add.iter().map(|x| Json::s(x.clone())).collect()),
                    );
                }
                opt(next, "next", &mut o);
            }
            NodeKind::Character {
                key,
                name,
                color,
                portraits,
                next,
            } => {
                o.set("key", Json::s(key.clone()));
                o.set("name", Json::s(name.clone()));
                if let Some(c) = color {
                    o.set("color", Json::s(c.clone()));
                }
                if !portraits.is_empty() {
                    o.set(
                        "portraits",
                        Json::Arr(portraits.iter().map(|p| Json::s(p.clone())).collect()),
                    );
                }
                opt(next, "next", &mut o);
            }
            NodeKind::Portrait {
                character,
                asset,
                expr,
                next,
            } => {
                opt(character, "character", &mut o);
                o.set("asset", Json::s(asset.clone()));
                opt(expr, "expr", &mut o);
                opt(next, "next", &mut o);
            }
            NodeKind::Background {
                asset,
                scene,
                next,
            } => {
                o.set("asset", Json::s(asset.clone()));
                opt(scene, "scene", &mut o);
                opt(next, "next", &mut o);
            }
            NodeKind::Script {
                engine,
                code,
                src,
                entry,
                next,
            } => {
                o.set("engine", Json::s(engine.as_str()));
                if let Some(c) = code {
                    o.set("code", Json::s(c.clone()));
                }
                if let Some(s) = src {
                    o.set("src", Json::s(s.clone()));
                }
                o.set("entry", Json::s(entry.clone()));
                opt(next, "next", &mut o);
            }
            NodeKind::Image { key, path, label, next } => {
                o.set("key", Json::s(key.clone()));
                o.set("path", Json::s(path.clone()));
                opt(label, "label", &mut o);
                opt(next, "next", &mut o);
            }
            NodeKind::Audio { key, path, kind, looping, volume, next } => {
                o.set("key", Json::s(key.clone()));
                o.set("path", Json::s(path.clone()));
                o.set("kind", Json::s(kind.as_str()));
                o.set("loop", Json::b(*looping));
                o.set("volume", Json::Num(*volume));
                opt(next, "next", &mut o);
            }
            NodeKind::Layout { group, items, next } => {
                o.set("group", Json::s(group.clone()));
                o.set("items", Json::Arr(items.iter().map(|it| {
                    let mut io = Json::obj();
                    io.set("node", Json::s(it.node.clone()));
                    io.set("x", Json::n(it.x));
                    io.set("y", Json::n(it.y));
                    io.set("scale", Json::n(it.scale));
                    io.set("opacity", Json::n(it.opacity));
                    io.set("rot", Json::n(it.rot));
                    io
                }).collect()));
                opt(next, "next", &mut o);
            }
            NodeKind::Loop { kind, expr, body, next, max_iters } => {
                o.set("kind", Json::s(kind.as_str()));
                o.set("expr", Json::s(expr.clone()));
                opt(body, "body", &mut o);
                opt(next, "next", &mut o);
                o.set("maxIters", Json::n(*max_iters as f64));
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

        let mut groups = Json::arr();
        for g in &self.groups {
            let mut go = Json::obj();
            go.set("id", Json::s(g.id.clone()));
            go.set("title", Json::s(g.title.clone()));
            go.set("collapsed", Json::b(g.collapsed));
            go.set(
                "nodes",
                Json::Arr(g.nodes.iter().map(|n| Json::s(n.clone())).collect()),
            );
            if let Some(c) = &g.color {
                go.set("color", Json::s(c.clone()));
            }
            if let Some(p) = &g.parent {
                go.set("parent", Json::s(p.clone()));
            }
            groups.push(go);
        }
        root.set("groups", groups);
        let mut st = Json::obj();
        let mut any_status = false;
        for (id, v) in &self.status {
            if v != "todo" && !v.is_empty() {
                st.set(id, Json::s(v.clone()));
                any_status = true;
            }
        }
        // 空则省略，保持包体紧凑、也不给旧样例引入无谓 diff
        if any_status {
            root.set("status", st);
        }
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
                "script" => NodeKind::Script {
                    engine: ScriptEngine::from_str(&nj.s_or("engine", "rust")),
                    code: nj.opt_str("code"),
                    src: nj.opt_str("src"),
                    entry: {
                        let e = nj.s_or("entry", "main");
                        if e.is_empty() {
                            "main".to_string()
                        } else {
                            e
                        }
                    },
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
                "return" => NodeKind::Return,
                "end" => NodeKind::End {
                    ending: nj.s_or("ending", "end"),
                    text: nj.s_or("text", ""),
                },
                "weighted" => {
                    let mut branches = Vec::new();
                    for bj in nj.arr_or_empty("branches") {
                        branches.push(WeightedBranch {
                            to: bj.s_or("to", ""),
                            weight: bj.s_or("weight", "1"),
                            cond: bj.s_or("cond", ""),
                        });
                    }
                    NodeKind::Weighted {
                        prompt: nj.s_or("prompt", ""),
                        branches,
                    }
                }
                // 旧数据里的 marker 自动升级成 label（tag 保留，text 先用 tag）
                "marker" => {
                    let tag = nj.s_or("tag", &id);
                    NodeKind::Label {
                        tag: Some(tag.clone()),
                        text: tag,
                        next: nj.opt_str("next").filter(|s| !s.is_empty()),
                    }
                }
                "label" => NodeKind::Label {
                    tag: nj.opt_str("tag").filter(|s| !s.is_empty()),
                    text: nj.s_or("text", ""),
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
                "value" => NodeKind::Value {
                    expr: nj.s_or("expr", "1"),
                },
                "variable" => NodeKind::Variable {
                    name: nj.s_or("name", ""),
                    add: {
                        match nj.get("add") {
                            Some(Json::Str(x)) if !x.is_empty() => vec![x.clone()],
                            Some(Json::Arr(a)) => a
                                .iter()
                                .filter_map(|v| v.as_str().map(|x| x.to_string()))
                                .collect(),
                            _ => Vec::new(),
                        }
                    },
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
                "character" => NodeKind::Character {
                    key: nj.s_or("key", &id),
                    name: {
                        let n = nj.s_or("name", "");
                        if n.is_empty() { nj.s_or("key", "角色") } else { n }
                    },
                    color: nj.opt_str("color"),
                    portraits: nj
                        .arr_or_empty("portraits")
                        .iter()
                        .filter_map(|v| v.as_str().map(|x| x.to_string()))
                        .collect(),
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
                "portrait" => NodeKind::Portrait {
                    character: nj.opt_str("character").filter(|s| !s.is_empty()),
                    asset: nj.s_or("asset", ""),
                    expr: nj.opt_str("expr").filter(|s| !s.is_empty()),
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
                "background" => NodeKind::Background {
                    asset: nj.s_or("asset", ""),
                    scene: nj.opt_str("scene").filter(|s| !s.is_empty()),
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
                "image" => NodeKind::Image {
                    key: nj.s_or("key", ""),
                    path: nj.s_or("path", ""),
                    label: nj.opt_str("label").filter(|s| !s.is_empty()),
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
                "layout" => NodeKind::Layout {
                    group: nj.s_or("group", ""),
                    items: nj.arr_or_empty("items").iter().map(|io| LayoutItem {
                        node: io.s_or("node", ""),
                        x: io.num_or("x", 0.0),
                        y: io.num_or("y", 0.0),
                        scale: io.num_or("scale", 1.0),
                        opacity: io.num_or("opacity", 1.0),
                        rot: io.num_or("rot", 0.0),
                    }).collect(),
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                },
                "loop" => NodeKind::Loop {
                    kind: LoopKind::from_str(&nj.s_or("kind", "count")),
                    expr: nj.s_or("expr", "0"),
                    body: nj.opt_str("body").filter(|s| !s.is_empty()),
                    next: nj.opt_str("next").filter(|s| !s.is_empty()),
                    max_iters: nj.num_or("maxIters", 1000.0) as u64,
                },
                "audio" => {
                    let kind = AudioKind::from_str(&nj.s_or("kind", "bgm"));
                    NodeKind::Audio {
                        key: nj.s_or("key", ""),
                        path: nj.s_or("path", ""),
                        kind,
                        looping: nj.bool_or("loop", kind.default_looping()),
                        volume: nj.num_or("volume", 1.0),
                        next: nj.opt_str("next").filter(|s| !s.is_empty()),
                    }
                }
                _ => {
                    // 端口值既接受字符串也接受字符串数组
                    let many = |key: &str| -> Vec<String> {
                        match nj.get(key) {
                            Some(Json::Str(x)) if !x.is_empty() => vec![x.clone()],
                            Some(Json::Arr(a)) => a
                                .iter()
                                .filter_map(|v| v.as_str().map(|x| x.to_string()))
                                .filter(|x| !x.is_empty())
                                .collect(),
                            _ => Vec::new(),
                        }
                    };
                    NodeKind::Say {
                        text: nj.s_or("text", ""),
                        next: nj.opt_str("next").filter(|s| !s.is_empty()),
                        cast: many("cast"),
                        art: many("art"),
                        bg: many("bg"),
                    }
                }
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
        for gj in j.arr_or_empty("groups") {
            let gid = gj.s_or("id", "");
            if gid.is_empty() {
                continue;
            }
            s.groups.push(Group {
                id: gid,
                title: gj.s_or("title", "分组"),
                collapsed: gj.bool_or("collapsed", false),
                nodes: gj
                    .arr_or_empty("nodes")
                    .iter()
                    .filter_map(|v| v.as_str().map(|x| x.to_string()))
                    .collect(),
                color: gj.opt_str("color"),
                parent: gj.opt_str("parent").filter(|x| !x.is_empty()),
            });
        }
        if let Some(Json::Obj(st)) = j.get("status") {
            for (id, v) in st {
                if let Json::Str(x) = v {
                    if x == "wip" || x == "done" {
                        s.status.insert(id.clone(), x.clone());
                    }
                }
            }
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
                text: text.to_string(),
                next: None,
                // 兼容旧调用：传了 speaker 就自动接一个同名标记名
                cast: speaker.map(|s| vec![s.to_string()]).unwrap_or_default(),
                art: Vec::new(),
                bg: Vec::new(),
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
    fn branch_completion_via_reaches_end() {
        let mut s = Story::new("t", "a");
        s.add_node(Story::mk_say("a", 0.0, 0.0, None, "起"));
        s.add_node(Story::mk_say("good", 0.0, 0.0, None, "好"));
        s.add_node(Story::mk_say("dead", 0.0, 0.0, None, "断头"));
        s.add_node(Story::mk_end("e", 0.0, 0.0, "g", "完"));
        s.node_mut("a").unwrap().set_port("next", Some("good".into()));
        s.node_mut("good").unwrap().set_port("next", Some("e".into()));
        // dead 没有出口 → 走不到 End
        let reach = s.reaches_end();
        assert!(reach.contains("a") && reach.contains("good") && reach.contains("e"));
        assert!(!reach.contains("dead"), "断头分支不算完成");
        assert_eq!(s.completion(), (3, 4));
    }

    #[test]
    fn status_roundtrip_and_progress() {
        let mut s = Story::new("t", "a");
        s.add_node(Story::mk_say("a", 0.0, 0.0, None, "一"));
        s.add_node(Story::mk_say("b", 0.0, 0.0, None, "二"));
        s.add_node(Story::mk_end("e", 0.0, 0.0, "g", "完"));
        s.set_status("a", "done");
        s.set_status("b", "wip");
        assert_eq!(s.progress(), (1, 1, 1));
        let j = s.to_json();
        let mut s2 = Story::from_json(&j).unwrap();
        assert_eq!(s2.to_json(), j, "status 往返必须无损");
        assert_eq!(s2.progress(), (1, 1, 1));
        s2.set_status("a", "todo");
        assert!(!s2.status.contains_key("a"), "todo 应移除记录");
        assert_eq!(s2.progress(), (2, 1, 0));
    }

    #[test]
    fn image_audio_json_roundtrip() {
        let mut s = Story::new("t", "a");
        s.add_node(Node { id: "img".into(), x: 0.0, y: 0.0, title: None,
            kind: NodeKind::Image { key: "bg1".into(), path: "assets/bg.webp".into(),
                label: Some("雨夜".into()), next: None } });
        s.add_node(Node { id: "aud".into(), x: 0.0, y: 0.0, title: None,
            kind: NodeKind::Audio { key: "bgm1".into(), path: "assets/rain.ogg".into(),
                kind: AudioKind::Bgm, looping: true, volume: 0.8, next: Some("a".into()) } });
        s.add_node(Story::mk_say("a", 0.0, 0.0, None, "你好"));
        s.add_node(Story::mk_end("e", 0.0, 0.0, "good", "完"));
        s.node_mut("a").unwrap().set_port("next", Some("e".into()));
        let j = s.to_json();
        let s2 = Story::from_json(&j).unwrap();
        assert_eq!(s2.to_json(), j, "Image/Audio 往返必须无损");
        assert!(matches!(s2.node("img").unwrap().kind, NodeKind::Image { .. }));
        assert!(matches!(s2.node("aud").unwrap().kind, NodeKind::Audio { kind: AudioKind::Bgm, .. }));
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

    #[test]
    fn groups_and_asset_nodes() {
        let mut s = Story::new("作品图", "c1");
        s.add_node(Node {
            id: "c1".into(),
            x: 0.0,
            y: 0.0,
            title: None,
            kind: NodeKind::Character {
                key: "yuki".into(),
                name: "雪".into(),
                color: Some("#7aa2f7".into()),
                portraits: vec!["a.png".into(), "b.png".into()],
                next: None,
            },
        });
        s.add_node(Node {
            id: "p1".into(),
            x: 0.0,
            y: 100.0,
            title: None,
            kind: NodeKind::Portrait {
                character: Some("c1".into()),
                asset: "assets/yuki_a.png".into(),
                expr: Some("smile".into()),
                next: None,
            },
        });
        s.add_node(Node {
            id: "b1".into(),
            x: 0.0,
            y: 200.0,
            title: None,
            kind: NodeKind::Background {
                asset: "assets/store.png".into(),
                scene: Some("便利店·夜".into()),
                next: None,
            },
        });
        let mut say = Story::mk_say("s1", 0.0, 300.0, Some("yuki"), "欢迎光临。");
        say.set_port("cast", Some("c1".into()));
        say.set_port("art", Some("p1".into()));
        s.add_node(say);
        s.groups.push(Group {
            id: "g1".into(),
            title: "第一章 · 雨夜".into(),
            collapsed: true,
            nodes: vec!["c1".into(), "p1".into(), "s1".into()],
            color: Some("#19d1ff".into()),
            parent: None,
        });

        // 端口：台词连到了角色与立绘（cast 是多值端口，先有 mk_say 传的 speaker）
        let say_node = s.node("s1").unwrap();
        let casts: Vec<String> = say_node
            .ports()
            .into_iter()
            .filter(|(p, _)| p == "cast")
            .map(|(_, t)| t)
            .collect();
        assert!(casts.contains(&"c1".to_string()), "cast 里应该有 c1：{:?}", casts);
        assert_eq!(say_node.port_target("art"), Some("p1".into()));

        // JSON 往返
        let text = s.to_json_string_pretty();
        let s2 = Story::from_json_str(&text).unwrap();
        assert_eq!(s2.groups.len(), 1);
        assert_eq!(s2.groups[0].title, "第一章 · 雨夜");
        assert!(s2.groups[0].collapsed);
        assert_eq!(s2.groups[0].nodes.len(), 3);
        assert!(matches!(
            s2.node("c1").unwrap().kind,
            NodeKind::Character { .. }
        ));
        assert!(matches!(
            s2.node("p1").unwrap().kind,
            NodeKind::Portrait { .. }
        ));
        assert!(matches!(
            s2.node("b1").unwrap().kind,
            NodeKind::Background { .. }
        ));
        assert_eq!(s2.to_json(), s.to_json());

        // lint：组里放一个不存在的方块要报错
        let mut bad = s.clone();
        bad.groups[0].nodes.push("ghost".into());
        let issues = crate::lint::lint(&bad);
        assert!(issues.iter().any(|i| i.kind == "group-dangling"));
    }
}
