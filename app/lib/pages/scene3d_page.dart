/// 3D 预览页 —— 验证「Flutter 独占显示 + Rust 渲染」这条链路。
///
/// 书柜右上角的立方体按钮进来。左边是 3D 场景（软件光栅），
/// 右边是同一份数据的状态显示，用来证明"显示层只有一个"。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/ffi3d.dart';
import '../theme.dart';

class Scene3DPage extends StatefulWidget {
  const Scene3DPage({super.key});

  @override
  State<Scene3DPage> createState() => _Scene3DPageState();
}

class _Scene3DPageState extends State<Scene3DPage> {
  double _t = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GColors.bg,
      appBar: AppBar(
        title: const Text('3D 预览'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text(
                Gal3D.available ? 'RUST RASTER' : 'NO NATIVE LIB',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.2,
                  fontFamily: 'monospace',
                  color: Gal3D.available ? GColors.accent : GColors.err,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                child: Scene3DView(
                  width: 480,
                  height: 270,
                  onFrame: (e, t) {
                    _t = t;
                    // 用剧情里的三种节点当三个物体
                    e.setRotation('main', 0, t * 38, 0);
                    e.setRotation('script', 0, -t * 56, 12);
                    e.setPosition(
                        'todo',
                        math.sin(t) * 0.5 + 1.5,
                        0.55 + math.sin(t * 2) * 0.08,
                        0.3);
                    e.setCamera(
                      3.2 + math.sin(t * 0.4) * 0.5,
                      2.4,
                      5.0,
                      0,
                      0.6,
                      0,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: GColors.paper,
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                border: Border.all(color: GColors.lineLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('同一条链路上的三层',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: GColors.textStrong)),
                  const SizedBox(height: 8),
                  _row('Godot（headless）', '只跑逻辑：场景 / 物理 / GDScript', GColors.dim),
                  _row('galatea-3d（Rust）', '场景图 → 三角形 → RGBA', GColors.accent),
                  _row('Flutter', '唯一显示层：RawImage', GColors.text),
                  const SizedBox(height: 10),
                  Text('t = ${_t.toStringAsFixed(2)}s · 480×270（拉伸显示）',
                      style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: GColors.dim)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String a, String b, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 3,
              height: 13,
              margin: const EdgeInsets.only(top: 2, right: 8),
              color: color),
          SizedBox(
              width: 128,
              child: Text(a,
                  style: const TextStyle(
                      fontSize: 11, color: GColors.textStrong))),
          Expanded(
              child: Text(b,
                  style: const TextStyle(fontSize: 11, color: GColors.dim))),
        ],
      ),
    );
  }
}
