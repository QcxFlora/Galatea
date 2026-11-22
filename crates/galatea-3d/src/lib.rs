//! Galatea 3D 后端 —— 对 Flutter 暴露的 **C ABI 稳定接口**。
//!
//! # 为什么是 C ABI
//!
//! Flutter 侧（`dart:ffi`）只认 C 函数。把渲染引擎封在一个 `cdylib` 里，
//! 上层脚本、场景图、`.gal` 格式都不需要知道底层用的是哪个引擎：
//!
//! ```text
//!   .gal 剧本 + Rust 脚本
//!            │
//!            ▼
//!   galatea-core::scene3d  （场景图 / 相机 / 网格，后端无关）
//!            │
//!      ┌─────┴─────┐
//!      ▼           ▼
//!   软件光栅      Filament（C++，正式版）
//!   （本文件）     由 cxx 桥接，接口一致
//!      └─────┬─────┘
//!            ▼
//!      C ABI（本 crate）→ dart:ffi → Flutter Texture
//! ```
//!
//! # 生命周期
//!
//! ```c
//! G3D* e = g3d_new(640, 360);
//! g3d_add_box(e, "a", 0,0,0, 1,1,1, 0xE8A87CFF);
//! g3d_set_rotation(e, "a", 0, 45, 0);
//! g3d_set_camera(e, 0,2,6, 0,0,0);
//! g3d_render(e);
//! const uint8_t* px = g3d_pixels(e);   // RGBA，宽*高*4
//! g3d_free(e);
//! ```
//!
//! 所有指针由引擎持有，**调用方不要 free**。

use galatea_core::scene3d::{encode_png, Frame, Rgba, Renderer, Scene, Vec3};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_uint};

pub struct G3D {
    scene: Scene,
    renderer: Renderer,
    last: Frame,
    /// 给 PNG 导出用
    last_png: Vec<u8>,
    version: CString,
}

fn cstr(s: &str) -> CString {
    CString::new(s.replace('\0', "")).unwrap_or_else(|_| CString::new("").unwrap())
}

fn from_c(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(p) }.to_string_lossy().to_string()
}

fn rgba_of(v: c_uint) -> Rgba {
    // 0xRRGGBBAA
    Rgba::new(
        ((v >> 24) & 0xFF) as f32 / 255.0,
        ((v >> 16) & 0xFF) as f32 / 255.0,
        ((v >> 8) & 0xFF) as f32 / 255.0,
        (v & 0xFF) as f32 / 255.0,
    )
}

// ---------------------------------------------------------------- 生命周期

/// 创建引擎（w/h 为渲染分辨率，建议 480×270 ~ 960×540）
#[no_mangle]
pub extern "C" fn g3d_new(width: c_int, height: c_int) -> *mut G3D {
    let w = width.clamp(16, 4096) as usize;
    let h = height.clamp(16, 4096) as usize;
    let mut scene = Scene::new();
    scene.light_dir = Vec3::new(-0.35, -1.0, -0.55).normalize();
    let engine = G3D {
        scene,
        renderer: Renderer::new(w, h),
        last: Frame {
            width: w,
            height: h,
            rgba: vec![0; w * h * 4],
        },
        last_png: Vec::new(),
        version: cstr("galatea-3d/0.1 (software-raster)"),
    };
    Box::into_raw(Box::new(engine))
}

#[no_mangle]
pub extern "C" fn g3d_free(engine: *mut G3D) {
    if engine.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(engine));
    }
}

#[no_mangle]
pub extern "C" fn g3d_version(engine: *const G3D) -> *const c_char {
    if engine.is_null() {
        return std::ptr::null();
    }
    unsafe { (*engine).version.as_ptr() }
}

// ---------------------------------------------------------------- 场景操作

#[no_mangle]
pub extern "C" fn g3d_clear(engine: *mut G3D) {
    if let Some(e) = unsafe { engine.as_mut() } {
        e.scene.clear();
    }
}

/// 加一个方块（kind: "cube" / "sphere" / "plane"）
#[no_mangle]
pub extern "C" fn g3d_add(
    engine: *mut G3D,
    name: *const c_char,
    kind: *const c_char,
    x: f32,
    y: f32,
    z: f32,
    sx: f32,
    sy: f32,
    sz: f32,
    rgba: c_uint,
) {
    let Some(e) = (unsafe { engine.as_mut() }) else { return };
    let name = from_c(name);
    let kind = from_c(kind);
    let o = e.scene.add(&name, &kind);
    o.position = Vec3::new(x, y, z);
    o.scale = Vec3::new(sx, sy, sz);
    o.color = rgba_of(rgba);
}

#[no_mangle]
pub extern "C" fn g3d_remove(engine: *mut G3D, name: *const c_char) {
    if let Some(e) = unsafe { engine.as_mut() } {
        e.scene.remove(&from_c(name));
    }
}

#[no_mangle]
pub extern "C" fn g3d_set_position(engine: *mut G3D, name: *const c_char, x: f32, y: f32, z: f32) {
    if let Some(e) = unsafe { engine.as_mut() } {
        let n = from_c(name);
        if let Some(o) = e.scene.object_mut(&n) {
            o.position = Vec3::new(x, y, z);
        }
    }
}

#[no_mangle]
pub extern "C" fn g3d_set_rotation(engine: *mut G3D, name: *const c_char, rx: f32, ry: f32, rz: f32) {
    if let Some(e) = unsafe { engine.as_mut() } {
        let n = from_c(name);
        if let Some(o) = e.scene.object_mut(&n) {
            o.rotation = Vec3::new(rx, ry, rz);
        }
    }
}

#[no_mangle]
pub extern "C" fn g3d_set_color(engine: *mut G3D, name: *const c_char, rgba: c_uint) {
    if let Some(e) = unsafe { engine.as_mut() } {
        let n = from_c(name);
        if let Some(o) = e.scene.object_mut(&n) {
            o.color = rgba_of(rgba);
        }
    }
}

#[no_mangle]
pub extern "C" fn g3d_set_visible(engine: *mut G3D, name: *const c_char, visible: c_int) {
    if let Some(e) = unsafe { engine.as_mut() } {
        let n = from_c(name);
        if let Some(o) = e.scene.object_mut(&n) {
            o.visible = visible != 0;
        }
    }
}

#[no_mangle]
pub extern "C" fn g3d_set_camera(
    engine: *mut G3D,
    ex: f32,
    ey: f32,
    ez: f32,
    tx: f32,
    ty: f32,
    tz: f32,
) {
    if let Some(e) = unsafe { engine.as_mut() } {
        e.scene.camera.eye = Vec3::new(ex, ey, ez);
        e.scene.camera.target = Vec3::new(tx, ty, tz);
    }
}

#[no_mangle]
pub extern "C" fn g3d_set_fov(engine: *mut G3D, fovy_deg: f32) {
    if let Some(e) = unsafe { engine.as_mut() } {
        e.scene.camera.fov_y = fovy_deg.clamp(10.0, 120.0);
    }
}

// ---------------------------------------------------------------- 渲染

/// 渲染一帧，返回 1 表示成功
#[no_mangle]
pub extern "C" fn g3d_render(engine: *mut G3D) -> c_int {
    let Some(e) = (unsafe { engine.as_mut() }) else { return 0 };
    e.last = e.renderer.render(&e.scene);
    1
}

/// RGBA 像素指针（宽×高×4），生命周期到下一次 g3d_render
#[no_mangle]
pub extern "C" fn g3d_pixels(engine: *const G3D) -> *const u8 {
    if engine.is_null() {
        return std::ptr::null();
    }
    unsafe { (*engine).last.rgba.as_ptr() }
}

#[no_mangle]
pub extern "C" fn g3d_width(engine: *const G3D) -> c_int {
    if engine.is_null() {
        return 0;
    }
    unsafe { (*engine).last.width as c_int }
}

#[no_mangle]
pub extern "C" fn g3d_height(engine: *const G3D) -> c_int {
    if engine.is_null() {
        return 0;
    }
    unsafe { (*engine).last.height as c_int }
}

/// 把最近一帧编码成 PNG，返回字节指针；长度见 g3d_png_len
#[no_mangle]
pub extern "C" fn g3d_png(engine: *mut G3D) -> *const u8 {
    let Some(e) = (unsafe { engine.as_mut() }) else { return std::ptr::null() };
    e.last_png = encode_png(&e.last);
    e.last_png.as_ptr()
}

#[no_mangle]
pub extern "C" fn g3d_png_len(engine: *const G3D) -> c_int {
    if engine.is_null() {
        return 0;
    }
    unsafe { (*engine).last_png.len() as c_int }
}

/// 场景摘要（JSON 字符串），出错返回 NULL
#[no_mangle]
pub extern "C" fn g3d_scene_json(engine: *const G3D) -> *mut c_char {
    if engine.is_null() {
        return std::ptr::null_mut();
    }
    let json = unsafe { (*engine).scene.to_json().to_string() };
    CString::new(json).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn g3d_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_render_and_read_pixels() {
        let e = g3d_new(64, 64);
        assert!(!e.is_null());
        let name = cstr("box");
        let kind = cstr("cube");
        g3d_add(e, name.as_ptr(), kind.as_ptr(), 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0xE8A87CFF);
        g3d_set_camera(e, 0.0, 0.0, 3.0, 0.0, 0.0, 0.0);
        assert_eq!(g3d_render(e), 1);

        assert_eq!(g3d_width(e), 64);
        assert_eq!(g3d_height(e), 64);
        let px = g3d_pixels(e);
        assert!(!px.is_null());
        // 中心像素不是纯背景
        let idx = ((32 * 64) + 32) * 4;
        let v = unsafe { std::slice::from_raw_parts(px, 64 * 64 * 4) };
        assert!(v[idx] > 80, "中心应有物体颜色，实际 {}", v[idx]);
        g3d_free(e);
    }

    #[test]
    fn png_export_works() {
        let e = g3d_new(32, 32);
        let n = cstr("b");
        let k = cstr("sphere");
        g3d_add(e, n.as_ptr(), k.as_ptr(), 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0x66CCFFFF);
        g3d_render(e);
        let p = g3d_png(e);
        let len = g3d_png_len(e);
        assert!(len > 100);
        let bytes = unsafe { std::slice::from_raw_parts(p, len as usize) };
        assert_eq!(&bytes[0..4], &[0x89, b'P', b'N', b'G']);
        g3d_free(e);
    }

    #[test]
    fn null_safety() {
        assert!(g3d_pixels(std::ptr::null()).is_null());
        assert_eq!(g3d_width(std::ptr::null()), 0);
        g3d_free(std::ptr::null_mut()); // 不应崩
        g3d_clear(std::ptr::null_mut());
    }
}
