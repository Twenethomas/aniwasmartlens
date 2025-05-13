// lib/features/scene_description/scene_description_page.dart
import 'dart:io' show File;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/image_labeler_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

// Only for web
import 'dart:html' as html;
import 'dart:ui' as ui;

class SceneDescriptionPage extends StatefulWidget {
  const SceneDescriptionPage({super.key});

  // Azure GPT endpoint
  final String azureApiKey = "6d0c515a8f144a46b9bc445c7ff5bbf8";
  final String azureEndpoint =
      "https://buzznewwithgpt4.openai.azure.com/openai/deployments/bgpt/chat/completions?api-version=2023-03-15-preview";

  @override
  _SceneDescriptionPageState createState() => _SceneDescriptionPageState();
}

class _SceneDescriptionPageState extends State<SceneDescriptionPage> {
  // Camera
  CameraController? _camController;
  List<CameraDescription>? _cameras;
  double _currentZoom = 1.0, _minZoom = 1.0, _maxZoom = 1.0;
  bool _cameraActive = true;
  
  // Scene Description
  String _description = '';
  bool _busy = false;
  late final FlutterTts _tts;
  String _recognizedText = '';
  
  // Web
  html.VideoElement? _webcamVideo;
  html.ImageElement? _webCapturedImage; // Store captured image
  bool _webcamActive = true;
  
  // Accessibility features
  bool _highContrast = false;
  double _textSize = 16.0;
  double _lineSpacing = 1.0;

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (kIsWeb) {
      _initWebcam();
    } else {
      if (await Permission.camera.request().isGranted) {
        _cameras = await availableCameras();
        if (_cameras!.isNotEmpty) {
          _camController = CameraController(
            _cameras!.first,
            ResolutionPreset.max,
          );
          await _camController!.initialize();
          _minZoom = await _camController!.getMinZoomLevel();
          _maxZoom = await _camController!.getMaxZoomLevel();
          setState(() {});
        }
      }
    }
  }

  void _initWebcam() {
    _webcamVideo = html.VideoElement()
      ..autoplay = true
      ..muted   = true
      ..style.objectFit = 'cover';

    html.window.navigator.getUserMedia(video: true).then((stream) {
      _webcamVideo!.srcObject = stream;
    }).catchError((_) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Webcam unavailable')));
    });

    // Register the view
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      'webcamVideo',
      (int viewId) => _webcamVideo!,
    );
  }
  Future<void> _captureAndDescribe() async {
  setState(() => _busy = true);
  String? base64;
  File? imageFile;

  if (kIsWeb) {
    final canvas = html.CanvasElement(
      width: _webcamVideo!.videoWidth,
      height: _webcamVideo!.videoHeight,
    );
    canvas.context2D.drawImageScaled(
      _webcamVideo!,
      0,
      0,
      _webcamVideo!.videoWidth,
      _webcamVideo!.videoHeight,
    );

    final dataUrl = canvas.toDataUrl('image/png');
    base64 = extractBase64FromDataUrl(dataUrl);

    if (base64 == null) {
      setState(() {
        _busy = false;
        _recognizedText = 'Invalid image data';
      });
      return;
    }

    // Stop webcam stream
    _webcamVideo?.srcObject?.getTracks().forEach((track) => track.stop());
    _webcamVideo = null;
    _webcamActive = false;

    // Store full data URL for preview
    final img = html.ImageElement();
    img.src = dataUrl; // ✅ Use full data URL for preview
    setState(() {
      _webCapturedImage = img;
      _webcamActive = false;
    });
  } else {
    if (_camController != null && _camController!.value.isInitialized) {
      final file = await _camController!.takePicture();
      imageFile = File(file.path);
    }
  }

  final service = ImageLabelerService();
  try {
    final labels = await service.labelImage(base64Image: base64 ?? '');
    service.dispose();

    final labelDescriptions = labels.map((l) => l.label).toList();
    final sceneDescription = await _generateSceneDescription(labelDescriptions);

    setState(() {
      _description = sceneDescription.trim();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sheetController.isAttached) {
        _sheetController.animateTo(
          0.5,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  } catch (e) {
    setState(() => _description = 'Error: $e');
  } finally {
    setState(() => _busy = false);
  }
}  String? extractBase64FromDataUrl(String dataUrl) {
  try {
    final parts = dataUrl.split(',');
    if (parts.length < 2) return null;
    final base64 = parts[1].trim();
    // Optional: Validate base64 format
    if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(base64)) return null;
    return base64;
  } catch (_) {
    return null;
  }
  }

  Future<String> _generateSceneDescription(List<String> labels) async {
    if (labels.isEmpty) return 'No objects detected in the image.';
    
    final headers = {
      'Content-Type': 'application/json',
      'api-key': widget.azureApiKey,
    };

    final body = jsonEncode({
      'messages': [
        {
          'role': 'user',
          'content': 'Generate a concise scene description from these objects: ${labels.join(', ')}'
        }
      ],
      'temperature': 0.3,
      'max_tokens': 800,
    });

    final response = await http.post(
      Uri.parse(widget.azureEndpoint),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['choices'][0]['message']['content'];
    } else {
      // Fallback to raw labels
      return 'Scene includes: ${labels.join(', ')}';
    }
  }

  Future<void> _speakDescription() async {
    if (_description.isNotEmpty) {
      await _tts.speak(_description);
    }
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
  }

  Future<void> _zoomIn() async {
    if (_camController == null) return;
    final next = (_currentZoom + 1.0).clamp(_minZoom, _maxZoom);
    await _camController!.setZoomLevel(next);
    setState(() => _currentZoom = next);
  }

  Future<void> _zoomOut() async {
    if (_camController == null) return;
    final next = (_currentZoom - 1.0).clamp(_minZoom, _maxZoom);
    await _camController!.setZoomLevel(next);
    setState(() => _currentZoom = next);
  }

  Future<void> _resetCamera() async {
    if (kIsWeb) {
      _webCapturedImage = null;
      _initWebcam();
    } else {
      _camController = null;
      _initCamera();
    }
    setState(() => _description = '');
  }

  // Draggable Sheet controller
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  @override
  void dispose() {
    _camController?.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black45,
        title: const Text('Scene Description'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.translate),
            onPressed: _busy ? null : _showLanguageSelectionDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Preview
          Positioned.fill(
            child: _buildCameraPreview(),
          ),
          
          // Busy overlay
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
            ),
          
          // Controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: SafeArea(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    FloatingActionButton(
                      heroTag: 'capture',
                      onPressed: _busy ? null : _captureAndDescribe,
                      backgroundColor: Colors.white70,
                      child: const Icon(Icons.camera_alt),
                    ),
                    const SizedBox(width: 12),
                    
                    FloatingActionButton(
                      heroTag: 'speak',
                      onPressed: _description.isEmpty || _busy ? null : _speakDescription,
                      backgroundColor: Colors.white70,
                      child: const Icon(Icons.volume_up),
                    ),
                    const SizedBox(width: 12),
                    
                    FloatingActionButton(
                      heroTag: 'stop',
                      onPressed: _description.isEmpty || _busy ? null : _stopSpeaking,
                      backgroundColor: Colors.white70,
                      child: const Icon(Icons.stop),
                    ),
                    const SizedBox(width: 12),
                    
                    FloatingActionButton(
                      heroTag: 'reset',
                      onPressed: _busy ? null : _resetCamera,
                      backgroundColor: Colors.white70,
                      child: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Sliding description panel
          _buildDescriptionPanel(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
  if (kIsWeb) {
    if (_webCapturedImage != null) {
      // ✅ Use full data URL for network preview
      return Image.network(_webCapturedImage!.src ?? '');
    } else if (_webcamVideo != null && _webcamActive) {
      return HtmlElementView(viewType: 'webcamVideo');
    }
    return const Center(child: CircularProgressIndicator());
  } else {
    if (_camController != null && _camController!.value.isInitialized && _cameraActive) {
      return CameraPreview(_camController!);
    } else if (_mobileCapturedImage != null) {
      return Image.file(_mobileCapturedImage!);
    }
    return const Center(child: CircularProgressIndicator());
  }
}

  Widget _buildDescriptionPanel() {
    return kIsWeb
        ? Positioned(
            left: 0,
            right: 0,
            bottom: 100,
            height: 300,
            child: _buildDescriptionPanelContent(),
          )
        : DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.3,
            minChildSize: 0.15,
            maxChildSize: 0.7,
            builder: (context, scrollCtrl) =>
                _buildDescriptionPanelContent(scrollCtrl),
          );
  }

  Widget _buildDescriptionPanelContent([ScrollController? scrollCtrl]) {
    return Container(
      decoration: BoxDecoration(
        color: _highContrast ? Colors.black87 : Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kIsWeb ? 0 : 24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      margin: kIsWeb ? const EdgeInsets.all(16) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!kIsWeb)
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          
          const SizedBox(height: 8),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Scene Description',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _highContrast ? Colors.yellow : Colors.black87,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      _highContrast
                          ? Icons.contrast
                          : Icons.contrast_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        _highContrast = !_highContrast;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _description.isEmpty
                        ? 'No scene description generated yet.'
                        : _description,
                    style: GoogleFonts.robotoMono(
                      fontSize: _textSize,
                      color: _highContrast ? Colors.yellow : Colors.black87,
                      height: _lineSpacing,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: const Icon(Icons.text_increase),
                onPressed: () {
                  setState(() {
                    _textSize += 2;
                  });
                },
              ),
              Text('Size: ${_textSize.toStringAsFixed(0)}'),
              IconButton(
                icon: const Icon(Icons.text_decrease),
                onPressed: () {
                  setState(() {
                    _textSize -= 2;
                    if (_textSize < 10) _textSize = 10;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.format_line_spacing),
                onPressed: () {
                  setState(() {
                    _lineSpacing += 0.2;
                    if (_lineSpacing > 2.0) _lineSpacing = 1.0;
                  });
                },
              ),
              ElevatedButton.icon(
                onPressed: _description.isEmpty ? null : _speakDescription,
                icon: const Icon(Icons.volume_up),
                label: const Text('Read Aloud'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Language selection
  Future<void> _showLanguageSelectionDialog() async {
    final langMap = {
      'eng': 'en-US',
      'spa': 'es-ES',
      'fra': 'fr-FR',
      'deu': 'de-DE',
      'ita': 'it-IT',
      'por': 'pt-BR',
    };
    
    final supportedLanguages = {
      'eng': 'English',
      'spa': 'Español',
      'fra': 'Français',
      'deu': 'Deutsch',
      'ita': 'Italiano',
      'por': 'Português',
    };
    
    final currentLangCode = langMap[_selectedLanguageCode] ?? 'en-US';
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  'Select Output Language',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: supportedLanguages.length,
                    itemBuilder: (context, index) {
                      final code = supportedLanguages.keys.elementAt(index);
                      final name = supportedLanguages[code]!;
                      
                      return ListTile(
                        title: Text(name),
                        trailing: code == _selectedLanguageCode 
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.radio_button_unchecked),
                        onTap: () async {
                          setState(() => _selectedLanguageCode = code);
                          await _saveLanguagePreference(
                            ocrLang: code,
                            ttsLang: langMap[code] ?? 'en-US',
                          );
                          Navigator.pop(context);
                          
                          if (_description.isNotEmpty) {
                            await _tts.setLanguage(langMap[code] ?? 'en-US');
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveLanguagePreference({
    required String ocrLang,
    required String ttsLang,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ocr_language', ocrLang);
    await prefs.setString('tts_language', ttsLang);
  }

  String _selectedLanguageCode = 'eng';

  // Mobile captured image
  File? _mobileCapturedImage;

  Widget get _buildImagePreview {
    if (kIsWeb) {
      if (_webCapturedImage != null) {
        return Image.memory(base64.decode(_webCapturedImage!.src ?? ''));
      } else if (_webcamVideo != null && _webcamActive) {
        return HtmlElementView(viewType: 'webcamVideo');
      }
      return const Center(child: CircularProgressIndicator());
    } else {
      if (_mobileCapturedImage != null) {
        return Image.file(_mobileCapturedImage!);
      } else if (_camController != null && _camController!.value.isInitialized) {
        return CameraPreview(_camController!);
      }
      return const Center(child: CircularProgressIndicator());
    }
  }
}