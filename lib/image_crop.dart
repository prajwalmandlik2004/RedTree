import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image/image.dart' as img;

class ImageCropScreen extends StatefulWidget {
  final File imageFile;

  const ImageCropScreen({super.key, required this.imageFile});

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final GlobalKey<ExtendedImageEditorState> editorKey = GlobalKey();

  Future<void> _cropAndSave() async {
    final state = editorKey.currentState;
    if (state == null) return;

    final cropRect = state.getCropRect();
    final action = state.editAction;

    if (cropRect == null || cropRect.width == 0 || cropRect.height == 0) {
      Fluttertoast.showToast(msg: "Invalid crop area");
      return;
    }

    final Uint8List rawBytes = await widget.imageFile.readAsBytes();
    img.Image? image = img.decodeImage(rawBytes);
    if (image == null) {
      Fluttertoast.showToast(msg: "Failed to decode image");
      return;
    }

    // Rotate if needed
    // final int angle = action?.rotateAngle.toInt() ?? 0;
    // if (angle != 0) {
    //   image = img.copyRotate(image, angle);
    // }

    // Flip
    // if (action?.flipX == true) image = img.flipHorizontal(image);
    if (action?.flipY == true) image = img.flipVertical(image);

    // Clamp crop region
    final int left = cropRect.left.round().clamp(0, image.width - 1);
    final int top = cropRect.top.round().clamp(0, image.height - 1);
    final int width = cropRect.width.round().clamp(1, image.width - left);
    final int height = cropRect.height.round().clamp(1, image.height - top);

    try {
      final cropped = img.copyCrop(
        image,
        x: left,
        y: top,
        width: width,
        height: height,
      );

      final resultBytes = Uint8List.fromList(img.encodeJpg(cropped));

      await widget.imageFile.writeAsBytes(resultBytes);

      Fluttertoast.showToast(msg: "Image cropped successfully");

      if (context.mounted) Navigator.pop(context, true);
    } catch (e) {
      Fluttertoast.showToast(msg: "Crop failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Crop Image"),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _cropAndSave,
          ),
        ],
      ),
      body: Center(
        child: ExtendedImage.file(
          widget.imageFile,
          fit: BoxFit.contain,
          mode: ExtendedImageMode.editor,
          extendedImageEditorKey: editorKey,
          // initEditorConfigHandler: (state) {
          //   return EditorConfig(
          //     maxScale: 8.0,
          //     cropAspectRatio: 1.0,
          //     hitTestSize: 20.0,
          //     cropRectPadding: const EdgeInsets.all(20.0),
          //     cropLayerPainter: const EditorCropLayerPainter(),
          //   );
          // },
            initEditorConfigHandler: (state) {
              return EditorConfig(
                maxScale: 8.0,
                cropAspectRatio: null, // null means freeform
                hitTestSize: 20.0,
                cropRectPadding: EdgeInsets.zero,
                initCropRectType: InitCropRectType.imageRect, // ✅ use full image
                cropLayerPainter: const EditorCropLayerPainter(),
              );
            }

        ),
      ),
    );
  }
}
