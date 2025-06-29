import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoCallService {
  late RTCVideoRenderer localRenderer;
  late RTCVideoRenderer remoteRenderer;

  Future<void> init() async {
    localRenderer = RTCVideoRenderer()..initialize();
    remoteRenderer = RTCVideoRenderer()..initialize();
  }

  void dispose() {
    localRenderer.dispose();
    remoteRenderer.dispose();
    // TODO: close peerConnection
  }

  // TODO: signaling logic
}
