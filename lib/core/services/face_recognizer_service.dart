// lib/core/services/face_recognizer_service.dart
import 'dart:io'; // For File
import 'dart:typed_data'; // For Uint8List, Float32List
import 'dart:math'; // For sqrt, pow
import 'dart:ui';

import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img_lib; // Alias for the 'image' package
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'; // For Face object
import 'package:assist_lens/core/services/face_database_helper.dart'; // Import Database Helper
import 'package:logger/logger.dart'; // Import logger

// This class handles loading and running the TFLite model for face recognition,
// as well as basic in-memory storage for known faces and recognition logic.
class FaceRecognizerService {
  Interpreter? _interpreter;
  // MobileFaceNet typically expects 112x112 input image
  final int _inputImageSize = 112;
  final Logger _logger = Logger();
  late final FaceDatabaseHelper _faceDatabaseHelper; // Database helper instance

  // In-memory storage for known faces: Map of name to their embedding
  final Map<String, Float32List> _knownFaces = {};

  // Public getter for known faces (read-only copy)
  Map<String, Float32List> get knownFaces => Map.unmodifiable(_knownFaces);

  // Threshold for recognizing faces. Lower values mean stricter match.
  // This value often needs empirical tuning for your specific model and dataset.
  // For MobileFaceNet, a distance below 1.0-1.2 is often considered a match.
  double recognitionThreshold =
      1.0; // Make this tunable, start with a more permissive value

  // Helper function to rotate img_lib.Image
  img_lib.Image _rotateImage(img_lib.Image image, InputImageRotation rotation) {
    switch (rotation) {
      case InputImageRotation.rotation0deg:
        return image;
      case InputImageRotation.rotation90deg:
        return img_lib.copyRotate(image, angle: 90);
      case InputImageRotation.rotation180deg:
        return img_lib.copyRotate(image, angle: 180);
      case InputImageRotation.rotation270deg:
        return img_lib.copyRotate(image, angle: 270);
    }
  }

  // Private constructor for singleton pattern
  FaceRecognizerService._privateConstructor(this._faceDatabaseHelper) {
    _initializeService();
  }

  // Singleton instance
  static FaceRecognizerService? _instance;

  // Factory constructor to return the singleton instance
  factory FaceRecognizerService({FaceDatabaseHelper? faceDatabaseHelper}) {
    // Ensure _faceDatabaseHelper is initialized if not already
    _instance ??= FaceRecognizerService._privateConstructor(
      faceDatabaseHelper ?? FaceDatabaseHelper(),
    );
    return _instance!;
  }

  /// Loads the MobileFaceNet TFLite model from assets.
  Future<void> loadModel() async {
    if (_interpreter != null) {
      _logger.i('FaceRecognizerService: Model already loaded.');
      return;
    }
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/ml/mobile_face_net.tflite', // Ensure this path is correct in your pubspec.yaml
      );
      _logger.i(
        'FaceRecognizerService: MobileFaceNet model loaded successfully.',
      );
    } catch (e) {
      _logger.e(
        'FaceRecognizerService: Failed to load MobileFaceNet model: $e',
      );
    }
  }

  /// Initializes the service by loading the model and known faces from DB.
  Future<void> _initializeService() async {
    await loadModel();
    await loadFacesFromDatabase();
  }

  /// Extracts face embedding from an InputImage given a detected face bounding box.
  /// Preprocesses the image (crop, resize, normalize) for model input.
  Future<Float32List?> getFaceEmbedding(
    InputImage inputImage,
    Face face,
  ) async {
    if (_interpreter == null) {
      _logger.w(
        'FaceRecognizerService: Model not loaded yet. Cannot get embedding.',
      );
      return null;
    }

    img_lib.Image? rawImage; // Image in its original orientation from bytes

    // 1. Convert InputImage data to img_lib.Image
    if (inputImage.filePath != null) {
      final fileBytes = await File(inputImage.filePath!).readAsBytes();
      rawImage = img_lib.decodeImage(fileBytes);
    } else if (inputImage.bytes != null && inputImage.metadata != null) {
      final metadata = inputImage.metadata!;
      if (metadata.format == InputImageFormat.bgra8888) {
        // iOS BGRA8888 (already in RGB-like format)
        rawImage = img_lib.Image.fromBytes(
          width: metadata.size.width.toInt(),
          height: metadata.size.height.toInt(),
          bytes:
              inputImage
                  .bytes!
                  .buffer, // This was 'originalImage', corrected to rawImage
          order: img_lib.ChannelOrder.bgra,
        );
      } else if (metadata.format == InputImageFormat.nv21) {
        rawImage = _convertNv21ToImage(
          inputImage.bytes!,
          metadata.size.width.toInt(),
          metadata.size.height.toInt(),
        );
      } else {
        _logger.w(
          'FaceRecognizerService: Unsupported raw image format ${metadata.format} from InputImage.bytes.',
        );
        return null;
      }
    }

    if (rawImage == null) {
      _logger.w(
        'FaceRecognizerService: Failed to convert InputImage to img_lib.Image.',
      );
      return null;
    }

    // 2. Rotate the rawImage to be upright, matching how ML Kit sees it.
    // The face.boundingBox is relative to this upright image.
    img_lib.Image uprightImage = rawImage;
    if (inputImage.metadata?.rotation != null &&
        inputImage.metadata!.rotation != InputImageRotation.rotation0deg) {
      uprightImage = _rotateImage(rawImage, inputImage.metadata!.rotation);
    }

    // Now, uprightImage is oriented correctly. The boundingBox from ML Kit
    // should apply to this uprightImage. However, ML Kit's bounding box is
    // for an image of size inputImage.metadata.size. If rotation involved
    // swapping width/height (90 or 270 deg), uprightImage.width/height will reflect that.

    // 3. Crop the face from the upright image using bounding box
    final Rect boundingBox = face.boundingBox;
    // Clamp bounding box coordinates to ensure they are within image bounds
    // Bounding box coordinates are relative to the image dimensions ML Kit used.
    // If rotation was 90 or 270, ML Kit effectively saw an image with swapped width/height.
    // `uprightImage` will have these swapped dimensions.

    final int cropX = boundingBox.left.toInt().clamp(0, uprightImage.width);
    final int cropY = boundingBox.top.toInt().clamp(0, uprightImage.height);
    final int cropWidth = boundingBox.width.toInt().clamp(
      0,
      uprightImage.width - cropX,
    );
    final int cropHeight = boundingBox.height.toInt().clamp(
      0,
      uprightImage.height - cropY,
    );

    if (cropWidth <= 0 || cropHeight <= 0) {
      _logger.w(
        'FaceRecognizerService: Invalid bounding box dimensions after clamp for cropping: w=$cropWidth, h=$cropHeight on upright image (w=${uprightImage.width}, h=${uprightImage.height})',
      );
      return null;
    }

    final img_lib.Image croppedFace = img_lib.copyCrop(
      uprightImage,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );

    // 4. Resize and preprocess the cropped face
    final img_lib.Image resizedFace = img_lib.copyResize(
      croppedFace,
      width: _inputImageSize,
      height: _inputImageSize,
    );

    // Convert resized image to RGB bytes and then normalize to Float32List [-1, 1]
    final img_lib.Image rgbImage = resizedFace.convert(
      numChannels: 3, // Ensure 3 channels (RGB)
      format: img_lib.Format.uint8, // Ensure 8-bit unsigned integer per channel
    );
    final Uint8List bytes = rgbImage.getBytes(order: img_lib.ChannelOrder.rgb);

    final inputBytes = Float32List(
      _inputImageSize * _inputImageSize * 3,
    ); // 3 channels (RGB)
    int pixelIndex = 0;
    for (int i = 0; i < bytes.length; i += 3) {
      final int r = bytes[i];
      final int g = bytes[i + 1];
      final int b = bytes[i + 2];

      // Normalize pixel values from [0, 255] to [-1, 1]
      inputBytes[pixelIndex++] = (r - 127.5) / 127.5;
      inputBytes[pixelIndex++] = (g - 127.5) / 127.5;
      inputBytes[pixelIndex++] = (b - 127.5) / 127.5;
    }

    // Reshape to the model's expected input shape (e.g., [1, 112, 112, 3])
    final input = inputBytes.reshape([1, _inputImageSize, _inputImageSize, 3]);

    // 5. Prepare output buffer
    // MobileFaceNet outputs a 192-dimensional embedding based on the error log.
    final output = List.filled(1 * 192, 0.0).reshape([1, 192]);

    // 6. Run inference
    try {
      _interpreter!.run(input, output);
      // The output is typically a list of lists, so output[0] gives the embedding
      // Fixed: Directly convert List<double> to Float32List
      final Float32List embedding = Float32List.fromList(
        output[0].cast<double>(),
      );
      _logger.d('FaceRecognizerService: Embedding generated successfully.');
      return embedding;
    } catch (e) {
      _logger.e('FaceRecognizerService: Error running inference: $e');
      return null;
    }
  }

  /// Converts NV21 (YUV420SP) byte array to an img_lib.Image (RGB).
  /// This is essential for processing Android camera images.
  img_lib.Image? _convertNv21ToImage(
    Uint8List nv21Bytes,
    int width,
    int height,
  ) {
    if (nv21Bytes.isEmpty || width <= 0 || height <= 0) {
      _logger.w('FaceRecognizerService: Invalid NV21 data for conversion.');
      return null;
    }

    final int frameSize = width * height;
    final Uint8List y = nv21Bytes.sublist(0, frameSize);
    final Uint8List uv = nv21Bytes.sublist(frameSize, nv21Bytes.length);

    img_lib.Image image = img_lib.Image(width: width, height: height);

    for (int yIndex = 0; yIndex < height; yIndex++) {
      for (int xIndex = 0; xIndex < width; xIndex++) {
        final int Y = y[yIndex * width + xIndex] & 0xff; // Y value
        // UV values are subsampled (every 2x2 block has one U and V)
        // Ensure to access UV values correctly, considering 2 bytes per UV pair.
        final int uvIndex = ((yIndex ~/ 2) * (width ~/ 2) + (xIndex ~/ 2)) * 2;
        if (uvIndex + 1 >= uv.length) {
          // Prevent index out of bounds
          _logger.w(
            'FaceRecognizerService: NV21 UV index out of bounds. Skipping pixel.',
          );
          continue;
        }
        final int U = uv[uvIndex] & 0xff;
        final int V = uv[uvIndex + 1] & 0xff;

        // Convert YUV to RGB (BT.601 standard formulas)
        // These formulas are approximated and common for YUV420
        int r = (Y + 1.402 * (V - 128)).round();
        int g = (Y - 0.344 * (U - 128) - 0.714 * (V - 128)).round();
        int b = (Y + 1.772 * (U - 128)).round();

        // Clamp RGB values to [0, 255]
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        image.setPixelRgb(xIndex, yIndex, r, g, b);
      }
    }
    return image;
  }

  /// Registers a new face with a given name and its embedding.
  /// For now, this stores the face in an in-memory map.
  Future<void> registerFace(
    String name,
    Face face,
    InputImage inputImage,
  ) async {
    _logger.i('FaceRecognizerService: Registering face for: $name');
    if (name.trim().isEmpty) {
      _logger.e('FaceRecognizerService: Face name cannot be empty.');
      throw Exception('Face name cannot be empty.');
    }
    final Float32List? embedding = await getFaceEmbedding(inputImage, face);
    if (embedding != null) {
      await _faceDatabaseHelper.insertFace(name, embedding); // Save to DB first
      _knownFaces[name] = embedding;
      _logger.i(
        'FaceRecognizerService: Face for "$name" registered successfully.',
      );
    } else {
      _logger.e(
        'FaceRecognizerService: Failed to get embedding for "$name". Face not registered.',
      );
      throw Exception('Failed to get face embedding for registration.');
    }
  }

  /// Recognizes a face by comparing its embedding to known faces.
  /// Returns the name of the recognized person or null if no match is found.
  Future<String?> recognizeFace(Face face, InputImage inputImage) async {
    // Ensure faces are loaded from DB if in-memory is empty (e.g., after app restart)
    if (_knownFaces.isEmpty) {
      await loadFacesFromDatabase();
    }
    if (_knownFaces.isEmpty) {
      _logger.i('FaceRecognizerService: No known faces to recognize against.');
      return null;
    }

    _logger.i('FaceRecognizerService: Attempting to recognize face.');
    final Float32List? queryEmbedding = await getFaceEmbedding(
      inputImage,
      face,
    );
    if (queryEmbedding == null) {
      _logger.e(
        'FaceRecognizerService: Failed to get embedding for recognition query.',
      );
      return null;
    }

    String? recognizedName;
    double minDistance = double.infinity;

    _knownFaces.forEach((name, knownEmbedding) {
      if (queryEmbedding.length != knownEmbedding.length) {
        _logger.w('Embedding length mismatch for $name. Skipping comparison.');
        return;
      }
      final double distance = _euclideanDistance(
        queryEmbedding,
        knownEmbedding,
      );
      _logger.d(
        'FaceRecognizerService: Distance between query and $name: $distance',
      );

      if (distance < minDistance) {
        minDistance = distance;
        recognizedName = name;
      }
    });

    if (minDistance < recognitionThreshold) {
      _logger.i(
        'FaceRecognizerService: Recognized "$recognizedName" with distance: $minDistance',
      );
      return recognizedName;
    } else {
      _logger.i(
        'FaceRecognizerService: No face recognized. Minimum distance: $minDistance (Threshold: $recognitionThreshold)',
      );
      return null;
    }
  }

  /// Calculates the Euclidean distance between two embeddings.
  double _euclideanDistance(Float32List emb1, Float32List emb2) {
    if (emb1.length != emb2.length) {
      throw ArgumentError('Embeddings must have the same length.');
    }
    double sumOfSquares = 0.0;
    for (int i = 0; i < emb1.length; i++) {
      sumOfSquares += pow((emb1[i] - emb2[i]), 2);
    }
    return sqrt(sumOfSquares);
  }

  /// Loads known faces from the database into the in-memory map.
  Future<void> loadFacesFromDatabase() async {
    _logger.i('FaceRecognizerService: Loading known faces from database...');
    try {
      final facesFromDb = await _faceDatabaseHelper.getKnownFaces();
      _knownFaces.clear(); // Clear existing in-memory faces
      _logger.d(
        "FaceRecognizerService: loadFacesFromDatabase: facesFromDb length is: ${facesFromDb.length}.",
      );

      _knownFaces.addAll(facesFromDb);
      _logger.i(
        'FaceRecognizerService: Loaded ${_knownFaces.length} faces from database.',
      );
    } catch (e) {
      _logger.e('FaceRecognizerService: Error loading faces from database: $e');
    }
  }

  /// Disposes the TFLite interpreter and cleans up resources.
  void dispose() {
    _logger.i('FaceRecognizerService: Disposing interpreter.');
    _interpreter?.close();
    _interpreter = null;
    // _knownFaces.clear(); // Clearing here might be premature if service is reused.
  }

  /// Allows setting the database helper after initial construction if necessary.
  /// Primarily for scenarios where the helper might not be available at the exact moment of singleton creation.
  void setDatabaseHelper(FaceDatabaseHelper helper) {
    _faceDatabaseHelper = helper;
  }
}
