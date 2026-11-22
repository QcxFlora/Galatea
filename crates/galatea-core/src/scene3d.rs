//! 3D 场景核心：向量 / 矩阵 / 相机 / 网格 / 光栅化。
//!
//! 定位：**后端无关的上层**。这里不碰任何图形 API，
//! 只负责"把一堆三角形变换到屏幕上并着色"。
//!
//! * [`Renderer`] 是纯软件实现（Z-buffer + 平面着色），零依赖、可测试、
//!   在 CI 里也能跑，能直接输出 PNG；
//! * 后续加 wgpu 后端时，网格/相机/变换这些东西可以直接搬过去，
//!   只把"三角形填充"换成 GPU 管线；
//! * 脚本通过 [`Scene`] 的公开方法建场景（见 `script.rs` 的宿主命令）。
//!
//! 约定：右手坐标系，+Y 朝上，相机看向 -Z，深度缓冲越小越近。

use crate::json::Json;

// ---------------------------------------------------------------- 向量

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Vec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Default for Vec3 {
    fn default() -> Self {
        Vec3::ZERO
    }
}

impl Vec3 {
    pub const ZERO: Vec3 = Vec3 { x: 0.0, y: 0.0, z: 0.0 };
    pub const UP: Vec3 = Vec3 { x: 0.0, y: 1.0, z: 0.0 };

    pub fn new(x: f32, y: f32, z: f32) -> Self {
        Vec3 { x, y, z }
    }
    pub fn splat(v: f32) -> Self {
        Vec3 { x: v, y: v, z: v }
    }
    pub fn add(self, o: Vec3) -> Vec3 {
        Vec3::new(self.x + o.x, self.y + o.y, self.z + o.z)
    }
    pub fn sub(self, o: Vec3) -> Vec3 {
        Vec3::new(self.x - o.x, self.y - o.y, self.z - o.z)
    }
    pub fn mul(self, s: f32) -> Vec3 {
        Vec3::new(self.x * s, self.y * s, self.z * s)
    }
    pub fn dot(self, o: Vec3) -> f32 {
        self.x * o.x + self.y * o.y + self.z * o.z
    }
    pub fn cross(self, o: Vec3) -> Vec3 {
        Vec3::new(
            self.y * o.z - self.z * o.y,
            self.z * o.x - self.x * o.z,
            self.x * o.y - self.y * o.x,
        )
    }
    pub fn length(self) -> f32 {
        self.dot(self).sqrt()
    }
    pub fn normalize(self) -> Vec3 {
        let l = self.length();
        if l <= 1e-8 {
            Vec3::ZERO
        } else {
            self.mul(1.0 / l)
        }
    }
    pub fn lerp(a: Vec3, b: Vec3, t: f32) -> Vec3 {
        a.add(b.sub(a).mul(t))
    }
}

// ---------------------------------------------------------------- 矩阵

/// 列主序 4×4
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Mat4(pub [f32; 16]);

impl Mat4 {
    pub fn identity() -> Self {
        let mut m = [0.0; 16];
        m[0] = 1.0;
        m[5] = 1.0;
        m[10] = 1.0;
        m[15] = 1.0;
        Mat4(m)
    }

    pub fn translation(v: Vec3) -> Self {
        let mut m = Mat4::identity();
        m.0[12] = v.x;
        m.0[13] = v.y;
        m.0[14] = v.z;
        m
    }

    pub fn scale(v: Vec3) -> Self {
        let mut m = Mat4::identity();
        m.0[0] = v.x;
        m.0[5] = v.y;
        m.0[10] = v.z;
        m
    }

    pub fn rotation_x(rad: f32) -> Self {
        let (s, c) = rad.sin_cos();
        let mut m = Mat4::identity();
        m.0[5] = c;
        m.0[6] = s;
        m.0[9] = -s;
        m.0[10] = c;
        m
    }

    pub fn rotation_y(rad: f32) -> Self {
        let (s, c) = rad.sin_cos();
        let mut m = Mat4::identity();
        m.0[0] = c;
        m.0[2] = -s;
        m.0[8] = s;
        m.0[10] = c;
        m
    }

    pub fn rotation_z(rad: f32) -> Self {
        let (s, c) = rad.sin_cos();
        let mut m = Mat4::identity();
        m.0[0] = c;
        m.0[1] = s;
        m.0[4] = -s;
        m.0[5] = c;
        m
    }

    pub fn perspective(fovy_deg: f32, aspect: f32, near: f32, far: f32) -> Self {
        let f = 1.0 / (fovy_deg.to_radians() * 0.5).tan();
        let mut m = [0.0; 16];
        m[0] = f / aspect.max(1e-6);
        m[5] = f;
        m[10] = (far + near) / (near - far);
        m[11] = -1.0;
        m[14] = 2.0 * far * near / (near - far);
        Mat4(m)
    }

    /// 右手系 look_at
    pub fn look_at(eye: Vec3, target: Vec3, up: Vec3) -> Self {
        let f = target.sub(eye).normalize(); // 前
        let s = f.cross(up).normalize(); // 右
        let u = s.cross(f); // 上
        let mut m = Mat4::identity();
        m.0[0] = s.x;
        m.0[4] = s.y;
        m.0[8] = s.z;
        m.0[1] = u.x;
        m.0[5] = u.y;
        m.0[9] = u.z;
        m.0[2] = -f.x;
        m.0[6] = -f.y;
        m.0[10] = -f.z;
        m.0[12] = -s.dot(eye);
        m.0[13] = -u.dot(eye);
        m.0[14] = f.dot(eye);
        m
    }

    pub fn mul(&self, o: &Mat4) -> Mat4 {
        let a = &self.0;
        let b = &o.0;
        let mut r = [0.0f32; 16];
        for c in 0..4 {
            for row in 0..4 {
                let mut sum = 0.0;
                for k in 0..4 {
                    sum += a[k * 4 + row] * b[c * 4 + k];
                }
                r[c * 4 + row] = sum;
            }
        }
        Mat4(r)
    }

    /// 变换一个点（w=1），返回 (x, y, z, w)
    pub fn transform_point(&self, p: Vec3) -> (f32, f32, f32, f32) {
        let m = &self.0;
        (
            m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
            m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
            m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14],
            m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15],
        )
    }
}

// ---------------------------------------------------------------- 颜色

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rgba {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

impl Rgba {
    pub fn new(r: f32, g: f32, b: f32, a: f32) -> Self {
        Rgba { r, g, b, a }
    }
    pub fn hex(s: &str) -> Rgba {
        let h = s.trim_start_matches('#');
        let parse = |i: usize| -> f32 {
            u8::from_str_radix(h.get(i..i + 2).unwrap_or("ff"), 16).unwrap_or(255) as f32 / 255.0
        };
        if h.len() >= 6 {
            Rgba::new(parse(0), parse(2), parse(4), 1.0)
        } else {
            Rgba::new(1.0, 1.0, 1.0, 1.0)
        }
    }
    pub fn scale(self, k: f32) -> Rgba {
        Rgba::new(
            (self.r * k).clamp(0.0, 1.0),
            (self.g * k).clamp(0.0, 1.0),
            (self.b * k).clamp(0.0, 1.0),
            self.a,
        )
    }
    pub fn to_json(&self) -> Json {
        let c = |v: f32| Json::n((v * 255.0).round() as f64);
        Json::Arr(vec![c(self.r), c(self.g), c(self.b), c(self.a)])
    }
}

impl Default for Rgba {
    fn default() -> Self {
        Rgba::new(1.0, 1.0, 1.0, 1.0)
    }
}

// ---------------------------------------------------------------- 网格

#[derive(Debug, Clone, Default)]
pub struct Mesh {
    pub positions: Vec<Vec3>,
    pub normals: Vec<Vec3>,
    /// 每三个一组
    pub indices: Vec<u32>,
}

impl Mesh {
    /// 单位立方体（边长 1，中心在原点）
    pub fn cube() -> Mesh {
        let p = [
            -0.5f32, -0.5, -0.5, 0.5, -0.5, -0.5, 0.5, 0.5, -0.5, -0.5, 0.5, -0.5, -0.5, -0.5,
            0.5, 0.5, -0.5, 0.5, 0.5, 0.5, 0.5, -0.5, 0.5, 0.5,
        ];
        let mut positions = Vec::new();
        for i in 0..8 {
            positions.push(Vec3::new(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]));
        }
        // 每面两个三角形
        let idx: [u32; 36] = [
            0, 1, 2, 0, 2, 3, // -Z
            5, 4, 7, 5, 7, 6, // +Z
            4, 0, 3, 4, 3, 7, // -X
            1, 5, 6, 1, 6, 2, // +X
            3, 2, 6, 3, 6, 7, // +Y
            4, 5, 1, 4, 1, 0, // -Y
        ];
        let mut m = Mesh {
            positions,
            normals: Vec::new(),
            indices: idx.to_vec(),
        };
        m.compute_normals();
        m
    }

    /// 低模球（经纬细分）
    pub fn sphere(segments: u32, rings: u32) -> Mesh {
        let (seg, ring) = (segments.max(3), rings.max(2));
        let mut positions = Vec::new();
        let mut indices = Vec::new();
        for r in 0..=ring {
            let v = r as f32 / ring as f32;
            let phi = v * std::f32::consts::PI;
            for s in 0..=seg {
                let u = s as f32 / seg as f32;
                let theta = u * std::f32::consts::TAU;
                positions.push(Vec3::new(
                    0.5 * phi.sin() * theta.cos(),
                    0.5 * phi.cos(),
                    0.5 * phi.sin() * theta.sin(),
                ));
            }
        }
        for r in 0..ring {
            for s in 0..seg {
                let a = r * (seg + 1) + s;
                let b = a + seg + 1;
                indices.extend_from_slice(&[a, b, a + 1, a + 1, b, b + 1]);
            }
        }
        let mut m = Mesh {
            positions,
            normals: Vec::new(),
            indices,
        };
        m.compute_normals();
        m
    }

    /// 地面平面（边长 1，XZ 平面）
    pub fn plane() -> Mesh {
        let positions = vec![
            Vec3::new(-0.5, 0.0, -0.5),
            Vec3::new(0.5, 0.0, -0.5),
            Vec3::new(0.5, 0.0, 0.5),
            Vec3::new(-0.5, 0.0, 0.5),
        ];
        let mut m = Mesh {
            positions,
            normals: Vec::new(),
            indices: vec![0, 1, 2, 0, 2, 3],
        };
        m.compute_normals();
        m
    }

    pub fn compute_normals(&mut self) {
        let mut normals = vec![Vec3::ZERO; self.positions.len()];
        for tri in self.indices.chunks_exact(3) {
            let (a, b, c) = (tri[0] as usize, tri[1] as usize, tri[2] as usize);
            if a >= self.positions.len() || b >= self.positions.len() || c >= self.positions.len() {
                continue;
            }
            let n = self.positions[b]
                .sub(self.positions[a])
                .cross(self.positions[c].sub(self.positions[a]));
            normals[a] = normals[a].add(n);
            normals[b] = normals[b].add(n);
            normals[c] = normals[c].add(n);
        }
        for n in normals.iter_mut() {
            *n = n.normalize();
        }
        self.normals = normals;
    }
}

// ---------------------------------------------------------------- 场景

#[derive(Debug, Clone)]
pub struct Object {
    pub name: String,
    pub mesh: Mesh,
    /// 位置 + 欧拉角（度）+ 缩放
    pub position: Vec3,
    pub rotation: Vec3,
    pub scale: Vec3,
    pub color: Rgba,
    pub visible: bool,
}

impl Object {
    pub fn new(name: &str, mesh: Mesh) -> Self {
        Object {
            name: name.to_string(),
            mesh,
            position: Vec3::ZERO,
            rotation: Vec3::ZERO,
            scale: Vec3::splat(1.0),
            color: Rgba::new(0.72, 0.78, 0.86, 1.0),
            visible: true,
        }
    }

    pub fn matrix(&self) -> Mat4 {
        let t = Mat4::translation(self.position);
        let r = Mat4::rotation_y(self.rotation.y.to_radians())
            .mul(&Mat4::rotation_x(self.rotation.x.to_radians()))
            .mul(&Mat4::rotation_z(self.rotation.z.to_radians()));
        let s = Mat4::scale(self.scale);
        t.mul(&r).mul(&s)
    }
}

#[derive(Debug, Clone)]
pub struct Camera {
    pub eye: Vec3,
    pub target: Vec3,
    pub fov_y: f32,
    pub near: f32,
    pub far: f32,
}

impl Default for Camera {
    fn default() -> Self {
        Camera {
            eye: Vec3::new(0.0, 2.5, 6.0),
            target: Vec3::new(0.0, 0.0, 0.0),
            fov_y: 50.0,
            near: 0.05,
            far: 200.0,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct Scene {
    pub objects: Vec<Object>,
    pub camera: Camera,
    pub bg: Option<Rgba>,
    /// 方向光方向（指向光的方向）
    pub light_dir: Vec3,
    pub ambient: f32,
}

impl Scene {
    pub fn new() -> Self {
        Scene {
            objects: Vec::new(),
            camera: Camera::default(),
            bg: Some(Rgba::new(0.06, 0.07, 0.09, 1.0)),
            light_dir: Vec3::new(-0.4, -1.0, -0.6).normalize(),
            ambient: 0.35,
        }
    }

    pub fn object(&self, name: &str) -> Option<&Object> {
        self.objects.iter().find(|o| o.name == name)
    }

    pub fn object_mut(&mut self, name: &str) -> Option<&mut Object> {
        self.objects.iter_mut().find(|o| o.name == name)
    }

    /// 没有就建一个；有就返回（脚本里 `add("box")` 很方便）
    pub fn add(&mut self, name: &str, kind: &str) -> &mut Object {
        if self.object(name).is_none() {
            let mesh = match kind {
                "plane" | "ground" => Mesh::plane(),
                "sphere" | "ball" => Mesh::sphere(16, 12),
                _ => Mesh::cube(),
            };
            self.objects.push(Object::new(name, mesh));
        }
        self.object_mut(name).unwrap()
    }

    pub fn remove(&mut self, name: &str) {
        self.objects.retain(|o| o.name != name);
    }

    pub fn clear(&mut self) {
        self.objects.clear();
    }

    pub fn to_json(&self) -> Json {
        let mut root = Json::obj();
        let mut objs = Json::arr();
        for o in &self.objects {
            let mut oj = Json::obj();
            oj.set("name", Json::s(o.name.clone()));
            oj.set("pos", Json::Arr(vec![
                Json::n(o.position.x as f64),
                Json::n(o.position.y as f64),
                Json::n(o.position.z as f64),
            ]));
            oj.set("rot", Json::Arr(vec![
                Json::n(o.rotation.x as f64),
                Json::n(o.rotation.y as f64),
                Json::n(o.rotation.z as f64),
            ]));
            oj.set("scale", Json::Arr(vec![
                Json::n(o.scale.x as f64),
                Json::n(o.scale.y as f64),
                Json::n(o.scale.z as f64),
            ]));
            oj.set("color", o.color.to_json());
            oj.set("triangles", Json::n((o.mesh.indices.len() / 3) as f64));
            objs.push(oj);
        }
        root.set("objects", objs);
        let mut cam = Json::obj();
        cam.set("eye", Json::Arr(vec![
            Json::n(self.camera.eye.x as f64),
            Json::n(self.camera.eye.y as f64),
            Json::n(self.camera.eye.z as f64),
        ]));
        root.set("camera", cam);
        root
    }
}

// ---------------------------------------------------------------- 光栅化

pub struct Frame {
    pub width: usize,
    pub height: usize,
    pub rgba: Vec<u8>,
}

impl Frame {
    pub fn pixel(&self, x: usize, y: usize) -> [u8; 4] {
        let i = (y * self.width + x) * 4;
        [self.rgba[i], self.rgba[i + 1], self.rgba[i + 2], self.rgba[i + 3]]
    }
}

pub struct Renderer {
    pub width: usize,
    pub height: usize,
    color: Vec<u8>,
    depth: Vec<f32>,
}

impl Renderer {
    pub fn new(width: usize, height: usize) -> Self {
        Renderer {
            width: width.max(1),
            height: height.max(1),
            color: vec![0; width * height * 4],
            depth: vec![f32::INFINITY; width * height],
        }
    }

    fn clear_buffer(&mut self, bg: Rgba) {
        let r = (bg.r * 255.0) as u8;
        let g = (bg.g * 255.0) as u8;
        let b = (bg.b * 255.0) as u8;
        for px in self.color.chunks_exact_mut(4) {
            px[0] = r;
            px[1] = g;
            px[2] = b;
            px[3] = 255;
        }
        self.depth.fill(f32::INFINITY);
    }

    /// 渲染一帧（纯软件：Z-buffer + 平面着色 + 简单环境光）
    pub fn render(&mut self, scene: &Scene) -> Frame {
        let bg = scene.bg.unwrap_or(Rgba::new(0.06, 0.07, 0.09, 1.0));
        self.clear_buffer(bg);

        let aspect = self.width as f32 / self.height as f32;
        let proj = Mat4::perspective(
            scene.camera.fov_y,
            aspect,
            scene.camera.near,
            scene.camera.far,
        );
        let view = Mat4::look_at(scene.camera.eye, scene.camera.target, Vec3::UP);
        let vp = proj.mul(&view);

        for obj in &scene.objects {
            if !obj.visible {
                continue;
            }
            let model = obj.matrix();
            let mvp = vp.mul(&model);

            // 顶点变换
            let n = obj.mesh.positions.len();
            let mut screen: Vec<(f32, f32, f32)> = Vec::with_capacity(n);
            let mut view_z: Vec<f32> = Vec::with_capacity(n);
            for p in &obj.mesh.positions {
                let (x, y, z, w) = mvp.transform_point(*p);
                if w.abs() < 1e-6 {
                    screen.push((f32::NAN, f32::NAN, f32::NAN));
                    view_z.push(f32::INFINITY);
                    continue;
                }
                let inv = 1.0 / w;
                let ndc_x = x * inv;
                let ndc_y = y * inv;
                let ndc_z = z * inv;
                screen.push((
                    (ndc_x * 0.5 + 0.5) * self.width as f32,
                    (1.0 - (ndc_y * 0.5 + 0.5)) * self.height as f32,
                    ndc_z,
                ));
                view_z.push(ndc_z);
            }

            // 面法线（世界空间）用于着色
            let rot_only = {
                let t = Mat4::translation(Vec3::ZERO);
                let r = Mat4::rotation_y(obj.rotation.y.to_radians())
                    .mul(&Mat4::rotation_x(obj.rotation.x.to_radians()))
                    .mul(&Mat4::rotation_z(obj.rotation.z.to_radians()));
                t.mul(&r)
            };

            for tri in obj.mesh.indices.chunks_exact(3) {
                let (ia, ib, ic) = (tri[0] as usize, tri[1] as usize, tri[2] as usize);
                if ia >= n || ib >= n || ic >= n {
                    continue;
                }
                let (a, b, c) = (screen[ia], screen[ib], screen[ic]);
                if a.0.is_nan() || b.0.is_nan() || c.0.is_nan() {
                    continue;
                }
                // 近平面粗筛
                if view_z[ia] < -1.0 && view_z[ib] < -1.0 && view_z[ic] < -1.0 {
                    continue;
                }

                // 世界空间法线
                let (wa, wb, wc) = (
                    obj.mesh.positions[ia],
                    obj.mesh.positions[ib],
                    obj.mesh.positions[ic],
                );
                let nrm = wb.sub(wa).cross(wc.sub(wa)).normalize();
                let (nx, ny, nz, _) = rot_only.transform_point(nrm);
                let world_n = Vec3::new(nx, ny, nz).normalize();
                // 双面：法线朝我们才亮，否则翻过来
                let shade_raw = -world_n.dot(scene.light_dir);
                let shade = if shade_raw < 0.0 { -shade_raw * 0.55 } else { shade_raw };
                let lit = (scene.ambient + (1.0 - scene.ambient) * shade).clamp(0.06, 1.4);
                let col = obj.color.scale(lit);

                self.fill_triangle(a, b, c, col);
            }
        }

        Frame {
            width: self.width,
            height: self.height,
            rgba: self.color.clone(),
        }
    }

    fn fill_triangle(&mut self, a: (f32, f32, f32), b: (f32, f32, f32), c: (f32, f32, f32), col: Rgba) {
        let area = (b.0 - a.0) * (c.1 - a.1) - (b.1 - a.1) * (c.0 - a.0);
        if area.abs() < 1e-6 {
            return;
        }
        let min_x = a.0.min(b.0).min(c.0).floor().max(0.0) as i32;
        let max_x = a.0.max(b.0).max(c.0).ceil().min(self.width as f32 - 1.0) as i32;
        let min_y = a.1.min(b.1).min(c.1).floor().max(0.0) as i32;
        let max_y = a.1.max(b.1).max(c.1).ceil().min(self.height as f32 - 1.0) as i32;
        if max_x < min_x || max_y < min_y {
            return;
        }
        let r = (col.r.clamp(0.0, 1.0) * 255.0) as u8;
        let g = (col.g.clamp(0.0, 1.0) * 255.0) as u8;
        let bl = (col.b.clamp(0.0, 1.0) * 255.0) as u8;

        for y in min_y..=max_y {
            for x in min_x..=max_x {
                let px = x as f32 + 0.5;
                let py = y as f32 + 0.5;
                let w0 = ((b.0 - px) * (c.1 - py) - (b.1 - py) * (c.0 - px)) / area;
                let w1 = ((c.0 - px) * (a.1 - py) - (c.1 - py) * (a.0 - px)) / area;
                let w2 = 1.0 - w0 - w1;
                if w0 < 0.0 || w1 < 0.0 || w2 < 0.0 {
                    continue;
                }
                let z = w0 * a.2 + w1 * b.2 + w2 * c.2;
                let idx = y as usize * self.width + x as usize;
                if z < self.depth[idx] {
                    self.depth[idx] = z;
                    let o = idx * 4;
                    self.color[o] = r;
                    self.color[o + 1] = g;
                    self.color[o + 2] = bl;
                    self.color[o + 3] = 255;
                }
            }
        }
    }
}

// ---------------------------------------------------------------- PNG 输出

fn adler32(data: &[u8]) -> u32 {
    let (mut a, mut b) = (1u32, 0u32);
    for &byte in data {
        a = (a + byte as u32) % 65521;
        b = (b + a) % 65521;
    }
    (b << 16) | a
}

/// 把帧编码成 PNG（8-bit RGBA，无滤波）
pub fn encode_png(frame: &Frame) -> Vec<u8> {
    let mut raw: Vec<u8> = Vec::with_capacity(frame.height * (frame.width * 4 + 1));
    for y in 0..frame.height {
        raw.push(0); // filter: none
        let start = y * frame.width * 4;
        raw.extend_from_slice(&frame.rgba[start..start + frame.width * 4]);
    }
    let compressed = crate::gal::deflate_bytes(&raw).unwrap_or_default();

    let mut out: Vec<u8> = Vec::new();
    out.extend_from_slice(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&(frame.width as u32).to_be_bytes());
    ihdr.extend_from_slice(&(frame.height as u32).to_be_bytes());
    ihdr.extend_from_slice(&[8, 6, 0, 0, 0]); // 8bit / RGBA / deflate / no filter / no interlace
    write_chunk(&mut out, b"IHDR", &ihdr);
    // zlib 包装：0x78 0x01 + deflate + adler32
    let mut z = vec![0x78, 0x01];
    z.extend_from_slice(&compressed);
    z.extend_from_slice(&adler32(&raw).to_be_bytes());
    write_chunk(&mut out, b"IDAT", &z);
    write_chunk(&mut out, b"IEND", &[]);
    out
}

fn write_chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    let mut body = Vec::with_capacity(4 + data.len());
    body.extend_from_slice(kind);
    body.extend_from_slice(data);
    out.extend_from_slice(&body);
    out.extend_from_slice(&crc32_bytes(&body).to_be_bytes());
}

fn crc32_bytes(data: &[u8]) -> u32 {
    let mut c = 0xFFFF_FFFFu32;
    for &b in data {
        c ^= b as u32;
        for _ in 0..8 {
            c = if c & 1 != 0 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 };
        }
    }
    c ^ 0xFFFF_FFFF
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn math_basics() {
        let m = Mat4::translation(Vec3::new(1.0, 2.0, 3.0));
        let (x, y, z, w) = m.transform_point(Vec3::new(0.0, 0.0, 0.0));
        assert!((x - 1.0).abs() < 1e-6 && (y - 2.0).abs() < 1e-6 && (z - 3.0).abs() < 1e-6);
        assert!((w - 1.0).abs() < 1e-6);

        let p = Mat4::perspective(50.0, 1.0, 0.1, 100.0);
        let (_, _, _, w2) = p.transform_point(Vec3::new(0.0, 0.0, -5.0));
        assert!(w2 > 0.0, "相机前方 w 应为正，实际 {}", w2);
    }

    #[test]
    fn cube_has_12_triangles() {
        let m = Mesh::cube();
        assert_eq!(m.indices.len() / 3, 12);
        assert_eq!(m.normals.len(), m.positions.len());
    }

    #[test]
    fn renders_a_cube_center_pixel() {
        let mut scene = Scene::new();
        scene.camera.eye = Vec3::new(0.0, 0.0, 3.0);
        scene.camera.target = Vec3::ZERO;
        let o = scene.add("box", "cube");
        o.color = Rgba::new(0.9, 0.5, 0.3, 1.0);

        let mut r = Renderer::new(96, 96);
        let frame = r.render(&scene);
        // 中心像素应该是物体颜色，不是背景
        let px = frame.pixel(48, 48);
        assert!(px[0] > 100, "中心应被立方体覆盖，实际 {:?}", px);
    }

    #[test]
    fn png_has_signature_and_chunks() {
        let mut scene = Scene::new();
        scene.add("box", "cube");
        let mut r = Renderer::new(32, 32);
        let frame = r.render(&scene);
        let png = encode_png(&frame);
        assert_eq!(&png[0..8], &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]);
        assert!(png.windows(4).any(|w| w == b"IDAT"));
        assert!(png.windows(4).any(|w| w == b"IEND"));
    }

    #[test]
    fn depth_hides_back_object() {
        let mut scene = Scene::new();
        scene.camera.eye = Vec3::new(0.0, 0.0, 3.0);
        scene.camera.target = Vec3::ZERO;
        let far = scene.add("far", "cube");
        far.position = Vec3::new(0.0, 0.0, -2.0);
        far.color = Rgba::new(1.0, 0.0, 0.0, 1.0);
        let near = scene.add("near", "cube");
        near.color = Rgba::new(0.0, 1.0, 0.0, 1.0);

        let mut r = Renderer::new(64, 64);
        let frame = r.render(&scene);
        let px = frame.pixel(32, 32);
        assert!(px[1] > px[0], "近处的绿块应盖住远处的红块，实际 {:?}", px);
    }
}