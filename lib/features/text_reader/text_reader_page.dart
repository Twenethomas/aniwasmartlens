import 'dart:io' show File;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/text_reader_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

// Only for web
import 'dart:html' as html;
import 'dart:ui' as ui;

class TextReaderPage extends StatefulWidget {
  const TextReaderPage({super.key});

  // Azure GPT endpoint
  final String azureApiKey = "6d0c515a8f144a46b9bc445c7ff5bbf8";
  final String azureEndpoint =
      "https://buzznewwithgpt4.openai.azure.com/openai/deployments/bgpt/chat/completions?api-version=2023-03-15-preview";

  @override
  _TextReaderPageState createState() => _TextReaderPageState();
}

class _TextReaderPageState extends State<TextReaderPage> {
  // Camera
  CameraController? _camController;
  List<CameraDescription>? _cameras;
  double _currentZoom = 1.0, _minZoom = 1.0, _maxZoom = 1.0;
  bool _cameraActive = true;

  // OCR & TTS
  String _recognizedText = '';
  String _translatedText = '';
  bool _busy = false;
  late final FlutterTts _tts;
  String? _detectedLanguage; // Detected OCR language

  // Web
  html.VideoElement? _webcamVideo;
  html.ImageElement? _webCapturedImage; // Store captured image
  bool _webcamActive = true;

  // Language settings
  final Map<String, String> _supportedLanguages = {
    'eng': 'English',
    'spa': 'Español',
    'fra': 'Français',
    'deu': 'Deutsch',
    'ita': 'Italiano',
    'por': 'Português',
  };
  String _ocrLanguageCode = 'eng'; // OCR input language
  String _ttsLanguageCode = 'en-US'; // TTS output language
  bool _autoDetectLanguage = true;
  bool _autoTranslateToSystem = true;

  // Draggable Sheet controller
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  // Accessibility features
  bool _highContrast = false;
  double _textSize = 16.0;
  double _lineSpacing = 1.0;

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts()..setLanguage('en-US');
    _loadSavedSettings();

    if (kIsWeb) {
      _initWebcam();
    } else {
      _initCamera();
    }
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ocrLanguageCode = prefs.getString('ocr_language') ?? 'eng';
      _ttsLanguageCode = prefs.getString('tts_language') ?? 'en-US';
      _autoDetectLanguage = prefs.getBool('auto_detect') ?? true;
      _autoTranslateToSystem = prefs.getBool('auto_translate') ?? true;
    });
    await _tts.setLanguage(_ttsLanguageCode);
  }

  String _mapLanguageCode(String code) {
    switch (code) {
      case 'spa':
        return 'es-ES';
      case 'fra':
        return 'fr-FR';
      case 'deu':
        return 'de-DE';
      case 'ita':
        return 'it-IT';
      case 'por':
        return 'pt-BR';
      default:
        return 'en-US';
    }
  }

  String _getLanguageName(String code) {
    final langMap = {
      'en-US': 'English',
      'es-ES': 'Spanish',
      'fr-FR': 'French',
      'de-DE': 'German',
      'it-IT': 'Italian',
      'pt-BR': 'Portuguese',
    };
    return langMap[code] ?? 'Unknown';
  }

  // ─── CAMERA INIT ────────────────────────────────────────
  Future<void> _initCamera() async {
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
        _currentZoom = 1.0;
        setState(() {});
      }
    }
  }

  // ─── Init Web Webcam ────────────────────────────────────
  void _initWebcam() {
    _webcamVideo =
        html.VideoElement()
          ..autoplay = true
          ..muted = true
          ..style.objectFit = 'cover';

    html.window.navigator.getUserMedia(video: true).then((stream) {
      _webcamVideo!.srcObject = stream;
    });

    // register view
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      'webcamVideo',
      (int viewId) => _webcamVideo!,
    );
  }

  Future<void> _captureAndRecognize() async {
    setState(() => _busy = true);
    String? base64;
    File? imageFile;

    if (kIsWeb) {
      // Validate webcam stream
      if (_webcamVideo == null || _webcamVideo!.videoWidth == 0) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No webcam feed available')),
        );
        return;
      }

      // Capture image
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
      base64 = extractBase64FromDataUrl(canvas.toDataUrl('image/png'));

      // Stop webcam stream
      _webcamVideo?.srcObject?.getTracks().forEach((track) => track.stop());
      _webcamVideo = null;
      _webcamActive = false;

      // Store captured image for preview
      final img = html.ImageElement();
      img.src = "data:image/png;base64,$base64"; // Reconstruct data URL
      setState(() => _webCapturedImage = img);
    } else {
      if (_camController == null || !_camController!.value.isInitialized) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Camera not initialized')));
        return;
      }

      try {
        final file = await _camController!.takePicture();
        imageFile = File(file.path);
      } catch (e) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Camera error: $e')));
        return;
      }
    }

    final service = TextReaderService(
      imageFile: imageFile,
      language: _autoDetectLanguage ? 'auto' : _ocrLanguageCode,
    );

    try {
      final rawText = await service.recognizeText(base64Image: base64);

      if (rawText.trim().isEmpty) {
        throw Exception('No text found in image - try a clearer image');
      }

      final correctedText = await _correctWithAzure(rawText);

      setState(() {
        _recognizedText = correctedText.trim();
        _translatedText = '';
      });

      // Auto-detect language if enabled
      if (_autoDetectLanguage) {
        final detectedLang = await _detectLanguage(_recognizedText);
        setState(() => _ocrLanguageCode = detectedLang);
      }

      // Auto-translate if needed
      if (_autoTranslateToSystem &&
          (_mapLanguageCode(_ocrLanguageCode) != _ttsLanguageCode)) {
        final translatedText = await translateText(
          text: _recognizedText,
          sourceLang: _ocrLanguageCode,
          targetLang: _ttsLanguageCode,
        );
        setState(() => _translatedText = translatedText);
      }

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
      setState(() => _recognizedText = 'Error: $e');
    } finally {
      service.dispose();
      setState(() => _busy = false);
    }
  }

  String? extractBase64FromDataUrl(String dataUrl) {
    try {
      final parts = dataUrl.split(',');
      if (parts.length < 2) return null;
      final base64 = parts[1].trim();
      if (base64.length < 100) return null; // Empty image
      return base64;
    } catch (_) {
      return null;
    }
  }

  Future<String> _correctWithAzure(String rawText) async {
    if (rawText.isEmpty) {
      // ✅ Handle empty text case
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No text to correct')));
      return rawText;
    }

    final headers = {
      'Content-Type': 'application/json',
      'api-key': widget.azureApiKey,
    };

    final body = jsonEncode({
      'messages': [
        {
          'role': 'user',
          'content':
              'Correct any OCR errors in the following text and structure it properly:\n\n$rawText',
        },
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
      // ✅ Fallback to raw text if GPT fails
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPT correction failed - showing raw text'),
        ),
      );
      return rawText;
    }
  }

  Future<void> _speakText() async {
    if (_recognizedText.isEmpty) return;

    if (_autoTranslateToSystem &&
        _ttsLanguageCode != _mapLanguageCode(_ocrLanguageCode) &&
        _translatedText.isNotEmpty) {
      // Speak translated text if auto-translate is on and translation exists
      await _tts.speak(_translatedText);
    } else if (_autoTranslateToSystem &&
        _ttsLanguageCode != _mapLanguageCode(_ocrLanguageCode)) {
      // Translate and speak if auto-translate is on but no translation exists
      setState(() => _busy = true);
      try {
        final translatedText = await translateText(
          text: _recognizedText,
          sourceLang: _ocrLanguageCode,
          targetLang: _ttsLanguageCode,
        );
        setState(() => _translatedText = translatedText);
        await _tts.speak(translatedText);
      } catch (e) {
        await _tts.speak(_recognizedText); // Fallback to original
      } finally {
        setState(() => _busy = false);
      }
    } else {
      // Speak original text when auto-translate is off
      await _tts.speak(_recognizedText);
    }
  }

  Future<String> _detectLanguage(String text) async {
    final headers = {
      'Content-Type': 'application/json',
      'api-key': widget.azureApiKey,
    };

    final body = jsonEncode({
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a professional language detector. Return only the detected language code without any additional text.',
        },
        {'role': 'user', 'content': text},
      ],
      'temperature': 0.1,
      'max_tokens': 800,
    });

    final response = await http.post(
      Uri.parse(widget.azureEndpoint),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final detectedLang =
          jsonResponse['choices'][0]['message']['content'].trim().toLowerCase();

      // Map to OCR codes
      final langCodeMap = {
        'english': 'eng',
        'spanish': 'spa',
        'french': 'fra',
        'german': 'deu',
        'italian': 'ita',
        'portuguese': 'por',
      };

      return langCodeMap[detectedLang] ?? 'eng';
    } else {
      throw Exception('Language detection failed');
    }
  }

  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      'api-key': widget.azureApiKey,
    };

    final body = jsonEncode({
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a professional translator. Translate the text from $sourceLang to $targetLang without any additional text.',
        },
        {'role': 'user', 'content': text},
      ],
      'temperature': 0.1,
      'max_tokens': 800,
    });

    final response = await http.post(
      Uri.parse(widget.azureEndpoint),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['choices'][0]['message']['content'].trim();
    } else {
      throw Exception(
        'Translation Error: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<void> _resetCamera() async {
    if (kIsWeb) {
      _webCapturedImage = null;
      _initWebcam();
    } else {
      _mobileCapturedImage = null;
      _initCamera();
    }
    setState(() {
      _cameraActive = true;
      _webcamActive = true;
      _recognizedText = '';
      _translatedText = '';
    });
  }

  @override
  void dispose() {
    _camController?.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black45,
        elevation: 0,
        title: const Text('Text Reader'),
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
          Positioned.fill(child: _buildCameraPreview()),

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
                      onPressed: _busy ? null : _captureAndRecognize,
                      backgroundColor: Colors.white70,
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 12),

                    FloatingActionButton(
                      heroTag: 'speak',
                      onPressed:
                          _recognizedText.isEmpty || _busy ? null : _speakText,
                      backgroundColor: Colors.white70,
                      child: const Icon(Icons.volume_up, color: Colors.black87),
                    ),
                    const SizedBox(width: 12),

                    FloatingActionButton(
                      heroTag: 'stop',
                      onPressed:
                          _recognizedText.isEmpty || _busy
                              ? null
                              : _stopSpeaking,
                      backgroundColor: Colors.white70,
                      child: const Icon(Icons.stop, color: Colors.black87),
                    ),
                    const SizedBox(width: 12),

                    if (_translatedText.isNotEmpty)
                      FloatingActionButton(
                        heroTag: 'swap',
                        onPressed: _swapLanguages,
                        backgroundColor: Colors.white70,
                        child: const Icon(
                          Icons.swap_horiz,
                          color: Colors.black87,
                        ),
                      ),
                    const SizedBox(width: 12),

                    FloatingActionButton(
                      heroTag: 'reset',
                      onPressed: _busy ? null : _resetCamera,
                      backgroundColor: Colors.white70,
                      child: const Icon(Icons.refresh, color: Colors.black87),
                    ),
                    FloatingActionButton(
                      heroTag: 'translate',
                      onPressed:
                          _recognizedText.isEmpty || _busy
                              ? null
                              : _showTranslationDialog,
                      backgroundColor: Colors.white70,
                      child: const Icon(Icons.translate, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Sliding text panel
          _buildTextPanel(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (kIsWeb) {
      if (_webCapturedImage != null) {
        return Image.network(_webCapturedImage!.src ?? '');
      } else if (_webcamVideo != null && _webcamActive) {
        return HtmlElementView(viewType: 'webcamVideo');
      }
      return const Center(child: CircularProgressIndicator());
    } else {
      if (_camController != null &&
          _camController!.value.isInitialized &&
          _cameraActive) {
        return CameraPreview(_camController!);
      } else if (_mobileCapturedImage != null) {
        return Image.file(_mobileCapturedImage!);
      }
      return const Center(child: CircularProgressIndicator());
    }
  }

  Widget _buildTextPanel() {
    return kIsWeb
        ? Positioned(
          left: 0,
          right: 0,
          bottom: 100,
          height: 300,
          child: _buildTextPanelContent(),
        )
        : DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: 0.3,
          minChildSize: 0.15,
          maxChildSize: 0.7,
          builder: (context, scrollCtrl) => _buildTextPanelContent(scrollCtrl),
        );
  }

  Widget _buildTextPanelContent([ScrollController? scrollCtrl]) {
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                'Recognized Text',
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
                      _highContrast ? Icons.contrast : Icons.contrast_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        _highContrast = !_highContrast;
                      });
                    },
                  ),
                  if (_recognizedText.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _recognizedText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Text copied to clipboard!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),

          if (_autoDetectLanguage && _detectedLanguage != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Detected: ${_getLanguageName(_ocrLanguageCode)}',
                style: TextStyle(fontSize: 12, color: Colors.blue[300]),
              ),
            ),

          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _recognizedText.isEmpty
                        ? 'No text recognized yet.'
                        : _recognizedText,
                    style: GoogleFonts.robotoMono(
                      fontSize: _textSize,
                      color: _highContrast ? Colors.yellow : Colors.black87,
                      height: _lineSpacing,
                    ),
                  ),
                  if (_translatedText.isNotEmpty && _autoTranslateToSystem)
                    Column(
                      children: [
                        const SizedBox(height: 16),
                        const Text(
                          'Translated Text:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _translatedText,
                          style: GoogleFonts.robotoMono(
                            fontSize: _textSize,
                            color: Colors.blue[300],
                            height: _lineSpacing,
                          ),
                        ),
                      ],
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
                onPressed: _recognizedText.isEmpty ? null : _speakText,
                icon: const Icon(Icons.volume_up),
                label: const Text('Read Aloud'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Mobile captured image
  File? _mobileCapturedImage;

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

  Future<void> _showLanguageSelectionDialog() async {
    final langMap = {
      'eng': 'en-US',
      'spa': 'es-ES',
      'fra': 'fr-FR',
      'deu': 'de-DE',
      'ita': 'it-IT',
      'por': 'pt-BR',
    };

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.5,
            maxChildSize: 0.8,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Language Settings',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.auto_fix_high),
                        const SizedBox(width: 8),
                        const Text('Auto-Detect OCR Language'),
                        const Spacer(),
                        Switch(
                          value: _autoDetectLanguage,
                          onChanged: (value) async {
                            setState(() => _autoDetectLanguage = value);
                            await _saveSettings(autoDetect: value);
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.translate),
                        const SizedBox(width: 8),
                        const Text('Auto-Translate to System'),
                        const Spacer(),
                        Switch(
                          value: _autoTranslateToSystem,
                          onChanged: (value) async {
                            setState(() {
                              _autoTranslateToSystem = value;
                              if (!value) {
                                _translatedText = '';
                              }
                            });
                            await _saveSettings(autoTranslate: value);

                            if (value && _recognizedText.isNotEmpty) {
                              _speakText(); // Auto-translate if enabled
                            }
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Text(
                      'OCR Language',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _supportedLanguages.length,
                        itemBuilder: (context, index) {
                          final code = _supportedLanguages.keys.elementAt(
                            index,
                          );
                          final name = _supportedLanguages[code]!;
                          return ListTile(
                            title: Text(name),
                            trailing:
                                code == _ocrLanguageCode
                                    ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    )
                                    : const Icon(Icons.radio_button_unchecked),
                            onTap: () async {
                              setState(() => _ocrLanguageCode = code);
                              await _saveSettings(ocrLang: code);
                              Navigator.pop(context);

                              if (_recognizedText.isNotEmpty) {
                                if (_autoTranslateToSystem) {
                                  _speakText(); // Auto-translate if enabled
                                } else {
                                  _tts.setLanguage(_mapLanguageCode(code));
                                }
                              }
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(height: 32),
                    Text(
                      'TTS Language',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _supportedLanguages.length,
                        itemBuilder: (context, index) {
                          final code = _supportedLanguages.keys.elementAt(
                            index,
                          );
                          final ttsCode = langMap[code]!;
                          final name = _supportedLanguages[code]!;
                          return ListTile(
                            title: Text(name),
                            trailing:
                                ttsCode == _ttsLanguageCode
                                    ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    )
                                    : const Icon(Icons.radio_button_unchecked),
                            onTap: () async {
                              setState(() => _ttsLanguageCode = ttsCode);
                              await _saveSettings(ttsLang: ttsCode);
                              Navigator.pop(context);

                              if (_recognizedText.isNotEmpty) {
                                if (_autoTranslateToSystem) {
                                  _speakText(); // Auto-translate if enabled
                                } else {
                                  _tts.setLanguage(ttsCode);
                                }
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

  Future<void> _saveSettings({
    String? ocrLang,
    String? ttsLang,
    bool? autoDetect,
    bool? autoTranslate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (ocrLang != null) await prefs.setString('ocr_language', ocrLang);
    if (ttsLang != null) await prefs.setString('tts_language', ttsLang);
    if (autoDetect != null) await prefs.setBool('auto_detect', autoDetect);
    if (autoTranslate != null)
      await prefs.setBool('auto_translate', autoTranslate);

    // Clear translation when auto-translate is turned off
    if (autoTranslate != null && !autoTranslate) {
      setState(() => _translatedText = '');
    }
  }

  Future<void> _swapLanguages() async {
    if (_translatedText.isNotEmpty && _autoTranslateToSystem) {
      setState(() {
        final tempText = _recognizedText;
        final tempLang = _ocrLanguageCode;

        _recognizedText = _translatedText;
        _ocrLanguageCode = _ttsLanguageCode;
        _ttsLanguageCode = _mapLanguageCode(tempLang);
        _translatedText = '';
      });

      await _tts.setLanguage(_mapLanguageCode(_ocrLanguageCode));

      if (_autoTranslateToSystem) {
        final translatedText = await translateText(
          text: _recognizedText,
          sourceLang: _ocrLanguageCode,
          targetLang: _ttsLanguageCode,
        );
        setState(() => _translatedText = translatedText);
      }
    }
  }

  Future<void> _showTranslationDialog() async {
    final supportedLanguages = {
      'eng': 'English',
      'spa': 'Español',
      'fra': 'Français',
      'deu': 'Deutsch',
      'ita': 'Italiano',
      'por': 'Português',
    };

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.5,
            maxChildSize: 0.8,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Select Target Language',
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
                            trailing:
                                code == _ocrLanguageCode
                                    ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    )
                                    : const Icon(Icons.radio_button_unchecked),
                            onTap: () async {
                              Navigator.pop(context);
                              if (code != _ocrLanguageCode) {
                                setState(() => _busy = true);
                                try {
                                  final translatedText = await translateText(
                                    text: _recognizedText,
                                    sourceLang: _ocrLanguageCode,
                                    targetLang: code,
                                  );
                                  setState(() {
                                    _ocrLanguageCode = code;
                                    _translatedText = translatedText;
                                  });
                                  await _tts.setLanguage(
                                    _mapLanguageCode(code),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Translation failed: $e'),
                                    ),
                                  );
                                } finally {
                                  setState(() => _busy = false);
                                }
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
}
