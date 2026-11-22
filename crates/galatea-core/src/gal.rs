//! `.gal` —— Galatea 的作品包格式。
//!
//! 目标：把「剧本 + 脚本 + 立绘 + 背景 + 音频」压成**一个文件**，直接丢给播放器。
//!
//! # 格式（v1）
//!
//! ```text
//! ┌──────────────────────────────────────────────┐
//! │ magic      "GAL\x01"              4 字节      │
//! │ version    u16 LE                 = 1        │
//! │ flags      u16 LE                 保留       │
//! │ count      u32 LE                 条目数     │
//! │ index_len  u32 LE                 索引字节数 │
//! ├──────────────────────────────────────────────┤
//! │ 索引区（每条约 30+名字长）                    │
//! │   name_len u16                                │
//! │   name     UTF-8                              │
//! │   method   u8    0=原样 1=DEFLATE             │
//! │   offset   u64   相对数据区起点               │
//! │   csize    u64   压缩后字节数                 │
//! │   usize    u64   原始字节数                   │
//! │   crc32    u32   原始内容校验                 │
//! ├──────────────────────────────────────────────┤
//! │ 数据区（各条目按索引顺序紧密排列）             │
//! └──────────────────────────────────────────────┘
//! ```
//!
//! # 为什么"密度高"
//!
//! * 文本（剧本 JSON / 脚本源码 / 说明）走 **DEFLATE level 9**，通常压到 1/5 ~ 1/8
//! * 图片（PNG/JPG）本身已压缩，**不再二次压缩**（否则又慢又变大），原样存储
//! * 每个条目**先试压一次**：如果压缩后反而更大，自动退回原样（`method=0`）
//! * 索引只存名字 + 偏移，不冗余存路径表

use std::collections::BTreeMap;
use std::io::{Read, Write};

use flate2::read::DeflateDecoder;
use flate2::write::DeflateEncoder;
use flate2::Compression;

pub const MAGIC: &[u8; 4] = b"GAL\x01";
pub const VERSION: u16 = 1;

#[derive(Debug, Clone)]
pub struct Entry {
    pub name: String,
    pub method: u8, // 0 = stored, 1 = deflate
    pub offset: u64,
    pub csize: u64,
    pub usize: u64,
    pub crc32: u32,
}

impl Entry {
    pub fn ratio(&self) -> f64 {
        if self.usize == 0 {
            1.0
        } else {
            self.csize as f64 / self.usize as f64
        }
    }
}

#[derive(Debug, Clone)]
pub struct Archive {
    pub entries: Vec<Entry>,
    pub data: Vec<u8>,
}

// ---------------------------------------------------------------- crc32

fn crc32_table() -> [u32; 256] {
    let mut t = [0u32; 256];
    for (i, slot) in t.iter_mut().enumerate() {
        let mut c = i as u32;
        for _ in 0..8 {
            c = if c & 1 != 0 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 };
        }
        *slot = c;
    }
    t
}

pub fn crc32(data: &[u8]) -> u32 {
    let t = crc32_table();
    let mut c = 0xFFFF_FFFFu32;
    for &b in data {
        c = t[((c ^ b as u32) & 0xFF) as usize] ^ (c >> 8);
    }
    c ^ 0xFFFF_FFFF
}

// ---------------------------------------------------------------- 压缩判定

/// 已经是压缩格式、再压没意义的扩展名
fn is_precompressed(name: &str) -> bool {
    let l = name.to_ascii_lowercase();
    [".png", ".jpg", ".jpeg", ".webp", ".gif", ".avif", ".mp3", ".ogg", ".opus", ".m4a", ".mp4", ".zip", ".gal"]
        .iter()
        .any(|ext| l.ends_with(ext))
}

fn deflate(data: &[u8]) -> Result<Vec<u8>, String> {
    let mut e = DeflateEncoder::new(Vec::new(), Compression::new(9));
    e.write_all(data).map_err(|e| e.to_string())?;
    e.finish().map_err(|e| e.to_string())
}

fn inflate(data: &[u8]) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    DeflateDecoder::new(data)
        .read_to_end(&mut out)
        .map_err(|e| e.to_string())?;
    Ok(out)
}

// ---------------------------------------------------------------- 打包

/// 把一组「路径 → 内容」打包成 `.gal` 字节流
pub fn pack(files: &BTreeMap<String, Vec<u8>>) -> Result<Vec<u8>, String> {
    let mut entries: Vec<Entry> = Vec::new();
    let mut blobs: Vec<u8> = Vec::new();

    for (name, raw) in files {
        let name = name.replace('\\', "/");
        let (method, body) = if is_precompressed(&name) || raw.len() < 64 {
            (0u8, raw.clone())
        } else {
            let packed = deflate(raw)?;
            // 压不动就存原样
            if packed.len() + 8 >= raw.len() {
                (0u8, raw.clone())
            } else {
                (1u8, packed)
            }
        };
        let offset = blobs.len() as u64;
        let csize = body.len() as u64;
        blobs.extend_from_slice(&body);
        entries.push(Entry {
            name,
            method,
            offset,
            csize,
            usize: raw.len() as u64,
            crc32: crc32(raw),
        });
    }

    // 索引
    let mut index: Vec<u8> = Vec::new();
    for e in &entries {
        let nb = e.name.as_bytes();
        if nb.len() > u16::MAX as usize {
            return Err(format!("文件名太长：{}", e.name));
        }
        index.extend_from_slice(&(nb.len() as u16).to_le_bytes());
        index.extend_from_slice(nb);
        index.push(e.method);
        index.extend_from_slice(&e.offset.to_le_bytes());
        index.extend_from_slice(&e.csize.to_le_bytes());
        index.extend_from_slice(&e.usize.to_le_bytes());
        index.extend_from_slice(&e.crc32.to_le_bytes());
    }

    let mut out = Vec::with_capacity(16 + index.len() + blobs.len());
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&VERSION.to_le_bytes());
    out.extend_from_slice(&0u16.to_le_bytes()); // flags
    out.extend_from_slice(&(entries.len() as u32).to_le_bytes());
    out.extend_from_slice(&(index.len() as u32).to_le_bytes());
    out.extend_from_slice(&index);
    out.extend_from_slice(&blobs);
    Ok(out)
}

// ---------------------------------------------------------------- 解包

pub fn parse(bytes: &[u8]) -> Result<Archive, String> {
    if bytes.len() < 16 {
        return Err("文件太短，不是 .gal".into());
    }
    if &bytes[0..4] != MAGIC {
        return Err("魔数不匹配：不是 .gal 文件".into());
    }
    let ver = u16::from_le_bytes([bytes[4], bytes[5]]);
    if ver != VERSION {
        return Err(format!("不支持的 .gal 版本：{}", ver));
    }
    let count = u32::from_le_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]) as usize;
    let index_len = u32::from_le_bytes([bytes[12], bytes[13], bytes[14], bytes[15]]) as usize;
    let index_start = 16;
    let data_start = index_start + index_len;
    if bytes.len() < data_start {
        return Err("索引区越界".into());
    }

    let mut p = index_start;
    let mut entries = Vec::with_capacity(count);
    for _ in 0..count {
        let need = |p: usize, n: usize| -> Result<(), String> {
            if p + n > data_start {
                Err("索引损坏".into())
            } else {
                Ok(())
            }
        };
        need(p, 2)?;
        let nl = u16::from_le_bytes([bytes[p], bytes[p + 1]]) as usize;
        p += 2;
        need(p, nl)?;
        let name = String::from_utf8_lossy(&bytes[p..p + nl]).to_string();
        p += nl;
        need(p, 1)?;
        let method = bytes[p];
        p += 1;
        need(p, 28)?;
        let offset = u64::from_le_bytes(bytes[p..p + 8].try_into().unwrap());
        p += 8;
        let csize = u64::from_le_bytes(bytes[p..p + 8].try_into().unwrap());
        p += 8;
        let usize_ = u64::from_le_bytes(bytes[p..p + 8].try_into().unwrap());
        p += 8;
        let crc = u32::from_le_bytes(bytes[p..p + 4].try_into().unwrap());
        p += 4;
        entries.push(Entry {
            name,
            method,
            offset,
            csize,
            usize: usize_,
            crc32: crc,
        });
    }

    Ok(Archive {
        entries,
        data: bytes[data_start..].to_vec(),
    })
}

impl Archive {
    /// 取出一个条目的原始内容（含 crc 校验）
    pub fn read(&self, name: &str) -> Result<Vec<u8>, String> {
        let e = self
            .entries
            .iter()
            .find(|e| e.name == name)
            .ok_or_else(|| format!("包里没有 `{}`", name))?;
        let start = e.offset as usize;
        let end = start + e.csize as usize;
        if end > self.data.len() {
            return Err(format!("`{}` 数据越界", name));
        }
        let raw = match e.method {
            0 => self.data[start..end].to_vec(),
            1 => inflate(&self.data[start..end])?,
            m => return Err(format!("未知压缩方法 {}", m)),
        };
        if raw.len() as u64 != e.usize {
            return Err(format!("`{}` 长度不符", name));
        }
        if crc32(&raw) != e.crc32 {
            return Err(format!("`{}` 校验失败（文件损坏）", name));
        }
        Ok(raw)
    }

    /// 全部解出来
    pub fn read_all(&self) -> Result<BTreeMap<String, Vec<u8>>, String> {
        let mut out = BTreeMap::new();
        for e in &self.entries {
            out.insert(e.name.clone(), self.read(&e.name)?);
        }
        Ok(out)
    }

    pub fn total_packed(&self) -> u64 {
        self.entries.iter().map(|e| e.csize).sum()
    }

    pub fn total_raw(&self) -> u64 {
        self.entries.iter().map(|e| e.usize).sum()
    }
}

/// 从剧本 JSON 里推断需要一起打包的资源路径
pub fn collect_assets(story_json: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    // 简单扫：形如 "assets/xxx.png" 的字符串字面量
    let mut chars = story_json.char_indices().peekable();
    while let Some((i, c)) = chars.next() {
        if c != '"' {
            continue;
        }
        // 读出这个字符串
        let start = i + 1;
        let mut end = start;
        let bytes = story_json.as_bytes();
        let mut j = start;
        while j < bytes.len() {
            if bytes[j] == b'\\' {
                j += 2;
                continue;
            }
            if bytes[j] == b'"' {
                end = j;
                break;
            }
            j += 1;
        }
        if end > start {
            let lit = &story_json[start..end];
            if (lit.starts_with("assets/")
                || lit.starts_with("scripts/")
                || lit.contains(".png")
                || lit.contains(".rs"))
                && !lit.contains("..")
            {
                if !out.contains(&lit.to_string()) {
                    out.push(lit.to_string());
                }
            }
        }
        // 跳过这个字符串
        while let Some(&(k, _)) = chars.peek() {
            if k <= end {
                chars.next();
            } else {
                break;
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> BTreeMap<String, Vec<u8>> {
        let mut m = BTreeMap::new();
        // 高重复文本：应该被压得很小
        let text = "阿米娅：「博士，今天的作战报告……写完了吗？」\n".repeat(200);
        m.insert("story.gala.json".to_string(), text.into_bytes());
        m.insert("scripts/intro.rs".to_string(), "fn f(t) { return t * 2.0; }".repeat(50).into_bytes());
        // 伪 PNG（已压缩，应该原样存）
        let mut png = vec![0x89, b'P', b'N', b'G'];
        png.extend((0..=255u8).cycle().take(4096));
        m.insert("assets/characters/amiya.png".to_string(), png);
        m
    }

    #[test]
    fn pack_unpack_roundtrip() {
        let files = sample();
        let bytes = pack(&files).unwrap();
        let arc = parse(&bytes).unwrap();
        assert_eq!(arc.entries.len(), 3);
        let back = arc.read_all().unwrap();
        assert_eq!(back, files);
    }

    #[test]
    fn compresses_text_density() {
        let files = sample();
        let bytes = pack(&files).unwrap();
        let arc = parse(&bytes).unwrap();
        let text_entry = arc
            .entries
            .iter()
            .find(|e| e.name == "story.gala.json")
            .unwrap();
        assert_eq!(text_entry.method, 1, "文本应该走 deflate");
        assert!(text_entry.ratio() < 0.25, "文本压缩率应低于 25%，实际 {}", text_entry.ratio());

        let png_entry = arc.entries.iter().find(|e| e.name.ends_with(".png")).unwrap();
        assert_eq!(png_entry.method, 0, "图片不该二次压缩");
    }

    #[test]
    fn corrupt_detected() {
        let files = sample();
        let mut bytes = pack(&files).unwrap();
        let n = bytes.len();
        bytes[n - 10] ^= 0xFF; // 破坏数据区末尾
        let arc = parse(&bytes).unwrap();
        // 至少有一个条目读出来应该失败（crc 抓住）
        let mut caught = false;
        for e in &arc.entries {
            if arc.read(&e.name).is_err() {
                caught = true;
            }
        }
        assert!(caught, "损坏应该被 crc 抓住");
    }

    #[test]
    fn bad_magic() {
        assert!(parse(b"nope-nope-nope-nope").is_err());
    }

    #[test]
    fn collect_from_story() {
        let json = r#"{
            "nodes": [
              {"id":"s1","type":"say","portrait":"assets/characters/amiya.png"},
              {"id":"s2","type":"script","src":"scripts/intro.rs"}
            ]
        }"#;
        let got = collect_assets(json);
        assert!(got.contains(&"assets/characters/amiya.png".to_string()));
        assert!(got.contains(&"scripts/intro.rs".to_string()));
    }
}