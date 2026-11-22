//! 自定义 Rust 脚本宿主。
//!
//! 目标是让作者「自己搓动画、自己搓首界面」，而不必改引擎本体。
//! 脚本语法是 Rust 的一个安全子集（`fn` / `let` / `if` / `while` / `return`），
//! 由本模块自带的解释器执行，因此：
//!
//! * **零依赖**、可交叉编译、可在 wasm 里跑；
//! * **沙箱**：没有 IO、没有指针、没有 unsafe，跑不出剧本之外的东西；
//! * 与剧情 VM 共享变量表，`set("好感", 3.0)` 就是改剧情状态。
//!
//! 宿主提供三类能力：
//!
//! 1. 数学：`sin cos sqrt abs min max clamp lerp pow floor round`
//! 2. 弹簧与缓动：`spring(t, response, damping)`、`ease(t)`、`ease_out(t)`、`bump(t, px)`
//! 3. 演出：`set(name, value)`、`emit(channel, value)`
//!
//! # 例子
//!
//! ```rust,ignore
//! // scripts/intro.rs —— 标题进场：0..1 秒内从下方弹入
//! fn title_entry(t) {
//!     let p = clamp(t / 0.45, 0.0, 1.0);
//!     let s = spring(p, 0.25, 0.45);      // 和 UI 同一个弹簧
//!     return (1.0 - s) * 120.0;           // 返回 Y 偏移
//! }
//!
//! fn title_fade(t) {
//!     return ease_out(clamp(t / 0.3, 0.0, 1.0));
//! }
//! ```

use crate::json::Json;
use std::collections::BTreeMap;

// ---------------------------------------------------------------- 词法

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Num(f64),
    Str(String),
    Ident(String),
    Sym(String),
    Eof,
}

fn lex(src: &str) -> Result<Vec<Tok>, String> {
    let cs: Vec<char> = src.chars().collect();
    let mut i = 0;
    let mut out = Vec::new();
    while i < cs.len() {
        let c = cs[i];
        if c.is_whitespace() {
            i += 1;
            continue;
        }
        // 注释
        if c == '/' && i + 1 < cs.len() && cs[i + 1] == '/' {
            while i < cs.len() && cs[i] != '\n' {
                i += 1;
            }
            continue;
        }
        if c.is_ascii_digit() || (c == '.' && i + 1 < cs.len() && cs[i + 1].is_ascii_digit()) {
            let start = i;
            while i < cs.len() && (cs[i].is_ascii_digit() || cs[i] == '.') {
                i += 1;
            }
            let s: String = cs[start..i].iter().collect();
            out.push(Tok::Num(s.parse().map_err(|_| format!("非法数字：{}", s))?));
            continue;
        }
        if c == '_' || c.is_alphanumeric() {
            let start = i;
            while i < cs.len() && (cs[i] == '_' || cs[i].is_alphanumeric()) {
                i += 1;
            }
            out.push(Tok::Ident(cs[start..i].iter().collect()));
            continue;
        }
        if c == '"' || c == '「' {
            let close = if c == '「' { '」' } else { c };
            i += 1;
            let mut s = String::new();
            let mut closed = false;
            while i < cs.len() {
                if cs[i] == '\\' && i + 1 < cs.len() {
                    s.push(match cs[i + 1] {
                        'n' => '\n',
                        't' => '\t',
                        o => o,
                    });
                    i += 2;
                } else if cs[i] == close {
                    i += 1;
                    closed = true;
                    break;
                } else {
                    s.push(cs[i]);
                    i += 1;
                }
            }
            if !closed {
                return Err("字符串没有闭合".into());
            }
            out.push(Tok::Str(s));
            continue;
        }
        let two: String = cs[i..(i + 2).min(cs.len())].iter().collect();
        if ["==", "!=", "<=", ">=", "&&", "||", "->", "+=", "-="].contains(&two.as_str()) {
            out.push(Tok::Sym(two));
            i += 2;
            continue;
        }
        if "+-*/%<>!=(){},;:".contains(c) {
            out.push(Tok::Sym(c.to_string()));
            i += 1;
            continue;
        }
        return Err(format!("不认识的字符：{}", c));
    }
    out.push(Tok::Eof);
    Ok(out)
}

// ---------------------------------------------------------------- 语法树

#[derive(Debug, Clone)]
pub enum Expr {
    Num(f64),
    Str(String),
    Bool(bool),
    Var(String),
    Call(String, Vec<Expr>),
    Unary(String, Box<Expr>),
    Bin(String, Box<Expr>, Box<Expr>),
}

#[derive(Debug, Clone)]
pub enum Stmt {
    Let(String, Expr),
    Assign(String, Expr),
    If(Expr, Vec<Stmt>, Vec<Stmt>),
    While(Expr, Vec<Stmt>),
    Return(Option<Expr>),
    Expr(Expr),
}

#[derive(Debug, Clone)]
pub struct Function {
    pub name: String,
    pub params: Vec<String>,
    pub body: Vec<Stmt>,
}

#[derive(Debug, Clone, Default)]
pub struct Program {
    pub functions: Vec<Function>,
}

impl Program {
    pub fn function(&self, name: &str) -> Option<&Function> {
        self.functions.iter().find(|f| f.name == name)
    }
}

// ---------------------------------------------------------------- 解析

struct Parser {
    t: Vec<Tok>,
    i: usize,
}

pub fn parse(src: &str) -> Result<Program, String> {
    let toks = lex(src)?;
    let mut p = Parser { t: toks, i: 0 };
    let mut prog = Program::default();
    loop {
        p.skip_semis();
        match p.peek().clone() {
            Tok::Eof => break,
            Tok::Ident(k) if k == "fn" => {
                prog.functions.push(p.function()?);
            }
            other => return Err(format!("顶层只允许 `fn` 定义，遇到 {:?}", other)),
        }
    }
    Ok(prog)
}

impl Parser {
    fn peek(&self) -> &Tok {
        self.t.get(self.i).unwrap_or(&Tok::Eof)
    }
    fn bump(&mut self) -> Tok {
        let t = self.t.get(self.i).cloned().unwrap_or(Tok::Eof);
        self.i += 1;
        t
    }
    fn eat(&mut self, sym: &str) -> bool {
        if let Tok::Sym(s) = self.peek() {
            if s == sym {
                self.i += 1;
                return true;
            }
        }
        false
    }
    fn expect(&mut self, sym: &str) -> Result<(), String> {
        if self.eat(sym) {
            Ok(())
        } else {
            Err(format!("期望 `{}`，实际 {:?}", sym, self.peek()))
        }
    }
    fn skip_semis(&mut self) {
        while self.eat(";") {}
    }
    fn ident(&mut self) -> Result<String, String> {
        match self.bump() {
            Tok::Ident(s) => Ok(s),
            other => Err(format!("期望标识符，实际 {:?}", other)),
        }
    }

    fn function(&mut self) -> Result<Function, String> {
        match self.bump() {
            Tok::Ident(k) if k == "fn" => {}
            other => return Err(format!("期望 `fn`，实际 {:?}", other)),
        }
        let name = self.ident()?;
        self.expect("(")?;
        let mut params = Vec::new();
        if !self.eat(")") {
            loop {
                params.push(self.ident()?);
                if self.eat(")") {
                    break;
                }
                self.expect(",")?;
            }
        }
        // 可选返回类型标注： -> Num
        if self.eat("->") {
            let _ = self.ident();
        }
        let body = self.block()?;
        Ok(Function {
            name,
            params,
            body,
        })
    }

    fn block(&mut self) -> Result<Vec<Stmt>, String> {
        self.expect("{")?;
        let mut out = Vec::new();
        loop {
            self.skip_semis();
            if self.eat("}") {
                break;
            }
            if matches!(self.peek(), Tok::Eof) {
                return Err("代码块没有闭合".into());
            }
            out.push(self.stmt()?);
        }
        Ok(out)
    }

    fn stmt(&mut self) -> Result<Stmt, String> {
        match self.peek().clone() {
            Tok::Ident(k) if k == "let" => {
                self.bump();
                let name = self.ident()?;
                self.expect("=")?;
                let e = self.expr()?;
                self.eat(";");
                Ok(Stmt::Let(name, e))
            }
            Tok::Ident(k) if k == "if" => {
                self.bump();
                let cond = self.expr()?;
                let then = self.block()?;
                let mut els = Vec::new();
                if let Tok::Ident(k2) = self.peek().clone() {
                    if k2 == "else" {
                        self.bump();
                        if let Tok::Ident(k3) = self.peek().clone() {
                            if k3 == "if" {
                                els.push(self.stmt()?);
                            } else {
                                els = self.block()?;
                            }
                        } else {
                            els = self.block()?;
                        }
                    }
                }
                Ok(Stmt::If(cond, then, els))
            }
            Tok::Ident(k) if k == "while" => {
                self.bump();
                let cond = self.expr()?;
                let body = self.block()?;
                Ok(Stmt::While(cond, body))
            }
            Tok::Ident(k) if k == "return" => {
                self.bump();
                self.eat(";");
                if matches!(self.peek(), Tok::Sym(s) if s == "}" || s == ";") {
                    self.skip_semis();
                    return Ok(Stmt::Return(None));
                }
                let e = self.expr()?;
                self.eat(";");
                Ok(Stmt::Return(Some(e)))
            }
            // 标识符后跟 = 视为赋值
            Tok::Ident(name) => {
                if let Some(Tok::Sym(s)) = self.t.get(self.i + 1) {
                    if s == "=" {
                        self.i += 2;
                        let e = self.expr()?;
                        self.eat(";");
                        return Ok(Stmt::Assign(name, e));
                    }
                    if s == "+=" || s == "-=" {
                        let op = if s == "+=" { "+" } else { "-" };
                        self.i += 2;
                        let rhs = self.expr()?;
                        self.eat(";");
                        return Ok(Stmt::Assign(
                            name.clone(),
                            Expr::Bin(
                                op.to_string(),
                                Box::new(Expr::Var(name)),
                                Box::new(rhs),
                            ),
                        ));
                    }
                }
                let e = self.expr()?;
                self.eat(";");
                Ok(Stmt::Expr(e))
            }
            _ => {
                let e = self.expr()?;
                self.eat(";");
                Ok(Stmt::Expr(e))
            }
        }
    }

    fn expr(&mut self) -> Result<Expr, String> {
        self.bin(0)
    }

    fn prec(op: &str) -> Option<u8> {
        Some(match op {
            "||" => 1,
            "&&" => 2,
            "==" | "!=" | "<" | "<=" | ">" | ">=" => 3,
            "+" | "-" => 4,
            "*" | "/" | "%" => 5,
            _ => return None,
        })
    }

    fn bin(&mut self, min: u8) -> Result<Expr, String> {
        let mut lhs = self.unary()?;
        loop {
            let op = match self.peek() {
                Tok::Sym(s) => match Self::prec(s) {
                    Some(_) => s.clone(),
                    None => break,
                },
                _ => break,
            };
            let p = Self::prec(&op).unwrap();
            if p < min {
                break;
            }
            self.i += 1;
            let rhs = self.bin(p + 1)?;
            lhs = Expr::Bin(op, Box::new(lhs), Box::new(rhs));
        }
        Ok(lhs)
    }

    fn unary(&mut self) -> Result<Expr, String> {
        if let Tok::Sym(s) = self.peek().clone() {
            if s == "!" || s == "-" {
                self.i += 1;
                let inner = self.unary()?;
                return Ok(Expr::Unary(s, Box::new(inner)));
            }
        }
        self.atom()
    }

    fn atom(&mut self) -> Result<Expr, String> {
        match self.bump() {
            Tok::Num(n) => Ok(Expr::Num(n)),
            Tok::Str(s) => Ok(Expr::Str(s)),
            Tok::Ident(name) => {
                if self.eat("(") {
                    let mut args = Vec::new();
                    if !self.eat(")") {
                        loop {
                            args.push(self.expr()?);
                            if self.eat(")") {
                                break;
                            }
                            self.expect(",")?;
                        }
                    }
                    return Ok(Expr::Call(name, args));
                }
                Ok(match name.as_str() {
                    "true" => Expr::Bool(true),
                    "false" => Expr::Bool(false),
                    _ => Expr::Var(name),
                })
            }
            Tok::Sym(s) if s == "(" => {
                let e = self.expr()?;
                self.expect(")")?;
                Ok(e)
            }
            other => Err(format!("这里不该出现 {:?}", other)),
        }
    }
}

// ---------------------------------------------------------------- 值

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Num(f64),
    Str(String),
    Bool(bool),
    Null,
}

impl Value {
    pub fn truthy(&self) -> bool {
        match self {
            Value::Num(n) => *n != 0.0,
            Value::Str(s) => !s.is_empty(),
            Value::Bool(b) => *b,
            Value::Null => false,
        }
    }
    pub fn num(&self) -> f64 {
        match self {
            Value::Num(n) => *n,
            Value::Bool(b) => {
                if *b {
                    1.0
                } else {
                    0.0
                }
            }
            Value::Str(s) => s.trim().parse().unwrap_or(0.0),
            Value::Null => 0.0,
        }
    }
    pub fn to_json(&self) -> Json {
        match self {
            Value::Num(n) => Json::Num(*n),
            Value::Str(s) => Json::Str(s.clone()),
            Value::Bool(b) => Json::Bool(*b),
            Value::Null => Json::Null,
        }
    }
    pub fn from_json(j: &Json) -> Value {
        match j {
            Json::Num(n) => Value::Num(*n),
            Json::Str(s) => Value::Str(s.clone()),
            Json::Bool(b) => Value::Bool(*b),
            _ => Value::Null,
        }
    }
}

/// 脚本执行的结果
#[derive(Debug, Clone, Default)]
pub struct ScriptResult {
    /// 脚本里 `set(name, v)` 写入的变量
    pub vars: BTreeMap<String, Value>,
    /// 脚本里 `emit(channel, v)` 抛出的演出指令（channel → 值）
    pub emits: BTreeMap<String, Value>,
    /// 函数返回值
    pub ret: Option<Value>,
    /// 执行了多少条语句（护栏用）
    pub steps: u32,
}

/// 一次调用的上下文
pub struct Host<'a> {
    /// 读取外部变量（剧情 VM 的变量表）
    pub get: &'a dyn Fn(&str) -> Value,
    pub vars: BTreeMap<String, Value>,
    pub emits: BTreeMap<String, Value>,
    steps: u32,
    depth: u32,
}

const MAX_STEPS: u32 = 200_000;
const MAX_DEPTH: u32 = 32;

impl<'a> Host<'a> {
    pub fn new(get: &'a dyn Fn(&str) -> Value) -> Self {
        Host {
            get,
            vars: BTreeMap::new(),
            emits: BTreeMap::new(),
            steps: 0,
            depth: 0,
        }
    }
}

// ---------------------------------------------------------------- 求值

fn call_builtin(
    host: &mut Host,
    name: &str,
    args: Vec<Value>,
) -> Result<Option<Value>, String> {
    let a = |i: usize| args.get(i).map(|v| v.num()).unwrap_or(0.0);
    let s = |i: usize| -> String {
        match args.get(i) {
            Some(Value::Str(x)) => x.clone(),
            Some(v) => format!("{}", v.num()),
            None => String::new(),
        }
    };
    let ret = match name {
        // ---- 数学
        "sin" => Some(Value::Num(a(0).sin())),
        "cos" => Some(Value::Num(a(0).cos())),
        "sqrt" => Some(Value::Num(a(0).max(0.0).sqrt())),
        "abs" => Some(Value::Num(a(0).abs())),
        "floor" => Some(Value::Num(a(0).floor())),
        "round" => Some(Value::Num(a(0).round())),
        "pow" => Some(Value::Num(a(0).powf(a(1)))),
        "min" => Some(Value::Num(a(0).min(a(1)))),
        "max" => Some(Value::Num(a(0).max(a(1)))),
        "clamp" => Some(Value::Num(a(0).max(a(1)).min(a(2)))),
        "lerp" => Some(Value::Num(a(0) + (a(1) - a(0)) * a(2))),
        "random" => {
            // 确定性伪随机：脚本里要可复现
            let seed = a(0) * 12.9898 + a(1) * 78.233;
            let v = (seed.sin() * 43758.5453).fract().abs();
            Some(Value::Num(v))
        }
        // ---- 弹簧（与 UI 同一套参数：Response / Damping）
        "spring" => {
            // spring(p, response, damping)：把 0..1 的进度 p 走一段阻尼弹簧积分
            let p = a(0).clamp(0.0, 1.0);
            let response = if a(1) > 0.0 { a(1) } else { 0.29 };
            let damping = if a(2) >= 0.0 { a(2) } else { 0.75 };
            Some(Value::Num(spring_sample(p, response, damping)))
        }
        // ---- 缓动
        "ease" => {
            let t = a(0).clamp(0.0, 1.0);
            Some(Value::Num(1.0 - (-t * 4.0).exp()))
        }
        "ease_out" => {
            let t = a(0).clamp(0.0, 1.0);
            Some(Value::Num(1.0 - (1.0 - t) * (1.0 - t)))
        }
        "bump" => {
            // bump(t, amplitude)：一次衰减震荡
            let t = a(0);
            Some(Value::Num(a(1) * (-t * 5.0).exp() * (t * 18.0).sin()))
        }
        // ---- 演出
        "set" => {
            host.vars.insert(s(0), args.get(1).cloned().unwrap_or(Value::Null));
            Some(Value::Null)
        }
        "emit" => {
            host.emits
                .insert(s(0), args.get(1).cloned().unwrap_or(Value::Null));
            Some(Value::Null)
        }
        "get" => Some(
            host.vars
                .get(&s(0))
                .cloned()
                .unwrap_or_else(|| (host.get)(&s(0))),
        ),
        "print" => {
            // 解释器里只当作 emit("log", ...)
            host.emits
                .insert("log".to_string(), Value::Str(args.iter().map(|v| match v {
                    Value::Str(x) => x.clone(),
                    v => format!("{}", v.num()),
                }).collect::<Vec<_>>().join(" ")));
            Some(Value::Null)
        }
        _ => return Ok(None), // 不是内置函数，交给用户函数
    };
    Ok(ret)
}

/// 把 0..1 的进度用阻尼弹簧积分采样（与 UI 里的 Spring 同参数）
pub fn spring_sample(progress: f64, response: f64, damping: f64) -> f64 {
    let duration = response * 2.6; // 大约走完的时间
    let t_end = progress * duration;
    let (mut x, mut v) = (0.0f64, 0.0f64);
    let h = 1.0 / 240.0;
    let mut t = 0.0;
    let w = std::f64::consts::PI * 2.0 / response;
    let k = w * w;
    let c = 2.0 * damping * w;
    while t < t_end {
        let f = k * (1.0 - x) - c * v;
        v += f * h;
        x += v * h;
        t += h;
    }
    x
}

fn eval_expr(
    prog: &Program,
    host: &mut Host,
    locals: &mut BTreeMap<String, Value>,
    e: &Expr,
) -> Result<Value, String> {
    Ok(match e {
        Expr::Num(n) => Value::Num(*n),
        Expr::Str(s) => Value::Str(s.clone()),
        Expr::Bool(b) => Value::Bool(*b),
        Expr::Var(name) => locals
            .get(name)
            .cloned()
            .or_else(|| host.vars.get(name).cloned())
            .unwrap_or_else(|| (host.get)(name)),
        Expr::Unary(op, inner) => {
            let v = eval_expr(prog, host, locals, inner)?;
            match op.as_str() {
                "!" => Value::Bool(!v.truthy()),
                _ => Value::Num(-v.num()),
            }
        }
        Expr::Bin(op, l, r) => {
            // 短路
            if op == "&&" {
                if !eval_expr(prog, host, locals, l)?.truthy() {
                    return Ok(Value::Bool(false));
                }
                return Ok(Value::Bool(eval_expr(prog, host, locals, r)?.truthy()));
            }
            if op == "||" {
                if eval_expr(prog, host, locals, l)?.truthy() {
                    return Ok(Value::Bool(true));
                }
                return Ok(Value::Bool(eval_expr(prog, host, locals, r)?.truthy()));
            }
            let a = eval_expr(prog, host, locals, l)?;
            let b = eval_expr(prog, host, locals, r)?;
            match op.as_str() {
                "+" => match (&a, &b) {
                    (Value::Str(_), _) | (_, Value::Str(_)) => Value::Str(format!(
                        "{}{}",
                        match &a {
                            Value::Str(s) => s.clone(),
                            v => fmt_num(v.num()),
                        },
                        match &b {
                            Value::Str(s) => s.clone(),
                            v => fmt_num(v.num()),
                        }
                    )),
                    _ => Value::Num(a.num() + b.num()),
                },
                "-" => Value::Num(a.num() - b.num()),
                "*" => Value::Num(a.num() * b.num()),
                "/" => {
                    let d = b.num();
                    Value::Num(if d == 0.0 { 0.0 } else { a.num() / d })
                }
                "%" => {
                    let d = b.num();
                    Value::Num(if d == 0.0 { 0.0 } else { a.num() % d })
                }
                "==" => Value::Bool(eq(&a, &b)),
                "!=" => Value::Bool(!eq(&a, &b)),
                "<" => Value::Bool(a.num() < b.num()),
                "<=" => Value::Bool(a.num() <= b.num()),
                ">" => Value::Bool(a.num() > b.num()),
                ">=" => Value::Bool(a.num() >= b.num()),
                _ => Value::Null,
            }
        }
        Expr::Call(name, args) => {
            let mut vals = Vec::with_capacity(args.len());
            for a in args {
                vals.push(eval_expr(prog, host, locals, a)?);
            }
            if let Some(v) = call_builtin(host, name, vals.clone())? {
                v
            } else if let Some(f) = prog.function(name) {
                call_function(prog, host, f, vals)?
            } else {
                return Err(format!("没有这个函数：{}", name));
            }
        }
    })
}

fn fmt_num(n: f64) -> String {
    if n.fract() == 0.0 && n.abs() < 1e15 {
        format!("{}", n as i64)
    } else {
        format!("{}", n)
    }
}

fn eq(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Str(x), Value::Str(y)) => x == y,
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Null, Value::Null) => true,
        _ => (a.num() - b.num()).abs() < 1e-9,
    }
}

fn call_function(
    prog: &Program,
    host: &mut Host,
    f: &Function,
    args: Vec<Value>,
) -> Result<Value, String> {
    if host.depth >= MAX_DEPTH {
        return Err(format!("调用层级太深（{} 层），是不是递归了？", MAX_DEPTH));
    }
    host.depth += 1;
    let mut locals = BTreeMap::new();
    for (i, p) in f.params.iter().enumerate() {
        locals.insert(p.clone(), args.get(i).cloned().unwrap_or(Value::Null));
    }
    let mut ret = Value::Null;
    exec_block(prog, host, &mut locals, &f.body, &mut ret)?;
    host.depth -= 1;
    Ok(ret)
}

fn exec_block(
    prog: &Program,
    host: &mut Host,
    locals: &mut BTreeMap<String, Value>,
    body: &[Stmt],
    ret: &mut Value,
) -> Result<bool, String> {
    for s in body {
        if exec_stmt(prog, host, locals, s, ret)? {
            return Ok(true); // 已 return
        }
    }
    Ok(false)
}

fn exec_stmt(
    prog: &Program,
    host: &mut Host,
    locals: &mut BTreeMap<String, Value>,
    s: &Stmt,
    ret: &mut Value,
) -> Result<bool, String> {
    host.steps += 1;
    if host.steps > MAX_STEPS {
        return Err("脚本执行步数超限（死循环？）".into());
    }
    match s {
        Stmt::Let(name, e) => {
            let v = eval_expr(prog, host, locals, e)?;
            locals.insert(name.clone(), v);
            Ok(false)
        }
        Stmt::Assign(name, e) => {
            let v = eval_expr(prog, host, locals, e)?;
            if locals.contains_key(name) {
                locals.insert(name.clone(), v);
            } else if host.vars.contains_key(name) {
                host.vars.insert(name.clone(), v);
            } else {
                locals.insert(name.clone(), v);
            }
            Ok(false)
        }
        Stmt::If(cond, then, els) => {
            if eval_expr(prog, host, locals, cond)?.truthy() {
                exec_block(prog, host, locals, then, ret)
            } else {
                exec_block(prog, host, locals, els, ret)
            }
        }
        Stmt::While(cond, body) => {
            loop {
                if !eval_expr(prog, host, locals, cond)?.truthy() {
                    break;
                }
                if exec_block(prog, host, locals, body, ret)? {
                    return Ok(true);
                }
                host.steps += 1;
                if host.steps > MAX_STEPS {
                    return Err("while 循环步数超限（死循环？）".into());
                }
            }
            Ok(false)
        }
        Stmt::Return(e) => {
            *ret = match e {
                Some(e) => eval_expr(prog, host, locals, e)?,
                None => Value::Null,
            };
            Ok(true)
        }
        Stmt::Expr(e) => {
            eval_expr(prog, host, locals, e)?;
            Ok(false)
        }
    }
}

// ---------------------------------------------------------------- 对外接口

/// 一个已编译的脚本（加载一次，反复调用）
#[derive(Debug, Clone)]
pub struct Script {
    pub name: String,
    pub program: Program,
}

impl Script {
    pub fn compile(name: &str, src: &str) -> Result<Script, String> {
        Ok(Script {
            name: name.to_string(),
            program: parse(src)?,
        })
    }

    pub fn from_file(path: &std::path::Path) -> Result<Script, String> {
        let src = std::fs::read_to_string(path)
            .map_err(|e| format!("读不到脚本 {}：{}", path.display(), e))?;
        Script::compile(&path.display().to_string(), &src)
    }

    pub fn has(&self, entry: &str) -> bool {
        self.program.function(entry).is_some()
    }

    /// 调用脚本里的一个函数。
    /// `get` 用来读剧情变量；`args` 是传入的参数（例如进度 t）。
    pub fn call(
        &self,
        entry: &str,
        args: Vec<Value>,
        get: &dyn Fn(&str) -> Value,
    ) -> Result<ScriptResult, String> {
        let f = self
            .program
            .function(entry)
            .ok_or_else(|| format!("脚本 {} 里没有函数 {}", self.name, entry))?
            .clone();
        let mut host = Host::new(get);
        let ret = call_function(&self.program, &mut host, &f, args)?;
        Ok(ScriptResult {
            vars: host.vars,
            emits: host.emits,
            ret: Some(ret),
            steps: host.steps,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn no_vars(_: &str) -> Value {
        Value::Null
    }

    #[test]
    fn arithmetic_and_return() {
        let s = Script::compile("t.rs", "fn f(a, b) { let c = a * 2; return c + b; }").unwrap();
        let r = s.call("f", vec![Value::Num(3.0), Value::Num(4.0)], &no_vars).unwrap();
        assert_eq!(r.ret.unwrap().num(), 10.0);
    }

    #[test]
    fn if_else_while() {
        let src = r#"
            fn acc(n) {
                let s = 0;
                let i = 1;
                while i <= n {
                    if i % 2 == 0 {
                        s = s + i;
                    } else {
                        s = s + 0;
                    }
                    i = i + 1;
                }
                return s;
            }
        "#;
        let s = Script::compile("t.rs", src).unwrap();
        // 2 + 4 = 6
        assert_eq!(s.call("acc", vec![Value::Num(5.0)], &no_vars).unwrap().ret.unwrap().num(), 6.0);
    }

    #[test]
    fn springs_and_easing() {
        let s = Script::compile(
            "t.rs",
            "fn f(t) { return spring(t, 0.25, 0.45); } fn g(t) { return ease_out(t); }",
        )
        .unwrap();
        let mid = s.call("f", vec![Value::Num(0.5)], &no_vars).unwrap().ret.unwrap().num();
        assert!(mid > 0.0 && mid < 2.0, "弹簧采样应在合理范围，实际 {}", mid);
        let e = s.call("g", vec![Value::Num(1.0)], &no_vars).unwrap().ret.unwrap().num();
        assert!((e - 1.0).abs() < 1e-6);
    }

    #[test]
    fn set_and_emit() {
        let src = r#"
            fn intro(t) {
                let p = clamp(t / 0.4, 0.0, 1.0);
                set("好感", 3);
                emit("titleY", (1.0 - p) * 120.0);
                return p;
            }
        "#;
        let s = Script::compile("t.rs", src).unwrap();
        let r = s.call("intro", vec![Value::Num(0.2)], &no_vars).unwrap();
        assert_eq!(r.vars.get("好感").unwrap().num(), 3.0);
        assert!((r.emits.get("titleY").unwrap().num() - 60.0).abs() < 1e-6);
    }

    #[test]
    fn reads_story_vars() {
        let s = Script::compile("t.rs", "fn f() { return get(\"好感\") * 10.0; }").unwrap();
        let get = |n: &str| {
            if n == "好感" {
                Value::Num(4.0)
            } else {
                Value::Null
            }
        };
        assert_eq!(s.call("f", vec![], &get).unwrap().ret.unwrap().num(), 40.0);
    }

    #[test]
    fn guards() {
        let s = Script::compile("t.rs", "fn f() { while true { } }").unwrap();
        assert!(s.call("f", vec![], &no_vars).is_err());
        let s2 = Script::compile("t.rs", "fn f() { return g(); } fn g() { return f(); }").unwrap();
        assert!(s2.call("f", vec![], &no_vars).is_err());
        assert!(Script::compile("t.rs", "fn f( { }").is_err());
    }

    #[test]
    fn recursive_factorial() {
        let src = r#"
            fn fac(n) {
                if n <= 1 { return 1; }
                return n * fac(n - 1);
            }
        "#;
        let s = Script::compile("t.rs", src).unwrap();
        assert_eq!(s.call("fac", vec![Value::Num(5.0)], &no_vars).unwrap().ret.unwrap().num(), 120.0);
    }
}