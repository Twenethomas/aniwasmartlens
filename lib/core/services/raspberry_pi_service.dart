// lib/core/services/raspberry_pi_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../main.dart'; // For global logger

enum RaspberryPiConnectionStatus { disconnected, connecting, connected, error }

class RaspberryPiService extends ChangeNotifier {
  final Logger _logger = logger;
  io.Socket? _socket;

  String? _raspberryPiIp;
  final int _port = 5000; // Default Flask port from assistive_lens.py

  RaspberryPiConnectionStatus _connectionStatus =
      RaspberryPiConnectionStatus.disconnected;
  RaspberryPiConnectionStatus get connectionStatus => _connectionStatus;

  String? get raspberryPiUrl =>
      _raspberryPiIp != null ? 'http://$_raspberryPiIp:$_port' : null;
  String? get videoFeedUrl =>
      raspberryPiUrl != null ? '$raspberryPiUrl/video_feed' : null;

  // Streams for data from Raspberry Pi
  final StreamController<Map<String, dynamic>> _statusUpdateController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get statusUpdateStream =>
      _statusUpdateController.stream;

  final StreamController<String> _speechOutputController =
      StreamController.broadcast();
  Stream<String> get speechOutputStream => _speechOutputController.stream;

  // NEW: Stream for messages from Pi (user) to mobile app (caretaker)
  final StreamController<Map<String, dynamic>> _userMessageController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get userMessageStream =>
      _userMessageController.stream;

  // NEW: Stream for navigation status updates
  final StreamController<Map<String, dynamic>> _navigationStatusController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get navigationStatusStream =>
      _navigationStatusController.stream;

  // NEW: Stream for navigation instructions
  final StreamController<Map<String, dynamic>>
  _navigationInstructionController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get navigationInstructionStream =>
      _navigationInstructionController.stream;

  final StreamController<Map<String, dynamic>> _logController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get logStream => _logController.stream;

  RaspberryPiService();

  Future<void> connect(String ipAddress) async {
    // If already trying to connect or connected to the same IP, do nothing.
    if (_raspberryPiIp == ipAddress &&
        (_connectionStatus == RaspberryPiConnectionStatus.connecting ||
            _connectionStatus == RaspberryPiConnectionStatus.connected)) {
      _logger.i(
        "RaspberryPiService: Already connecting or connected to $ipAddress. Skipping connection attempt.",
      );
      return;
    }

    // If connected/connecting to a different IP, disconnect first.
    if (_raspberryPiIp != ipAddress &&
        (_connectionStatus == RaspberryPiConnectionStatus.connecting ||
            _connectionStatus == RaspberryPiConnectionStatus.connected)) {
      _logger.i(
        "RaspberryPiService: Different IP requested ($ipAddress). Disconnecting from $_raspberryPiIp first.",
      );
      await disconnect();
    }

    _raspberryPiIp = ipAddress;
    _setConnectionStatus(RaspberryPiConnectionStatus.connecting);
    _logger.i(
      "RaspberryPiService: Attempting to connect to Raspberry Pi at $raspberryPiUrl...",
    );

    try {
      _socket = io.io(raspberryPiUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false, // We'll manage connection explicitly
        'forceNew':
            true, // Ensures a new connection attempt each time connect() is called
        'enableReconnection': true, // Enable automatic reconnection attempts
        'reconnectionAttempts': 5, // Number of reconnection attempts
        'reconnectionDelay':
            1000, // Initial delay before first reconnection attempt (1 second)
        'reconnectionDelayMax':
            5000, // Maximum delay between reconnection attempts (5 seconds)
        'pingInterval': 25000, // Client sends ping every 25 seconds
        'pingTimeout': 60000, // Client waits 60 seconds for a pong response
      });

      _socket!.onConnect((_) {
        _logger.i('RaspberryPiService: Connected to $raspberryPiUrl');
        _setConnectionStatus(RaspberryPiConnectionStatus.connected);
        _setupSocketListeners();
      });

      _socket!.onConnectError((data) {
        _logger.e('RaspberryPiService: Connection Error: $data');
        _setConnectionStatus(RaspberryPiConnectionStatus.error);
        _socket?.dispose(); // Ensure socket is disposed on connect error
        _socket = null;
      });

      _socket!.onError((data) {
        _logger.e('RaspberryPiService: Socket Error: $data');
        // This often fires before onDisconnect if the error causes a disconnect
        if (_connectionStatus != RaspberryPiConnectionStatus.disconnected) {
          _setConnectionStatus(RaspberryPiConnectionStatus.error);
        }
      });

      _socket!.onDisconnect((reason) {
        _logger.i(
          'RaspberryPiService: Disconnected from $raspberryPiUrl. Reason: $reason',
        );
        // Only set to disconnected if not already in an error state from onError
        if (_connectionStatus != RaspberryPiConnectionStatus.error) {
          _setConnectionStatus(RaspberryPiConnectionStatus.disconnected);
        }
        _socket?.dispose(); // Ensure socket is disposed on disconnect
        _socket = null;
      });

      _socket!.connect(); // Explicitly initiate the connection
    } catch (e) {
      _logger.e("RaspberryPiService: Exception during connection attempt: $e");
      _setConnectionStatus(RaspberryPiConnectionStatus.error);
      _socket?.dispose();
      _socket = null;
    }
  }

  void _setupSocketListeners() {
    if (_socket == null) return;

    _socket!.on('system_status', (data) {
      _logger.d('RaspberryPiService: Received system_status: $data');
      _statusUpdateController.add({'type': 'system_status', 'data': data});
    });

    _socket!.on('update', (data) {
      _logger.d('RaspberryPiService: Received update: $data');
      _statusUpdateController.add(
        data,
      ); // Assuming data is already {'type': ..., 'data': ...}
      _logController.add({
        'timestamp': DateTime.now().toIso8601String(),
        'message': "Update: ${data['type']}",
      });
    });

    _socket!.on('speech_output', (data) {
      _logger.d(
        'RaspberryPiService: Received speech_output: ${data['message']}',
      );
      _speechOutputController.add(data['message']);
      _logController.add({
        'timestamp': DateTime.now().toIso8601String(),
        'message': "Speech: ${data['message']}",
      });
    });

    _socket!.on('obstacle_alert', (data) {
      _logger.w('RaspberryPiService: Received obstacle_alert: $data');
      // Add to the main status stream for UI updates
      _statusUpdateController.add({'type': 'obstacle_alert', 'data': data});
      _logController.add({
        'timestamp': DateTime.now().toIso8601String(),
        'message': "OBSTACLE: ${data['message']}",
      });
    });

    _socket!.on('emergency_alert', (data) {
      _logger.w('RaspberryPiService: Received emergency_alert: $data');
      _statusUpdateController.add({'type': 'emergency_alert', 'data': data});
      _logController.add({
        'timestamp': DateTime.now().toIso8601String(),
        'message': "EMERGENCY: ${data['message']}",
      });
    });

    // NEW: Listen for user messages from Pi
    _socket!.on('user_message', (data) {
      _logger.d('RaspberryPiService: Received user_message: $data');
      _userMessageController.add(data);
      _logController.add({
        'timestamp': DateTime.now().toIso8601String(),
        'message': "User: ${data['message']}",
      });
    });

    // NEW: Listen for navigation status updates
    _socket!.on('navigation_status', (data) {
      _logger.d('RaspberryPiService: Received navigation_status: $data');
      _navigationStatusController.add(data);
      _logController.add({
        'timestamp': DateTime.now().toIso8601String(),
        'message': "Nav Status: ${data['status']}",
      });
    });

    // NEW: Listen for navigation instructions
    _socket!.on('navigation_instruction', (data) {
      _logger.d('RaspberryPiService: Received navigation_instruction: $data');
      _navigationInstructionController.add(data);
      _logController.add({
        'timestamp': DateTime.now().toIso8601String(),
        'message': "Nav Instr: ${data['instruction']}",
      });
    });

    _socket!.on('command_response', (data) {
      _logger.d('RaspberryPiService: Received command_response: $data');
      _logController.add({
        'timestamp': DateTime.now().toIso8601String(),
        'message': "CMD Response: ${data['status']} for ${data['command']}",
      });
    });
    // MODIFICATION: Listen for connection_status from Pi (if Pi sends it, but also handled internally by _setConnectionStatus)
    _socket!.on('connection_status', (data) {
      _logger.d(
        'RaspberryPiService: Received connection_status from Pi: $data',
      );
      final bool piReportsConnected = data?['connected'] as bool? ?? false;
      // This is a secondary indicator, _setConnectionStatus is the primary
      // We log it for debugging but rely on the socket's own lifecycle for _connectionStatus
      _logController.add({
        'timestamp': DateTime.now().toIso8601String(),
        'message':
            "Pi Self-Reported Connection: ${piReportsConnected ? 'Connected' : 'Disconnected'}",
      });
    });
  }

  Future<void> disconnect() async {
    _logger.i("RaspberryPiService: Disconnecting...");
    _socket?.disconnect();
    // It's crucial to also stop and dispose if the socket is not going to auto-reconnect immediately,
    // or if we explicitly want to tear down its resources.
    _socket?.dispose();
    _socket = null;
    _raspberryPiIp = null;
    _setConnectionStatus(RaspberryPiConnectionStatus.disconnected);
  }

  void sendCommand(String command, {Map<String, dynamic>? params}) {
    if (_socket != null && _socket!.connected) {
      _logger.i("RaspberryPiService: Sending command: $command");
      _socket!.emit('command', {
        'command': command,
        ...?params,
      }); // Merge params into the map
    } else {
      _logger.w(
        "RaspberryPiService: Cannot send command '$command', socket not connected. Current status: $_connectionStatus",
      );
    }
  }

  void _setConnectionStatus(RaspberryPiConnectionStatus status) {
    if (_connectionStatus != status) {
      _connectionStatus = status;
      notifyListeners();
      // MODIFICATION: Emit connection status through the stream
      _statusUpdateController.add({
        'type': 'connection_status',
        'data': {'connected': status == RaspberryPiConnectionStatus.connected},
      });
    }
  }

  @override
  void dispose() {
    _logger.i("RaspberryPiService: Disposing.");
    _socket?.dispose();
    _statusUpdateController.close();
    _userMessageController.close();
    _navigationStatusController.close();
    _navigationInstructionController.close();
    _speechOutputController.close();
    _logController.close();
    super.dispose();
  }
}
