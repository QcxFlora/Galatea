//! 剧情条件/效果用的小表达式语言。
//!
//! 语法（优先级从低到高）：
//!   `||` → `&&` → `== != < <= > >=` → `+ -` → `* / %` → `! -`（一元）→ 原子
//! 原子：数字、'字符串' 或 "字符串"、变量名（支持中文）、true/false/null、括号。
//!
//! 例：`aff >= 3 && met_yuki == true`、`"雪" + "的" + 名字`、`flags.seen`

use crate::json::Json;

#[derive(Debug, Clone, PartialEq)]
pub enum Expr {
    Lit(Json),
    Var(String),
    Not(Box<Expr>),
    Neg(Box<Expr>),
    Bin(&'static str, Box<Expr>, Box<Expr>),
}

impl Expr {
    /// 求值。`get` 负责从变量表取值（未定义变量应返回 Json::Null）。
    pub fn eval(&self, get: &dyn Fn(&str) -> Json) -> Json {
        match self {
            Expr::Lit(v) => v.clone(),
            Expr::Var(name) => get(name),
            Expr::Not(e) => Json::Bool(!e.eval(get).truthy()),
            Expr::Neg(e) => Json::Num(-to_num(&e.eval(get))),
            Expr::Bin(op, l, r) => match *op {
                "&&" => {
                    if !l.eval(get).truthy() {
                        Json::Bool(false)
                    } else {
                        Json::Bool(r.eval(get).truthy())
                    }
                }
                "||" => {
                    if l.eval(get).truthy() {
                        Json::Bool(true)
                    } else {
                        Json::Bool(r.eval(get).truthy())
                    }
                }
                "==" => Json::Bool(loose_eq(&l.eval(get), &r.eval(get))),
                "!=" => Json::Bool(!loose_eq(&l.eval(get), &r.eval(get))),
                "+" => {
                    let (a, b) = (l.eval(get), r.eval(get));
                    match (&a, &b) {
                        (Json::Str(_), _) | (_, Json::Str(_)) => {
                            Json::Str(format!("{}{}", a.as_display(), b.as_display()))
                        }
                        _ => Json::Num(to_num(&a) + to_num(&b)),
                    }
                }
                "-" => Json::Num(to_num(&l.eval(get)) - to_num(&r.eval(get))),
                "*" => Json::Num(to_num(&l.eval(get)) * to_num(&r.eval(get))),
                "/" => {
                    let d = to_num(&r.eval(get));
                    if d == 0.0 {
                        Json::Num(0.0)
                    } else {
                        Json::Num(to_num(&l.eval(get)) / d)
                    }
                }
                "%" => {
                    let d = to_num(&r.eval(get));
                    if d == 0.0 {
                        Json::Num(0.0)
                    } else {
                        Json::Num(to_num(&l.eval(get)) % d)
                    }
                }
                "<" => Json::Bool(compare(&l.eval(get), &r.eval(get)).map(|o| o < 0).unwrap_or(false)),
                "<=" => Json::Bool(compare(&l.eval(get), &r.eval(get)).map(|o| o <= 0).unwrap_or(false)),
                ">" => Json::Bool(compare(&l.eval(get), &r.eval(get)).map(|o| o > 0).unwrap_or(false)),
                ">=" => Json::Bool(compare(&l.eval(get), &r.eval(get)).map(|o| o >= 0).unwrap_or(false)),
                _ => Json::Null,
            },
        }
    }

    /// 收集表达式里引用到的变量名（给校验器做"未定义变量"警告用）
    pub fn vars(&self, out: &mut Vec<String>) {
        match self {
            Expr::Lit(_) => {}
            Expr::Var(n) => out.push(n.clone()),
            Expr::Not(e) | Expr::Neg(e) => e.vars(out),
            Expr::Bin(_, a, b) => {
                a.vars(out);
                b.vars(out);
            }
        }
    }

    /// 是否是常量（编译期可折叠，给自动布局/预览用）
    pub fn is_const(&self) -> bool {
        match self {
            Expr::Lit(_) => true,
            Expr::Var(_) => false,
            Expr::Not(e) | Expr::Neg(e) => e.is_const(),
            Expr::Bin(_, a, b) => a.is_const() && b.is_const(),
        }
    }

    /// 把表达式还原成字符串（用于把节点导出回 JSON）
    pub fn to_src(&self) -> String {
        match self {
            Expr::Lit(Json::Str(s)) => format!("\"{}\"", s.replace('"', "\\\"")),
            Expr::Lit(v) => v.as_display(),
            Expr::Var(n) => n.clone(),
            Expr::Not(e) => format!("!{}", paren_if_bin(e)),
            Expr::Neg(e) => format!("-{}", paren_if_bin(e)),
            Expr::Bin(op, a, b) => format!("{} {} {}", paren_if_bin(a), op, paren_if_bin(b)),
        }
    }
}

fn paren_if_bin(e: &Expr) -> String {
    match e {
        Expr::Bin(..) => format!("({})", e.to_src()),
        _ => e.to_src(),
    }
}

pub fn to_num(v: &Json) -> f64 {
    match v {
        Json::Num(n) => *n,
        Json::Bool(b) => {
            if *b {
                1.0
            } else {
                0.0
            }
        }
        Json::Str(s) => s.trim().parse::<f64>().unwrap_or(0.0),
        _ => 0.0,
    }
}

fn loose_eq(a: &Json, b: &Json) -> bool {
    match (a, b) {
        (Json::Null, Json::Null) => true,
        (Json::Str(x), Json::Str(y)) => x == y,
        (Json::Bool(x), Json::Bool(y)) => x == y,
        (Json::Num(x), Json::Num(y)) => (*x - *y).abs() < 1e-9,
        (Json::Null, _) | (_, Json::Null) => false,
        _ => false,
    }
}

fn compare(a: &Json, b: &Json) -> Option<i32> {
    match (a, b) {
        (Json::Num(x), Json::Num(y)) => Some(if x < y { -1 } else if x > y { 1 } else { 0 }),
        (Json::Str(x), Json::Str(y)) => Some(match x.cmp(y) {
            std::cmp::Ordering::Less => -1,
            std::cmp::Ordering::Equal => 0,
            std::cmp::Ordering::Greater => 1,
        }),
        _ => {
            let (x, y) = (to_num(a), to_num(b));
            Some(if x < y { -1 } else if x > y { 1 } else { 0 })
        }
    }
}

// ---------------------------------------------------------------- tokenizer

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Num(f64),
    Str(String),
    Ident(String),
    Sym(String),
}

fn tokenize(src: &str) -> Result<Vec<Tok>, String> {
    let cs: Vec<char> = src.chars().collect();
    let mut i = 0;
    let mut out = Vec::new();
    while i < cs.len() {
        let c = cs[i];
        if c.is_whitespace() {
            i += 1;
            continue;
        }
        if c.is_ascii_digit() || (c == '.' && i + 1 < cs.len() && cs[i + 1].is_ascii_digit()) {
            let start = i;
            while i < cs.len() && (cs[i].is_ascii_digit() || cs[i] == '.') {
                i += 1;
            }
            let s: String = cs[start..i].iter().collect();
            out.push(Tok::Num(s.parse::<f64>().map_err(|_| format!("非法数字：{}", s))?));
            continue;
        }
        if c == '"' || c == '\'' || c == '「' {
            let quote = c;
            let close = if quote == '「' { '」' } else { quote };
            i += 1;
            let mut s = String::new();
            let mut closed = false;
            while i < cs.len() {
                if cs[i] == '\\' && i + 1 < cs.len() {
                    let e = cs[i + 1];
                    s.push(match e {
                        'n' => '\n',
                        't' => '\t',
                        other => other,
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
                return Err("字符串没有闭合".to_string());
            }
            out.push(Tok::Str(s));
            continue;
        }
        if c.is_alphanumeric() || c == '_' {
            let start = i;
            while i < cs.len() && (cs[i].is_alphanumeric() || cs[i] == '_' || cs[i] == '.') {
                i += 1;
            }
            out.push(Tok::Ident(cs[start..i].iter().collect()));
            continue;
        }
        // 符号
        let two: String = cs[i..(i + 2).min(cs.len())].iter().collect();
        if ["&&", "||", "==", "!=", "<=", ">="].contains(&two.as_str()) {
            out.push(Tok::Sym(two));
            i += 2;
            continue;
        }
        if "<>+-*/%!()".contains(c) {
            out.push(Tok::Sym(c.to_string()));
            i += 1;
            continue;
        }
        return Err(format!("不认识的字符：{}", c));
    }
    Ok(out)
}

// ---------------------------------------------------------------- parser

struct E<'a> {
    t: &'a [Tok],
    i: usize,
}

fn prec(sym: &str) -> Option<u8> {
    Some(match sym {
        "||" => 1,
        "&&" => 2,
        "==" | "!=" | "<" | "<=" | ">" | ">=" => 3,
        "+" | "-" => 4,
        "*" | "/" | "%" => 5,
        _ => return None,
    })
}

impl<'a> E<'a> {
    fn peek(&self) -> Option<&Tok> {
        self.t.get(self.i)
    }

    fn expr(&mut self, min_prec: u8) -> Result<Expr, String> {
        let mut lhs = self.unary()?;
        loop {
            let (op, p) = match self.peek() {
                Some(Tok::Sym(s)) => match prec(s) {
                    Some(p) => (s.clone(), p),
                    None => break,
                },
                _ => break,
            };
            if p < min_prec {
                break;
            }
            self.i += 1;
            let rhs = self.expr(p + 1)?;
            // 把 &'static str 的映射做掉，避免 hover 生命周期问题
            let st: &'static str = match op.as_str() {
                "||" => "||",
                "&&" => "&&",
                "==" => "==",
                "!=" => "!=",
                "<" => "<",
                "<=" => "<=",
                ">" => ">",
                ">=" => ">=",
                "+" => "+",
                "-" => "-",
                "*" => "*",
                "/" => "/",
                _ => "%",
            };
            lhs = Expr::Bin(st, Box::new(lhs), Box::new(rhs));
        }
        Ok(lhs)
    }

    fn unary(&mut self) -> Result<Expr, String> {
        match self.peek() {
            Some(Tok::Sym(s)) if s == "!" => {
                self.i += 1;
                Ok(Expr::Not(Box::new(self.unary()?)))
            }
            Some(Tok::Sym(s)) if s == "-" => {
                self.i += 1;
                Ok(Expr::Neg(Box::new(self.unary()?)))
            }
            _ => self.atom(),
        }
    }

    fn atom(&mut self) -> Result<Expr, String> {
        let tok = self.peek().cloned().ok_or("表达式不完整")?;
        self.i += 1;
        match tok {
            Tok::Num(n) => Ok(Expr::Lit(Json::Num(n))),
            Tok::Str(s) => Ok(Expr::Lit(Json::Str(s))),
            Tok::Ident(name) => Ok(match name.as_str() {
                "true" | "真" => Expr::Lit(Json::Bool(true)),
                "false" | "假" => Expr::Lit(Json::Bool(false)),
                "null" | "none" | "nil" => Expr::Lit(Json::Null),
                _ => Expr::Var(name),
            }),
            Tok::Sym(s) if s == "(" => {
                let e = self.expr(0)?;
                match self.peek() {
                    Some(Tok::Sym(s)) if s == ")" => {
                        self.i += 1;
                        Ok(e)
                    }
                    _ => Err("缺少右括号".to_string()),
                }
            }
            Tok::Sym(s) => Err(format!("这里不该出现 '{}'", s)),
        }
    }
}

/// 解析表达式；空串视为"恒真"。
pub fn parse(src: &str) -> Result<Expr, String> {
    let src = src.trim();
    if src.is_empty() {
        return Ok(Expr::Lit(Json::Bool(true)));
    }
    let toks = tokenize(src)?;
    let mut p = E { t: &toks, i: 0 };
    let e = p.expr(0)?;
    if p.i != toks.len() {
        return Err(format!("表达式在 `{}` 之后有无法解析的内容", e.to_src()));
    }
    Ok(e)
}

/// 便捷：直接求值一个字符串表达式
pub fn eval_str(src: &str, get: &dyn Fn(&str) -> Json) -> Result<Json, String> {
    Ok(parse(src)?.eval(get))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env_get(name: &str) -> Json {
        match name {
            "aff" => Json::Num(5.0),
            "name" => Json::s("雪"),
            "flag" => Json::Bool(true),
            _ => Json::Null,
        }
    }

    #[test]
    fn arith_and_logic() {
        let e = parse("aff * 2 + 1 >= 11 && flag").unwrap();
        assert!(e.eval(&env_get).truthy());
        let e = parse("!(aff > 10) || 0").unwrap();
        assert!(e.eval(&env_get).truthy());
        let e = parse("!(aff < 10) || 0").unwrap();
        assert!(!e.eval(&env_get).truthy());
    }

    #[test]
    fn string_concat() {
        let e = parse("\"你好，\" + name").unwrap();
        assert_eq!(e.eval(&env_get), Json::s("你好，雪"));
    }

    #[test]
    fn chinese_and_prec() {
        let e = parse("aff + 1 * 2 == 7").unwrap();
        assert!(e.eval(&env_get).truthy());
        let e = parse("(aff + 1) * 2 == 12").unwrap();
        assert!(e.eval(&env_get).truthy());
    }

    #[test]
    fn bad_syntax() {
        assert!(parse("aff >").is_err());
        assert!(parse("(aff").is_err());
        assert!(parse("\"未闭合").is_err());
    }

    #[test]
    fn var_collect() {
        let mut v = Vec::new();
        parse("a == 1 && b.c > 2").unwrap().vars(&mut v);
        assert_eq!(v, vec!["a".to_string(), "b.c".to_string()]);
    }
}