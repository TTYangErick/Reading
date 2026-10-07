import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'style.dart';

/// Keep decoded image memory bounded even when the original is very large.
Future<Size?> imageDecodeSize(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) return null;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width, height = descriptor.height;
    if (width <= 0 || height <= 0) return null;
    return boundedImageDecodeSize(Size(width.toDouble(), height.toDouble()));
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Size boundedImageDecodeSize(Size size) {
  final scale = math.min(
    1.0,
    math.min(
      4096 / math.max(size.width, size.height),
      math.sqrt(8 * 1024 * 1024 / (size.width * size.height)),
    ),
  );
  return Size(
    math.max(1, (size.width * scale).floor()).toDouble(),
    math.max(1, (size.height * scale).floor()).toDouble(),
  );
}

class ReaderImageViewer extends StatefulWidget {
  final Uint8List bytes;
  final String description;
  final ReaderPalette palette;
  const ReaderImageViewer({
    super.key,
    required this.bytes,
    required this.description,
    required this.palette,
  });
  @override
  State<ReaderImageViewer> createState() => _ReaderImageViewerState();
}

class _ReaderImageViewerState extends State<ReaderImageViewer> {
  final transform = TransformationController();
  late final dimensions = imageDecodeSize(widget.bytes);
  Size viewport = Size.zero;
  Offset? doubleTapPoint;

  void zoom(double factor, [Offset? focus]) {
    final scale = (transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      5.0,
    );
    if (scale == 1) {
      transform.value = Matrix4.identity();
      return;
    }
    final point = focus ?? viewport.center(Offset.zero);
    final scene = transform.toScene(point);
    transform.value = Matrix4.identity()
      ..translateByDouble(
        point.dx - scene.dx * scale,
        point.dy - scene.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: widget.palette.background,
    body: SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('close-image'),
                tooltip: '关闭图片',
                color: widget.palette.ink,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Text('图片', style: TextStyle(color: widget.palette.ink)),
              ),
              IconButton(
                tooltip: '缩小',
                color: widget.palette.ink,
                onPressed: () => zoom(1 / 1.5),
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                tooltip: '放大',
                color: widget.palette.ink,
                onPressed: () => zoom(1.5),
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: '还原图片',
                color: widget.palette.ink,
                onPressed: () => transform.value = Matrix4.identity(),
                icon: const Icon(Icons.fit_screen),
              ),
            ],
          ),
          Expanded(
            child: FutureBuilder<Size?>(
              future: dimensions,
              builder: (_, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final size = snapshot.data;
                if (size == null) {
                  return Center(
                    child: Text(
                      '图片无法显示',
                      style: TextStyle(color: widget.palette.ink),
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (_, constraints) {
                    final next = constraints.biggest;
                    if (viewport != Size.zero && viewport != next) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) transform.value = Matrix4.identity();
                      });
                    }
                    viewport = next;
                    return GestureDetector(
                      onDoubleTapDown: (details) =>
                          doubleTapPoint = details.localPosition,
                      onDoubleTap: () {
                        if (transform.value.getMaxScaleOnAxis() > 1) {
                          transform.value = Matrix4.identity();
                        } else {
                          zoom(2.5, doubleTapPoint);
                        }
                      },
                      child: InteractiveViewer(
                        transformationController: transform,
                        minScale: 1,
                        maxScale: 5,
                        child: SizedBox.expand(
                          child: Image.memory(
                            widget.bytes,
                            fit: BoxFit.contain,
                            cacheWidth: size.width.toInt(),
                            cacheHeight: size.height.toInt(),
                            semanticLabel: widget.description,
                            errorBuilder: (_, error, stack) => Center(
                              child: Text(
                                '图片无法显示',
                                style: TextStyle(color: widget.palette.ink),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Text(
              '双指缩放 · 放大后拖动 · 双击还原或放大',
              style: TextStyle(
                fontSize: 12,
                color: widget.palette.ink.withValues(alpha: .6),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
