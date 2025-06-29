import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

/// Custom painter to draw bounding boxes and labels for detected objects.
class ObjectDetectorPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize; // Size of the image frame from the camera
  final CameraLensDirection cameraLensDirection; // Direction of the camera lens

  ObjectDetectorPainter(this.objects, this.imageSize, this.cameraLensDirection);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = Colors.red; // Color for bounding boxes

    final TextPainter textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    const TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14.0,
      fontWeight: FontWeight.bold,
    );

    // Calculate scaling factors to map image coordinates to canvas coordinates.
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    for (DetectedObject object in objects) {
      // Adjust bounding box coordinates based on camera lens direction (mirroring for front camera).
      final Rect scaledRect = Rect.fromLTRB(
        cameraLensDirection == CameraLensDirection.front
            ? size.width - (object.boundingBox.right * scaleX)
            : object.boundingBox.left * scaleX,
        object.boundingBox.top * scaleY,
        cameraLensDirection == CameraLensDirection.front
            ? size.width - (object.boundingBox.left * scaleX)
            : object.boundingBox.right * scaleX,
        object.boundingBox.bottom * scaleY,
      );

      canvas.drawRect(scaledRect, paint); // Draw the bounding box

      // Prepare the label text for the detected object.
      final label =
          object.labels.isNotEmpty
              ? "${object.labels.first.text} (${(object.labels.first.confidence * 100).toStringAsFixed(1)}%)"
              : "Unknown";

      textPainter.text = TextSpan(text: label, style: textStyle);
      textPainter.layout(); // Layout the text to get its size

      // Draw a black background for the text for better readability.
      final backgroundPaint = Paint()..color = Colors.black54;
      final textRect = Rect.fromLTWH(
        scaledRect.left,
        scaledRect.top -
            textPainter.height -
            5, // Position above the bounding box
        textPainter.width + 10, // Add padding to text width
        textPainter.height + 5, // Add padding to text height
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(textRect, const Radius.circular(5)),
        backgroundPaint,
      );

      // Paint the text label.
      textPainter.paint(
        canvas,
        Offset(scaledRect.left + 5, scaledRect.top - textPainter.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
