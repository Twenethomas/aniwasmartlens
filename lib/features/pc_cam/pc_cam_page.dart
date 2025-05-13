import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class PcCamPage extends StatefulWidget {
  const PcCamPage({super.key});

  @override
  _PcCamPageState createState() => _PcCamPageState();
}

class _PcCamPageState extends State<PcCamPage> {
  CameraController? _controller;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isNotEmpty) {
      _controller = CameraController(cameras[0], ResolutionPreset.medium);
      await _controller!.initialize();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text('PC Webcam')),
      body: CameraPreview(_controller!),
    );
  }
}
