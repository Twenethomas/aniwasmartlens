// lib/features/scene_description/scene_description_state.dart
import 'dart:async';
import 'dart:io';
import 'dart:convert'; // Import for base64Encode

import 'package:camera/camera.dart';
import 'package:flutter/material.dart'; // Import for WidgetsBinding.instance.addPostFrameCallback
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart'; // For picking images from gallery

import '../../core/services/network_service.dart';
import '../../core/services/gemini_service.dart'; // Import GeminiService
import '../../main.dart'; // For global logger

class SceneDescriptionState extends ChangeNotifier {
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _isCameraReady = false;
  String _imageDescription = '';
  String _errorMessage = '';
  bool _isProcessingAI = false;
  bool _isCameraCapturing = false; // To prevent multiple capture attempts
  final Logger _logger = logger;

  final NetworkService _networkService;
  final GeminiService _geminiService; // Injected GeminiService

  // Getters
  CameraController? get cameraController => _cameraController;
  bool get isCameraReady => _isCameraReady;
  String get imageDescription => _imageDescription;
  String get errorMessage => _errorMessage;
  bool get isProcessingAI => _isProcessingAI;
  bool get isCameraCapturing => _isCameraCapturing;


  SceneDescriptionState(this._networkService, this._geminiService); // Constructor injection

  void _setIsCameraReady(bool status) {
    if (_isCameraReady != status) {
      _isCameraReady = status;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void _setImageDescription(String description) {
    if (_imageDescription != description) {
      _imageDescription = description;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void _setErrorMessage(String message) {
    if (_errorMessage != message) {
      _errorMessage = message;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void _setIsProcessingAI(bool status) {
    if (_isProcessingAI != status) {
      _isProcessingAI = status;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  void _setIsCameraCapturing(bool status) {
    if (_isCameraCapturing != status) {
      _isCameraCapturing = status;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  Future<void> initCamera() async {
    _logger.i("SceneDescriptionState: Initializing camera.");
    _setErrorMessage('');
    _setIsCameraReady(false);
    _setImageDescription('');

    try {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        _availableCameras = await availableCameras();
        if (_availableCameras.isEmpty) {
          _setErrorMessage("No cameras found.");
          _logger.w("SceneDescriptionState: No cameras found on device.");
          return;
        }

        // Prefer back camera for scene description
        CameraDescription camera = _availableCameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.back,
          orElse: () => _availableCameras.first,
        );

        _cameraController = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: false,
        );

        await _cameraController!.initialize();
        _setIsCameraReady(true);
        _logger.i("SceneDescriptionState: Camera initialized successfully.");
      } else {
        _setErrorMessage("Camera permission denied.");
        _logger.w("SceneDescriptionState: Camera permission denied.");
      }
    } on CameraException catch (e) {
      _setErrorMessage('Error initializing camera: ${e.description}');
      _logger.e('Error initializing camera: $e');
    } catch (e) {
      _setErrorMessage('An unexpected error occurred: $e');
      _logger.e('Unexpected error during camera init: $e');
    }
  }

  Future<void> disposeCamera() async {
    _logger.i("SceneDescriptionState: Disposing camera.");
    if (_cameraController != null) {
      try {
        await _cameraController!.dispose();
        _cameraController = null;
      } on CameraException catch (e) {
        _logger.e('Error disposing camera: $e');
        _setErrorMessage('Error disposing camera: ${e.description}');
      }
    }
    _setIsCameraReady(false);
    _setImageDescription('');
    _setErrorMessage('');
    _setIsProcessingAI(false);
    _setIsCameraCapturing(false);
  }

  Future<void> takePictureAndDescribe() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isCameraCapturing) {
      _setErrorMessage("Camera not ready or already capturing.");
      return;
    }

    _setIsCameraCapturing(true);
    _setErrorMessage('');
    _setImageDescription('Capturing image...');
    _setIsProcessingAI(true); // Indicate AI processing starts after capture

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      _logger.i("Picture taken: ${imageFile.path}");

      final bytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(bytes);

      await _describeImage(base64Image);
    } on CameraException catch (e) {
      _setErrorMessage('Failed to take picture: ${e.description}');
      _logger.e('Failed to take picture: $e');
    } catch (e) {
      _setErrorMessage('An error occurred during picture capture: $e');
      _logger.e('Error during picture capture: $e');
    } finally {
      _setIsCameraCapturing(false);
      _setIsProcessingAI(false); // Ensure this is reset whether successful or not
    }
  }

  Future<void> pickImageAndDescribe() async {
    _setErrorMessage('');
    _setImageDescription('Picking image from gallery...');
    _setIsProcessingAI(true);

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? imageFile = await picker.pickImage(source: ImageSource.gallery);

      if (imageFile == null) {
        _setErrorMessage('No image selected.');
        _setImageDescription('');
        _setIsProcessingAI(false);
        return;
      }

      final bytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(bytes);

      await _describeImage(base64Image);
    } catch (e) {
      _setErrorMessage('Failed to pick image: $e');
      _logger.e('Failed to pick image from gallery: $e');
    } finally {
      _setIsProcessingAI(false); // Ensure this is reset whether successful or not
    }
  }


  Future<void> _describeImage(String base64Image) async {
    if (!_networkService.isOnline) {
      _setErrorMessage('No internet connection. Cannot describe image.');
      _setIsProcessingAI(false);
      return;
    }

    _setImageDescription('Describing image with AI...');
    _setIsProcessingAI(true); // Ensure this is true during AI processing

    try {
      // Use the getVisionResponse method from GeminiService
      final String description = await _geminiService.getVisionResponse(
        "Describe this image in detail, focusing on objects, colors, and overall scene content. Be concise and accurate, provide only the description.",
        base64Image,
      );
      _setImageDescription(description);
      _logger.i("Image Description: $description");
    } catch (e) {
      _setErrorMessage('Failed to get image description: $e');
      _logger.e('Error getting image description from Gemini: $e');
    } finally {
      _setIsProcessingAI(false);
    }
  }


  void clearDescription() {
    _setImageDescription('');
    _setErrorMessage('');
    _setIsProcessingAI(false);
    _setIsCameraCapturing(false);
  }

  @override
  void dispose() {
    _logger.i("SceneDescriptionState disposed.");
    disposeCamera();
    super.dispose();
  }
}
