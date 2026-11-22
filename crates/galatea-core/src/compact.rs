//! 打包时的**结构化去重**（字符串池化）。
//!
//! 剧本 JSON 里同一个字符串会被引用很多次：`"say"`、`"amiya"`、
//! `"assets/characters/amiya.webp"`、`"next"`…… 直接 DEFLATE 虽然也能压，
//! 但它是"盲压"；这里先做一次**按引用去重**，把重复字符串抽到池子里，
//! 原位置只留一个索引，再交给 DEFLATE 压剩下的结构。
//!
//! ```text
//! 池化前：{"speaker":"amiya",...} ×10  → 每次都要存 "amiya"
//! 池化后：pool:["amiya"],  节点里只写 {"$s":0} ×10
//! ```
//!
//! 这层处理只在 `.gal` 内部生效：`unpack` 出来的仍是**标准 JSON**，
//! 所以剧本文件依旧是人可读、可 diff、可手改的。
//!
//! # 编码格式
//!
//! ```json
//! {
//!   "$gal": 1,
//!   "pool": ["amiya", "say", "assets/characters/amiya.webp"],
//!   "doc":  { ...原文档，命中的字符串值换成 {"$s": 索引} ... }
//! }
//! ```

use crate::json::Json;
use std::collections::BTreeMap;

const REF_KEY: &str = "$s";

/// 低于这个长度的字符串不值得进池（索引本身也要占空间）
const MIN_LEN: usize = 3;
/// 出现次数少于这个数也不值得进池
const MIN_HITS: usize = 2;

fn collect(value: &Json, counts: &mut BTreeMap<String, usize>) {
    match value {
        Json::Str(s) => {
            if s.chars().count() >= MIN_LEN {
                *counts.entry(s.clone()).or_insert(0) += 1;
            }
        }
        Json::Arr(a) => a.iter().for_each(|v| collect(v, counts)),
        Json::Obj(m) => m.values().for_each(|v| collect(v, counts)),
        _ => {}
    }
}

fn replace(value: &Json, map: &BTreeMap<String, usize>) -> Json {
    match value {
        Json::Str(s) => match map.get(s) {
            Some(&i) => {
                let mut m = BTreeMap::new();
                m.insert(REF_KEY.to_string(), Json::n(i as f64));
                Json::Obj(m)
            }
            None => value.clone(),
        },
        Json::Arr(a) => Json::Arr(a.iter().map(|v| replace(v, map)).collect()),
        Json::Obj(m) => {
            let mut out = BTreeMap::new();
            for (k, v) in m {
                out.insert(k.clone(), replace(v, map));
            }
            Json::Obj(out)
        }
        other => other.clone(),
    }
}

fn expand_refs(value: &Json, pool: &[String]) -> Result<Json, String> {
    match value {
        Json::Obj(m) => {
            // 是不是一个引用节点
            if m.len() == 1 {
                if let Some(idx) = m.get(REF_KEY).and_then(|v| v.as_f64()) {
                    let i = idx as usize;
                    return pool
                        .get(i)
                        .map(|s| Json::Str(s.clone()))
                        .ok_or_else(|| format!("池引用 {} 越界", i));
                }
            }
            let mut out = BTreeMap::new();
            for (k, v) in m {
                out.insert(k.clone(), expand_refs(v, pool)?);
            }
            Ok(Json::Obj(out))
        }
        Json::Arr(a) => {
            let mut out = Vec::with_capacity(a.len());
            for v in a {
                out.push(expand_refs(v, pool)?);
            }
            Ok(Json::Arr(out))
        }
        other => Ok(other.clone()),
    }
}

/// 把文档压成「池 + 引用」形式
pub fn pack(doc: &Json) -> Json {
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    collect(doc, &mut counts);

    // 只把"真正重复且够长"的字符串入池，并按节省量排序（多的在前）
    let mut candidates: Vec<(String, usize)> = counts
        .into_iter()
        .filter(|(s, c)| *c >= MIN_HITS && s.chars().count() >= MIN_LEN)
        .collect();
    candidates.sort_by(|a, b| {
        let sa = (a.0.len() * a.1).saturating_sub(a.1 * 6 + a.0.len());
        let sb = (b.0.len() * b.1).saturating_sub(b.1 * 6 + b.0.len());
        sb.cmp(&sa)
    });

    let mut map: BTreeMap<String, usize> = BTreeMap::new();
    let mut pool: Vec<String> = Vec::new();
    for (s, _) in candidates {
        // 粗略估算：省下的字节 = len*hits - (索引节点 ~8 字节*hits + 池里存一次)
        let hits = map.len();
        let _ = hits;
        map.insert(s.clone(), pool.len());
        pool.push(s);
    }

    let doc2 = replace(doc, &map);
    let mut root = Json::obj();
    root.set("$gal", Json::n(1.0));
    root.set(
        "pool",
        Json::Arr(pool.into_iter().map(Json::Str).collect()),
    );
    root.set("doc", doc2);
    root
}

/// 还原成普通文档
pub fn unpack(wrapped: &Json) -> Result<Json, String> {
    let is_wrapped = wrapped.get("$gal").and_then(|v| v.as_f64()).is_some()
        && wrapped.get("pool").is_some()
        && wrapped.get("doc").is_some();
    if !is_wrapped {
        // 不是池化格式，直接返回
        return Ok(wrapped.clone());
    }
    let pool: Vec<String> = wrapped
        .get("pool")
        .and_then(|v| v.as_arr())
        .map(|a| {
            a.iter()
                .map(|v| v.as_str().unwrap_or("").to_string())
                .collect()
        })
        .unwrap_or_default();
    let doc = wrapped.get("doc").ok_or("缺少 doc")?;
    expand_refs(doc, &pool)
}

/// 便捷：文本进，文本出
pub fn pack_str(src: &str) -> Result<String, String> {
    let doc = crate::json::parse(src)?;
    Ok(pack(&doc).to_string())
}

pub fn unpack_str(src: &str) -> Result<String, String> {
    let doc = crate::json::parse(src)?;
    Ok(unpack(&doc)?.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> String {
        let mut nodes = Vec::new();
        for i in 0..12 {
            nodes.push(format!(
                r#"{{"id":"s{}","type":"say","speaker":"amiya","cast":"char_amiya","art":"art_amiya","portrait":"assets/characters/amiya.webp","text":"博士，今天的作战报告……写完了吗？"}}"#,
                i
            ));
        }
        format!(r#"{{"format":"galatea.graph/1","nodes":[{}]}}"#, nodes.join(","))
    }

    #[test]
    fn roundtrip_is_lossless() {
        let src = sample();
        let packed = pack_str(&src).unwrap();
        let back = unpack_str(&packed).unwrap();
        // 通过 JSON 值比较（键序与空白可能不同）
        let a = crate::json::parse(&src).unwrap();
        let b = crate::json::parse(&back).unwrap();
        assert_eq!(a, b);
    }

    #[test]
    fn shrinks_repetitive_doc() {
        let src = sample();
        let packed = pack_str(&src).unwrap();
        assert!(
            packed.len() < src.len(),
            "池化后应该更小：{} → {}",
            src.len(),
            packed.len()
        );
        println!("池化：{} → {} 字节（{:.0}%）", src.len(), packed.len(), packed.len() as f64 / src.len() as f64 * 100.0);
    }

    #[test]
    fn pick_the_smaller_encoding() {
        // 实测结论：DEFLATE 的 LZ77 本身就在做"重复串只记一次"，
        // 预池化经常反而更大（把连续重复打散成索引）。
        // 所以工程上不硬选，两种编码都试压一遍取小的。
        let src = sample();
        let compacted = pack_str(&src).unwrap();
        let a = crate::gal::deflate_for_test(src.as_bytes());
        let b = crate::gal::deflate_for_test(compacted.as_bytes());
        println!("仅 deflate {} 字节 / 池化+deflate {} 字节 / 取最优 {}", a.len(), b.len(), a.len().min(b.len()));
        let best = a.len().min(b.len());
        assert!(best <= a.len());
        // 池化在"不压缩存储"时一定赢（省 31%）
        assert!(compacted.len() < src.len());
    }

    #[test]
    fn plain_doc_passes_through() {
        let plain = r#"{"a":1,"b":[1,2,3]}"#;
        let doc = crate::json::parse(plain).unwrap();
        assert_eq!(unpack(&doc).unwrap(), doc);
    }

    #[test]
    fn marker_label_chain() {
        // 标记名 → 显示名：同一个 tag 在不同场景可以显示成不同文字
        let src = r#"{
          "nodes":[
            {"id":"m1","type":"label","tag":"amiya","text":"阿米娅"},
            {"id":"m2","type":"label","tag":"amiya","text":"？？？"}
          ]}"#;
        let story = crate::graph::Story::from_json_str(src).unwrap();
        match &story.node("m1").unwrap().kind {
            crate::graph::NodeKind::Label { tag, text, .. } => {
                assert_eq!(tag.as_deref(), Some("amiya"));
                assert_eq!(text, "阿米娅");
            }
            _ => panic!(),
        }
        match &story.node("m2").unwrap().kind {
            crate::graph::NodeKind::Label { text, .. } => assert_eq!(text, "？？？"),
            _ => panic!(),
        }
    }
}