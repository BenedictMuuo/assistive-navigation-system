import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Turns one camera frame into the input the model expects.
///
/// The model takes a 224 x 224 RGB image with raw 0-255 pixel values.
/// MobileNetV3 does its own scaling inside, so the values must NOT be
/// divided by 255 here, or the image is scaled twice and accuracy collapses.
///
/// Android cameras deliver frames in YUV420 format, usually rotated 90
/// degrees from upright. Rather than converting the whole frame to RGB and
/// then resizing, this samples straight into the 224 x 224 output, rotating
/// and centre-cropping as it goes. That is roughly 50,000 pixel lookups
/// instead of 300,000 or more, which keeps it fast enough for the UI thread.
class ImageConverter {
  static const int size = 224;

  /// Converts [image] to a flat Float32List of length 224 * 224 * 3.
  ///
  /// [rotation] is the camera's sensor orientation in degrees: 0, 90, 180
  /// or 270. It is used to turn the frame upright.
  static Float32List toModelInput(CameraImage image, int rotation) {
    if (image.planes.length < 3) {
      throw UnsupportedError(
        'Expected a YUV420 frame with 3 planes, got ${image.planes.length}. '
        'Make sure the camera uses ImageFormatGroup.yuv420.',
      );
    }

    final int w = image.width;
    final int h = image.height;

    final Plane yPlane = image.planes[0];
    final Plane uPlane = image.planes[1];
    final Plane vPlane = image.planes[2];

    final Uint8List yBytes = yPlane.bytes;
    final Uint8List uBytes = uPlane.bytes;
    final Uint8List vBytes = vPlane.bytes;

    final int yRowStride = yPlane.bytesPerRow;
    final int uvRowStride = uPlane.bytesPerRow;
    // U and V samples may be packed side by side (stride 2) or separate (1).
    final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

    // Size of the frame after it has been turned upright.
    final bool sideways = rotation == 90 || rotation == 270;
    final int uprightW = sideways ? h : w;
    final int uprightH = sideways ? w : h;

    // Take the largest centred square, so objects are not stretched.
    final int side = uprightW < uprightH ? uprightW : uprightH;
    final int cropX = (uprightW - side) ~/ 2;
    final int cropY = (uprightH - side) ~/ 2;
    final double step = side / size;

    final Float32List out = Float32List(size * size * 3);
    int o = 0;

    for (int oy = 0; oy < size; oy++) {
      final int ry = cropY + (oy * step).floor();

      for (int ox = 0; ox < size; ox++) {
        final int rx = cropX + (ox * step).floor();

        // Map the upright position back to where it sits in the raw frame.
        int sx;
        int sy;
        switch (rotation) {
          case 90:
            sx = ry;
            sy = h - 1 - rx;
            break;
          case 180:
            sx = w - 1 - rx;
            sy = h - 1 - ry;
            break;
          case 270:
            sx = w - 1 - ry;
            sy = rx;
            break;
          default:
            sx = rx;
            sy = ry;
        }

        final int yValue = yBytes[sy * yRowStride + sx];
        final int uvIndex = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;
        final int u = uBytes[uvIndex] - 128;
        final int v = vBytes[uvIndex] - 128;

        double r = yValue + 1.402 * v;
        double g = yValue - 0.344136 * u - 0.714136 * v;
        double b = yValue + 1.772 * u;

        out[o++] = r < 0 ? 0.0 : (r > 255 ? 255.0 : r);
        out[o++] = g < 0 ? 0.0 : (g > 255 ? 255.0 : g);
        out[o++] = b < 0 ? 0.0 : (b > 255 ? 255.0 : b);
      }
    }

    return out;
  }
}
