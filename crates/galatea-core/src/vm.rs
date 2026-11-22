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
        /// 多人同框时除第一张以外的立绘
        extra_portraits: Vec<String>,
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
    /// 执行了一个自定义脚本节点
    Script {
        node: String,
        /// "rust" | "godot"
        engine: String,
        /// godot 引擎时的脚本路径
        src: Option<String>,
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

/// 确定性随机数（xorshift64*）：相同种子 + 相同调用次数 = 相同结果，
/// 所以存档里存下 state 就能做到"读档后剧情走向不变"。
#[derive(Debug, Clone)]
pub struct Rng {
    pub state: u64,
}

/// 每次启动换一个种子（同一局之内仍然确定）
fn time_seed() -> u64 {
    match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
        Ok(d) => (d.as_secs() << 20) ^ d.subsec_nanos() as u64,
        Err(_) => 0x0DA7_A5EE_D,
    }
}

impl Rng {
    pub fn new(seed: u64) -> Self {
        Rng {
            state: if seed == 0 { 0x9E37_79B9_7F4A_7C15 } else { seed },
        }
    }
    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.state = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    /// [0, 1)
    pub fn next_f64(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
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
    /// 加权分支用的随机数（状态会存档）
    pub rng: Rng,
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
            rng: Rng::new(time_seed()),
            scripts: BTreeMap::new(),
            script_base: std::env::current_dir()
                .unwrap_or_else(|_| std::path::PathBuf::from(".")),
        }
    }

    /// 从剧本的第一个节点开始
    pub fn restart(&mut self) {
        // 每局换一个种子，但一局之内是确定的
        let seed = self.rng.next_u64() ^ 0x5DEECE66D;
        self.rng = Rng::new(seed);
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
                    text,
                    next,
                    cast,
                    art,
                    bg,
                } => {
                    self.push_snapshot();

                    // art 端口 → 立绘方块里的真实资源路径（可多个，先取第一个）
                    let art_paths: Vec<String> = art
                        .iter()
                        .filter_map(|id| self.story.node(id))
                        .filter_map(|n| match &n.kind {
                            NodeKind::Portrait { asset, .. } => Some(asset.clone()),
                            _ => None,
                        })
                        .collect();

                    // cast 端口 → 每个人的显示名（顺着 marker→label 或 character 解析）
                    let mut names: Vec<String> = Vec::new();
                    let mut first_color: Option<String> = None;
                    for cid in &cast {
                        let Some(cn) = self.story.node(cid) else {
                            // 兼容：cast 里直接写了 characters 表的 key（旧剧本）
                            let (nm, color, _) = self.speaker_info(&Some(cid.clone()), None);
                            if !nm.is_empty() && !names.contains(&nm) {
                                names.push(nm);
                            }
                            if first_color.is_none() {
                                first_color = color;
                            }
                            continue;
                        };
                        let key = match &cn.kind {
                            NodeKind::Character { key, .. } => key.clone(),
                            NodeKind::Marker { tag, .. } => tag.clone(),
                            NodeKind::Label { .. } => {
                                // 直接连了显示名
                                if let NodeKind::Label { text, .. } = &cn.kind {
                                    names.push(text.clone());
                                }
                                continue;
                            }
                            _ => continue,
                        };
                        let (nm, color, _) = self.speaker_info(&Some(key), None);
                        if !nm.is_empty() && !names.contains(&nm) {
                            names.push(nm);
                        }
                        if first_color.is_none() {
                            first_color = color;
                        }
                    }

                    // 多人同声时用「、」连起来；一个都没有 = 旁白
                    let speaker_name = names.join("、");
                    let speaker_key = cast.first().cloned();

                    let bg_path = bg.first().and_then(|id| self.story.node(id)).and_then(|n| {
                        match &n.kind {
                            NodeKind::Background { asset, .. } => Some(asset.clone()),
                            _ => None,
                        }
                    });
                    let portrait = art_paths.first().cloned();

                    self.log.push(if speaker_name.is_empty() {
                        text.clone()
                    } else {
                        format!("{}：{}", speaker_name, text)
                    });
                    self.pc = next;
                    return Event::Say {
                        node: pc,
                        speaker: speaker_key,
                        speaker_name,
                        color: first_color,
                        text,
                        bg: bg_path,
                        portrait,
                        extra_portraits: art_paths.iter().skip(1).cloned().collect(),
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
                | NodeKind::Background { next, .. }
                | NodeKind::Marker { next, .. }
                | NodeKind::Label { next, .. } => {
                    self.pc = next;
                }
                // 加权块：满足条件就给变量加权
                NodeKind::Weight {
                    target,
                    amount,
                    cond,
                    next,
                } => {
                    if cond.is_empty() || self.eval_cond(&cond) {
                        let delta = self
                            .eval_expr(&amount)
                            .map(|v| crate::expr::to_num(&v))
                            .unwrap_or(0.0);
                        let cur = crate::expr::to_num(&self.var(&target));
                        self.set_var(&target, Json::Num(cur + delta));
                    }
                    self.pc = next;
                }
                // 加权分支：按权重掷一次
                NodeKind::Weighted { branches, .. } => {
                    let mut pool: Vec<(f64, String)> = Vec::new();
                    for b in &branches {
                        if !b.cond.is_empty() && !self.eval_cond(&b.cond) {
                            continue;
                        }
                        if b.to.is_empty() {
                            continue;
                        }
                        let w = self
                            .eval_expr(&b.weight)
                            .map(|v| crate::expr::to_num(&v))
                            .unwrap_or(0.0);
                        if w > 0.0 {
                            pool.push((w, b.to.clone()));
                        }
                    }
                    if pool.is_empty() {
                        return Event::Halt {
                            reason: format!(
                                "加权分支 `{}` 没有可用路线（权重全为 0 或条件全不满足）",
                                pc
                            ),
                        };
                    }
                    let total: f64 = pool.iter().map(|(w, _)| *w).sum();
                    let mut r = self.rng.next_f64() * total;
                    let mut chosen = pool[pool.len() - 1].1.clone();
                    for (w, to) in &pool {
                        if r <= *w {
                            chosen = to.clone();
                            break;
                        }
                        r -= w;
                    }
                    self.pc = Some(chosen);
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
                    engine,
                    code,
                    src,
                    entry,
                    next,
                } => {
                    // Godot 脚本：不由本 VM 执行，抛给运行时（Godot 侧 await 完再 advance）
                    if engine == crate::graph::ScriptEngine::Godot {
                        self.pc = next;
                        return Event::Script {
                            node: pc,
                            engine: "godot".to_string(),
                            src: src.clone(),
                            entry,
                            ret: Json::Null,
                            emits: BTreeMap::new(),
                        };
                    }
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
                                engine: "rust".to_string(),
                                src: None,
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
            Some(k) => {
                // 1. 传统 characters 表
                if let Some(c) = self.story.characters.get(k) {
                    return (
                        c.name.clone(),
                        c.color.clone(),
                        portrait.or_else(|| c.avatar.clone()),
                    );
                }
                // 2. 标记名方块：顺着 next 连到的「显示名」方块取文字
                for n in &self.story.nodes {
                    if let NodeKind::Marker { tag, next } = &n.kind {
                        if tag == k || &n.id == k {
                            if let Some(lid) = next {
                                if let Some(ln) = self.story.node(lid) {
                                    if let NodeKind::Label { text, .. } = &ln.kind {
                                        return (text.clone(), None, portrait);
                                    }
                                }
                            }
                            return (tag.clone(), None, portrait);
                        }
                    }
                }
                // 3. v0.2 的 character 方块（按 key 或方块 id 匹配）
                for n in &self.story.nodes {
                    if let NodeKind::Character {
                        key,
                        name,
                        color,
                        portraits,
                        ..
                    } = &n.kind
                    {
                        if key == k || &n.id == k {
                            let p = portrait
                                .or_else(|| portraits.first().cloned());
                            return (name.clone(), color.clone(), p);
                        }
                    }
                }
                (k.clone(), None, portrait)
            }
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
        // u64 超出 f64 的 53 位精度，存字符串
        o.set("rng", Json::s(self.rng.state.to_string()));
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
        if let Some(node) = j.get("rng") {
            let seed = node
                .as_str()
                .and_then(|x| x.parse::<u64>().ok())
                .or_else(|| node.as_f64().map(|x| x as u64));
            if let Some(seed) = seed {
                self.rng = Rng::new(seed);
            }
        }
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

    #[test]
    fn weight_and_weighted() {
        let mut s = Story::new("t", "w1");
        s.vars.insert("勇气".into(), Json::Num(0.0));
        s.add_node(crate::graph::Node {
            id: "w1".into(),
            x: 0.0,
            y: 0.0,
            title: None,
            kind: NodeKind::Weight {
                target: "勇气".into(),
                amount: "2".into(),
                cond: String::new(),
                next: Some("wb".into()),
            },
        });
        s.add_node(crate::graph::Node {
            id: "wb".into(),
            x: 0.0,
            y: 100.0,
            title: None,
            kind: NodeKind::Weighted {
                prompt: String::new(),
                branches: vec![
                    crate::graph::WeightedBranch::new("a", "1"),
                    crate::graph::WeightedBranch::new("b", "3"),
                ],
            },
        });
        s.add_node(Story::mk_say("a", 0.0, 200.0, None, "走到 A"));
        s.add_node(Story::mk_say("b", 0.0, 200.0, None, "走到 B"));

        let mut vm = Vm::new(s);
        match vm.step() {
            Event::Say { text, .. } => assert!(text == "走到 A" || text == "走到 B"),
            other => panic!("{:?}", other),
        }
        // 加权块把勇气 +2 了
        assert_eq!(vm.var("勇气"), Json::Num(2.0));
    }

    #[test]
    fn weighted_respects_conditions_and_zero() {
        let mut s = Story::new("t", "wb");
        s.add_node(crate::graph::Node {
            id: "wb".into(),
            x: 0.0,
            y: 0.0,
            title: None,
            kind: NodeKind::Weighted {
                prompt: String::new(),
                branches: vec![
                    crate::graph::WeightedBranch {
                        to: "a".into(),
                        weight: "1".into(),
                        cond: "假".into(), // 条件不满足 → 排除
                    },
                    crate::graph::WeightedBranch::new("b", "0"), // 权重 0 → 排除
                    crate::graph::WeightedBranch::new("c", "5"),
                ],
            },
        });
        for id in ["a", "b", "c"] {
            s.add_node(Story::mk_say(id, 0.0, 100.0, None, id));
        }
        let mut vm = Vm::new(s);
        match vm.step() {
            Event::Say { text, .. } => assert_eq!(text, "c"),
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn save_restores_rng() {
        // 存档 → 读出同样的 rng 状态 → 后续路线一致
        let mut s = Story::new("t", "wb");
        s.add_node(crate::graph::Node {
            id: "wb".into(),
            x: 0.0,
            y: 0.0,
            title: None,
            kind: NodeKind::Weighted {
                prompt: String::new(),
                branches: vec![
                    crate::graph::WeightedBranch::new("a", "1"),
                    crate::graph::WeightedBranch::new("b", "1"),
                ],
            },
        });
        s.add_node(Story::mk_say("a", 0.0, 100.0, None, "A"));
        s.add_node(Story::mk_say("b", 0.0, 100.0, None, "B"));

        let mut vm = Vm::new(s.clone());
        let first = match vm.step() {
            Event::Say { text, .. } => text,
            _ => panic!(),
        };
        let snap = vm.save_json();
        let mut vm2 = Vm::new(s);
        vm2.load(&snap).unwrap();
        // 读档后 rng 状态一致：再掷一次结果应该可复现
        let mut a = vm.rng.clone();
        let mut b = vm2.rng.clone();
        assert_eq!(a.next_u64(), b.next_u64());
        assert!(first == "A" || first == "B");
    }
}
