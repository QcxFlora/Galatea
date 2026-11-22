//! 极小 JSON 实现（零依赖）。
//! 引擎需要读写剧本图、存档，格式固定且简单，因此自带一个 JSON 解析/序列化器，
//! 免去 serde 依赖，方便交叉编译到 Android / iOS / 桌面 / wasm。

use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(BTreeMap<String, Json>),
}

impl Json {
    pub fn obj() -> Self {
        Json::Obj(BTreeMap::new())
    }
    pub fn arr() -> Self {
        Json::Arr(Vec::new())
    }
    pub fn s<S: Into<String>>(v: S) -> Self {
        Json::Str(v.into())
    }
    pub fn n<N: Into<f64>>(v: N) -> Self {
        Json::Num(v.into())
    }
    pub fn b(v: bool) -> Self {
        Json::Bool(v)
    }

    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(m) => m.get(key),
            _ => None,
        }
    }
    pub fn has(&self, key: &str) -> bool {
        self.get(key).map(|v| !v.is_null()).unwrap_or(false)
    }
    pub fn at(&self, i: usize) -> Option<&Json> {
        match self {
            Json::Arr(a) => a.get(i),
            _ => None,
        }
    }
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Json::Num(n) => Some(*n),
            _ => None,
        }
    }
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Json::Bool(b) => Some(*b),
            _ => None,
        }
    }
    pub fn as_arr(&self) -> Option<&Vec<Json>> {
        match self {
            Json::Arr(a) => Some(a),
            _ => None,
        }
    }
    pub fn as_obj(&self) -> Option<&BTreeMap<String, Json>> {
        match self {
            Json::Obj(m) => Some(m),
            _ => None,
        }
    }
    pub fn is_null(&self) -> bool {
        matches!(self, Json::Null)
    }

    // ---- 便捷取值（带默认值）----
    pub fn s_or(&self, key: &str, d: &str) -> String {
        self.get(key)
            .and_then(|v| v.as_str())
            .unwrap_or(d)
            .to_string()
    }
    pub fn opt_str(&self, key: &str) -> Option<String> {
        match self.get(key) {
            Some(Json::Str(s)) => Some(s.clone()),
            _ => None,
        }
    }
    pub fn num_or(&self, key: &str, d: f64) -> f64 {
        self.get(key).and_then(|v| v.as_f64()).unwrap_or(d)
    }
    pub fn bool_or(&self, key: &str, d: bool) -> bool {
        self.get(key).and_then(|v| v.as_bool()).unwrap_or(d)
    }
    pub fn arr_or_empty(&self, key: &str) -> Vec<Json> {
        self.get(key)
            .and_then(|v| v.as_arr())
            .cloned()
            .unwrap_or_default()
    }
    pub fn set(&mut self, key: &str, v: Json) {
        if let Json::Obj(m) = self {
            m.insert(key.to_string(), v);
        }
    }
    pub fn push(&mut self, v: Json) {
        if let Json::Arr(a) = self {
            a.push(v);
        }
    }

    /// 真值规则：null/false/0/空串/空数组/空对象 为假，其余为真。
    pub fn truthy(&self) -> bool {
        match self {
            Json::Null => false,
            Json::Bool(b) => *b,
            Json::Num(n) => *n != 0.0,
            Json::Str(s) => !s.is_empty(),
            Json::Arr(a) => !a.is_empty(),
            Json::Obj(m) => !m.is_empty(),
        }
    }

    pub fn as_display(&self) -> String {
        match self {
            Json::Null => String::new(),
            Json::Bool(b) => b.to_string(),
            Json::Num(n) => fmt_num(*n),
            Json::Str(s) => s.clone(),
            other => other.to_string(),
        }
    }

    /// 紧凑序列化
    pub fn to_string(&self) -> String {
        let mut out = String::new();
        write_compact(self, &mut out);
        out
    }

    /// 2 空格缩进的美化序列化（给人和 git 看）
    pub fn to_pretty(&self) -> String {
        let mut out = String::new();
        write_pretty(self, &mut out, 0);
        out.push('\n');
        out
    }
}

fn fmt_num(n: f64) -> String {
    if n.is_finite() && n.fract() == 0.0 && n.abs() < 1e15 {
        format!("{}", n as i64)
    } else {
        format!("{}", n)
    }
}

fn write_compact(v: &Json, out: &mut String) {
    match v {
        Json::Null => out.push_str("null"),
        Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
        Json::Num(n) => out.push_str(&fmt_num(*n)),
        Json::Str(s) => write_str(s, out),
        Json::Arr(a) => {
            out.push('[');
            for (i, x) in a.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_compact(x, out);
            }
            out.push(']');
        }
        Json::Obj(m) => {
            out.push('{');
            for (i, (k, x)) in m.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_str(k, out);
                out.push(':');
                write_compact(x, out);
            }
            out.push('}');
        }
    }
}

fn write_pretty(v: &Json, out: &mut String, depth: usize) {
    let pad = |d: usize| "  ".repeat(d);
    match v {
        Json::Arr(a) if !a.is_empty() => {
            out.push_str("[\n");
            for (i, x) in a.iter().enumerate() {
                out.push_str(&pad(depth + 1));
                write_pretty(x, out, depth + 1);
                if i + 1 < a.len() {
                    out.push(',');
                }
                out.push('\n');
            }
            out.push_str(&pad(depth));
            out.push(']');
        }
        Json::Obj(m) if !m.is_empty() => {
            out.push_str("{\n");
            let n = m.len();
            for (i, (k, x)) in m.iter().enumerate() {
                out.push_str(&pad(depth + 1));
                write_str(k, out);
                out.push_str(": ");
                write_pretty(x, out, depth + 1);
                if i + 1 < n {
                    out.push(',');
                }
                out.push('\n');
            }
            out.push_str(&pad(depth));
            out.push('}');
        }
        other => write_compact(other, out),
    }
}

fn write_str(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
}

// ---------------------------------------------------------------- parser

pub fn parse(src: &str) -> Result<Json, String> {
    let b = src.as_bytes();
    let mut p = Parser { b, i: 0 };
    p.ws();
    let v = p.value()?;
    p.ws();
    if p.i != b.len() {
        return Err(p.err("文档结尾还有多余内容"));
    }
    Ok(v)
}

struct Parser<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Parser<'a> {
    fn err(&self, msg: &str) -> String {
        let (mut line, mut col) = (1usize, 1usize);
        for &c in &self.b[..self.i.min(self.b.len())] {
            if c == b'\n' {
                line += 1;
                col = 1;
            } else {
                col += 1;
            }
        }
        format!("JSON 解析错误（{}:{}）：{}", line, col, msg)
    }

    fn peek(&self) -> Option<u8> {
        self.b.get(self.i).copied()
    }

    fn ws(&mut self) {
        while let Some(c) = self.peek() {
            if c == b' ' || c == b'\t' || c == b'\n' || c == b'\r' {
                self.i += 1;
            } else {
                break;
            }
        }
    }

    fn expect(&mut self, c: u8) -> Result<(), String> {
        if self.peek() == Some(c) {
            self.i += 1;
            Ok(())
        } else {
            Err(self.err(&format!("期望 '{}'", c as char)))
        }
    }

    fn value(&mut self) -> Result<Json, String> {
        match self.peek() {
            None => Err(self.err("意外的文件结尾")),
            Some(b'{') => self.object(),
            Some(b'[') => self.array(),
            Some(b'"') => Ok(Json::Str(self.string()?)),
            Some(b't') => {
                self.lit("true")?;
                Ok(Json::Bool(true))
            }
            Some(b'f') => {
                self.lit("false")?;
                Ok(Json::Bool(false))
            }
            Some(b'n') => {
                self.lit("null")?;
                Ok(Json::Null)
            }
            Some(_) => self.number(),
        }
    }

    fn lit(&mut self, s: &str) -> Result<(), String> {
        if self.b[self.i..].starts_with(s.as_bytes()) {
            self.i += s.len();
            Ok(())
        } else {
            Err(self.err("无法识别的字面量"))
        }
    }

    fn object(&mut self) -> Result<Json, String> {
        self.expect(b'{')?;
        let mut m = BTreeMap::new();
        self.ws();
        if self.peek() == Some(b'}') {
            self.i += 1;
            return Ok(Json::Obj(m));
        }
        loop {
            self.ws();
            let k = self.string()?;
            self.ws();
            self.expect(b':')?;
            self.ws();
            let v = self.value()?;
            m.insert(k, v);
            self.ws();
            match self.peek() {
                Some(b',') => {
                    self.i += 1;
                }
                Some(b'}') => {
                    self.i += 1;
                    break;
                }
                _ => return Err(self.err("对象里期望 ',' 或 '}'")),
            }
        }
        Ok(Json::Obj(m))
    }

    fn array(&mut self) -> Result<Json, String> {
        self.expect(b'[')?;
        let mut a = Vec::new();
        self.ws();
        if self.peek() == Some(b']') {
            self.i += 1;
            return Ok(Json::Arr(a));
        }
        loop {
            self.ws();
            a.push(self.value()?);
            self.ws();
            match self.peek() {
                Some(b',') => {
                    self.i += 1;
                }
                Some(b']') => {
                    self.i += 1;
                    break;
                }
                _ => return Err(self.err("数组里期望 ',' 或 ']'")),
            }
        }
        Ok(Json::Arr(a))
    }

    fn string(&mut self) -> Result<String, String> {
        self.expect(b'"')?;
        let mut s = String::new();
        loop {
            let c = self.peek().ok_or_else(|| self.err("字符串未闭合"))?;
            match c {
                b'"' => {
                    self.i += 1;
                    return Ok(s);
                }
                b'\\' => {
                    self.i += 1;
                    let e = self.peek().ok_or_else(|| self.err("转义未闭合"))?;
                    self.i += 1;
                    match e {
                        b'"' => s.push('"'),
                        b'\\' => s.push('\\'),
                        b'/' => s.push('/'),
                        b'b' => s.push('\u{8}'),
                        b'f' => s.push('\u{c}'),
                        b'n' => s.push('\n'),
                        b'r' => s.push('\r'),
                        b't' => s.push('\t'),
                        b'u' => {
                            let cp = self.hex4()?;
                            let ch = if (0xD800..0xDC00).contains(&cp) {
                                // 代理对
                                if self.peek() == Some(b'\\') {
                                    self.i += 1;
                                    if self.peek() == Some(b'u') {
                                        self.i += 1;
                                        let lo = self.hex4()?;
                                        if (0xDC00..0xE000).contains(&lo) {
                                            let c = 0x10000u32
                                                + ((cp - 0xD800) << 10)
                                                + (lo - 0xDC00);
                                            char::from_u32(c).unwrap_or('\u{fffd}')
                                        } else {
                                            '\u{fffd}'
                                        }
                                    } else {
                                        '\u{fffd}'
                                    }
                                } else {
                                    '\u{fffd}'
                                }
                            } else {
                                char::from_u32(cp).unwrap_or('\u{fffd}')
                            };
                            s.push(ch);
                        }
                        _ => return Err(self.err("非法转义")),
                    }
                }
                _ => {
                    let rest = std::str::from_utf8(&self.b[self.i..])
                        .map_err(|_| self.err("非法 UTF-8"))?;
                    let ch = rest.chars().next().unwrap();
                    self.i += ch.len_utf8();
                    s.push(ch);
                }
            }
        }
    }

    fn hex4(&mut self) -> Result<u32, String> {
        if self.i + 4 > self.b.len() {
            return Err(self.err("\\u 转义不完整"));
        }
        let s = std::str::from_utf8(&self.b[self.i..self.i + 4])
            .map_err(|_| self.err("\\u 转义非法"))?;
        let v = u32::from_str_radix(s, 16).map_err(|_| self.err("\\u 转义非法"))?;
        self.i += 4;
        Ok(v)
    }

    fn number(&mut self) -> Result<Json, String> {
        let start = self.i;
        if self.peek() == Some(b'-') {
            self.i += 1;
        }
        while let Some(c) = self.peek() {
            if c.is_ascii_digit() || c == b'.' || c == b'e' || c == b'E' || c == b'+' || c == b'-' {
                self.i += 1;
            } else {
                break;
            }
        }
        let s = std::str::from_utf8(&self.b[start..self.i]).map_err(|_| self.err("非法数字"))?;
        s.parse::<f64>()
            .map(Json::Num)
            .map_err(|_| self.err("非法数字"))
    }
}

// ---------------------------------------------------------------- tests

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let src = r#"{"a":[1,2,{"b":"中文 \"引号\"\n"}],"c":true,"d":null}"#;
        let v = parse(src).unwrap();
        let s = v.to_string();
        let v2 = parse(&s).unwrap();
        assert_eq!(v, v2);
        assert_eq!(v.get("a").unwrap().at(2).unwrap().s_or("b", ""), "中文 \"引号\"\n");
    }

    #[test]
    fn errors() {
        assert!(parse("{").is_err());
        assert!(parse("{\"a\":1,}").is_err());
        assert!(parse("[1 2]").is_err());
    }

    #[test]
    fn numbers() {
        assert_eq!(parse("42").unwrap(), Json::Num(42.0));
        assert_eq!(parse("-1.5e2").unwrap(), Json::Num(-150.0));
        assert_eq!(Json::Num(3.0).to_string(), "3");
    }
}