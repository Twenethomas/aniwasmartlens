// lib/core/services/yolo_object_detection_service.dart
import 'dart:typed_data';
import 'dart:ui'; // For Rect, Size
import 'dart:math'; // For max and min in NMS

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img_lib; // Correctly aliased 'image' package
import 'package:logger/logger.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// Define a simple class to hold detection results, similar to ML Kit's DetectedObject
class CustomDetectedObject {
  final Rect boundingBox;
  final String label;
  final double confidence;

  CustomDetectedObject({
    required this.boundingBox,
    required this.label,
    required this.confidence,
  });

  @override
  String toString() {
    return 'Object: $label, Confidence: ${confidence.toStringAsFixed(2)}, BoundingBox: $boundingBox';
  }
}

class YoloObjectDetectionService {
  late final Interpreter _interpreter;
  final Logger _logger = Logger();
  List<String> _labels = []; // Labels for your model

  final String _modelPath;
  final String _labelsPath;
  final int _inputSize = 640; // Common input size for YOLOv8 (e.g., 640x640)
  final double _confidenceThreshold = 0.25; // Minimum confidence to consider a detection
  final double _iouThreshold = 0.45; // IoU (Intersection over Union) threshold for NMS

  YoloObjectDetectionService({
    String modelPath = 'assets/ml/yolov8n_float16.tflite', // Default model path
    String labelsPath = 'assets/ml/coco_label.txt',      // Default labels path
  })  : _modelPath = modelPath, // Assign to internal private field
        _labelsPath = labelsPath; // Assign to internal private field


  Future<void> init() async {
    _logger.i("Initializing YoloObjectDetectionService...");
    try {
      // Load model from assets
      _interpreter = await Interpreter.fromAsset(_modelPath);
      _logger.i('Model loaded: $_modelPath');

      // Load labels from assets
      String labelsData = await rootBundle.loadString(_labelsPath);
      _labels = labelsData.split('\n').where((s) => s.isNotEmpty).toList();
      _logger.i('Labels loaded. Total labels: ${_labels.length}');

      _logger.i('Input Shape: ${_interpreter.getInputTensor(0).shape}');
      _logger.i('Output Shape: ${_interpreter.getOutputTensor(0).shape}');
      _logger.i("YoloObjectDetectionService initialized.");
    } catch (e) {
      _logger.e("Error initializing YoloObjectDetectionService: $e");
      rethrow; // Re-throw to propagate error
    }
  }

  // This method processes raw camera image bytes for object detection
  Future<List<CustomDetectedObject>> detectObjects(Uint8List imageBytes, int imageWidth, int imageHeight) async {
    // 1. Pre-process the image
    img_lib.Image? originalImage = img_lib.decodeImage(imageBytes);
    if (originalImage == null) {
      _logger.e("Failed to decode image bytes.");
      return [];
    }

    // Resize image to model input size
    img_lib.Image resizedImage = img_lib.copyResize(originalImage, width: _inputSize, height: _inputSize);

    // Convert resized image to a ByteBuffer for model input (normalize to [0, 1])
    // Assuming float16 model input (which tflite_flutter handles as float32 in dart, then converts).
    var input = Float32List(1 * _inputSize * _inputSize * 3); // 1 (batch) * H * W * C
    int pixelIndex = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = resizedImage.getPixel(x, y); // Get the ARGB integer pixel value

        // CORRECTED: Extract R, G, B components using bitwise operations
        // The image.Image.getPixel() returns a 32-bit ARGB integer.
        // Alpha is bits 24-31, Red 16-23, Green 8-15, Blue 0-7.
        int red = pixel.r.toInt();
        int green = pixel.g.toInt();
        int blue = pixel.b.toInt();

        input[pixelIndex++] = red / 255.0;
        input[pixelIndex++] = green / 255.0;
        input[pixelIndex++] = blue / 255.0;
      }
    }
    // Reshape to model's expected input shape (e.g., [1, 640, 640, 3])
    var inputTensor = input.reshape([1, _inputSize, _inputSize, 3]);


    // 2. Run inference
    // Output tensor shape example for YOLOv8 with 80 classes: [1, 84, 8400] (for 640x640 input)
    // 84 = 4 (bbox: x, y, w, h) + 80 (class scores)
    // 8400 = number of anchors * grid cells
    var output = List.filled(_interpreter.getOutputTensor(0).shape.reduce((a, b) => a * b), 0.0)
        .reshape(_interpreter.getOutputTensor(0).shape);

    _interpreter.run(inputTensor, output);

    // 3. Post-process the output
    List<CustomDetectedObject> detections = _processYoloOutput(output, originalImage.width, originalImage.height);

    return detections;
  }

  // Processes the raw YOLO model output to extract detected objects
  List<CustomDetectedObject> _processYoloOutput(dynamic output, int originalWidth, int originalHeight) {
    // Assuming YOLOv8 output format: [1, 84, N_boxes] where N_boxes is usually 8400 for 640x640 input
    // 84 means 4 for bbox (cx, cy, w, h) and 80 for class scores.
    // The output array is a Float32List, which is usually flattened
    // So, we need to access it carefully based on the shape.
    final rawOutput = output[0]; // Access the first (and only) batch
    // final int numFeatures = rawOutput.shape[0]; // This would be 84
    final int numBoxes = rawOutput.shape[1]; // This would be 8400

    List<CustomDetectedObject> candidates = [];
    int numClasses = _labels.length; // Typically 80 for COCO

    for (int i = 0; i < numBoxes; i++) {
      // Extract bounding box coordinates (cx, cy, width, height)
      double cx = rawOutput[0][i]; // Row 0 for x_center
      double cy = rawOutput[1][i]; // Row 1 for y_center
      double w = rawOutput[2][i];  // Row 2 for width
      double h = rawOutput[3][i];  // Row 3 for height

      // Find the class with the highest confidence
      double maxConfidence = 0.0;
      int classId = -1;
      for (int j = 0; j < numClasses; j++) {
        // Class scores start from index 4
        double confidence = rawOutput[4 + j][i];
        if (confidence > maxConfidence) {
          maxConfidence = confidence;
          classId = j;
        }
      }

      if (maxConfidence >= _confidenceThreshold && classId != -1) {
        String label = (classId < _labels.length) ? _labels[classId] : 'unknown';

        // Convert normalized (0-1) YOLO box coords to pixel coords relative to original image size
        // cx, cy, w, h are relative to the input_size (640)
        // Convert to x1, y1, x2, y2 format relative to original image dimensions
        double x1 = (cx - w / 2) * originalWidth / _inputSize;
        double y1 = (cy - h / 2) * originalHeight / _inputSize;
        double x2 = (cx + w / 2) * originalWidth / _inputSize;
        double y2 = (cy + h / 2) * originalHeight / _inputSize;

        // Ensure coordinates are within image bounds
        x1 = x1.clamp(0.0, originalWidth.toDouble());
        y1 = y1.clamp(0.0, originalHeight.toDouble());
        x2 = x2.clamp(0.0, originalWidth.toDouble());
        y2 = y2.clamp(0.0, originalHeight.toDouble());

        candidates.add(
          CustomDetectedObject(
            boundingBox: Rect.fromLTRB(x1, y1, x2, y2),
            label: label,
            confidence: maxConfidence,
          ),
        );
      }
    }

    // Apply Non-Maximum Suppression (NMS) to remove overlapping boxes
    return _applyNMS(candidates, _iouThreshold);
  }

  // Non-Maximum Suppression (NMS) implementation
  List<CustomDetectedObject> _applyNMS(List<CustomDetectedObject> boxes, double iouThreshold) {
    if (boxes.isEmpty) return [];

    // Sort by confidence descending
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));

    List<bool> suppressed = List.filled(boxes.length, false);
    List<CustomDetectedObject> result = [];

    for (int i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;

      result.add(boxes[i]);

      for (int j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;

        if (boxes[i].label == boxes[j].label) { // Only suppress if same class
          double iou = _calculateIoU(boxes[i].boundingBox, boxes[j].boundingBox);
          if (iou > iouThreshold) {
            suppressed[j] = true;
          }
        }
      }
    }
    return result;
  }

  // Calculates Intersection over Union (IoU) between two bounding boxes
  double _calculateIoU(Rect box1, Rect box2) {
    double xA = max(box1.left, box2.left);
    double yA = max(box1.top, box2.top);
    double xB = min(box1.right, box2.right);
    double yB = min(box1.bottom, box2.bottom);

    double interWidth = max(0.0, xB - xA);
    double interHeight = max(0.0, yB - yA);

    double interArea = interWidth * interHeight;

    double box1Area = box1.width * box1.height;
    double box2Area = box2.width * box2.height;

    double iou = interArea / (box1Area + box2Area - interArea);
    return iou;
  }

  void dispose() {
    _interpreter.close();
    _logger.i("YoloObjectDetectionService disposed.");
  }
}