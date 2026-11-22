//! 渲染一张 3D 场景图（验证 3D 后端可用）
use galatea_core::scene3d::{encode_png, Rgba, Renderer, Scene, Vec3};

fn main() {
    let mut scene = Scene::new();
    scene.bg = Some(Rgba::hex("#0B0D12"));
    scene.camera.eye = Vec3::new(3.6, 2.8, 5.2);
    scene.camera.target = Vec3::new(0.0, 0.6, 0.0);
    scene.camera.fov_y = 46.0;

    // 地面
    let g = scene.add("ground", "plane");
    g.scale = Vec3::new(9.0, 1.0, 9.0);
    g.position = Vec3::new(0.0, 0.0, 0.0);
    g.color = Rgba::hex("#1B2029");

    // 三个方块：主 / 脚本 / 未完成
    let a = scene.add("main", "cube");
    a.position = Vec3::new(-1.4, 0.5, 0.0);
    a.rotation = Vec3::new(0.0, 25.0, 0.0);
    a.color = Rgba::hex("#E8E8E8");

    let b = scene.add("script", "cube");
    b.position = Vec3::new(0.2, 0.42, -0.6);
    b.rotation = Vec3::new(0.0, -30.0, 12.0);
    b.scale = Vec3::new(0.85, 0.85, 0.85);
    b.color = Rgba::hex("#E4032E");

    let c = scene.add("todo", "sphere");
    c.position = Vec3::new(1.5, 0.55, 0.3);
    c.scale = Vec3::new(0.9, 0.9, 0.9);
    c.color = Rgba::hex("#7BE3CB");

    let mut r = Renderer::new(640, 360);
    let frame = r.render(&scene);
    std::fs::write("/workspace/render3d.png", encode_png(&frame)).unwrap();
    println!("✓ /workspace/render3d.png  {}×{}", frame.width, frame.height);
    println!("场景: {}", scene.to_json().to_pretty());
}
