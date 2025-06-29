// android/app/src/main/kotlin/com/example/assist_lens/VoiceAssistantService.kt
package com.example.assist_lens // This package declaration should match your namespace/applicationId

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo // NEW: Import ServiceInfo for FOREGROUND_SERVICE_TYPE_MICROPHONE
import android.os.Build
import android.os.IBinder
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.example.assist_lens.R // NEW: Import your app's R class

class VoiceAssistantService : Service(), RecognitionListener {

    private val TAG = "VoiceAssistantService"
    private val NOTIFICATION_CHANNEL_ID = "VoiceAssistantChannel"
    private val NOTIFICATION_ID = 101

    private var speechRecognizer: SpeechRecognizer? = null
    private var speechRecognizerIntent: Intent? = null
    private var eventSink: EventChannel.EventSink? = null

    private var flutterEngine: FlutterEngine? = null

    companion object {
        var eventSinkStatic: EventChannel.EventSink? = null
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "VoiceAssistantService onCreate")
        createNotificationChannel()
        startForeground(createNotification())

        flutterEngine = FlutterEngine(this)
        flutterEngine?.dartExecutor?.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )

        // FIX 1: Safely access binaryMessenger to prevent nullability mismatch
        val binaryMessenger = flutterEngine?.dartExecutor?.binaryMessenger
        if (binaryMessenger != null) {
            EventChannel(binaryMessenger, "com.assistlens.app/voice_events")
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                        eventSink = sink
                        eventSinkStatic = sink
                        Log.d(TAG, "EventChannel onListen")
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                        eventSinkStatic = null
                        Log.d(TAG, "EventChannel onCancel")
                    }
                })
        } else {
            Log.e(TAG, "FlutterEngine binaryMessenger is null. EventChannel not initialized.")
        }

        MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger ?: throw IllegalStateException("Binary messenger is null after FlutterEngine init"), "com.assistlens.app/voice_service")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startVoiceService" -> {
                        startListening()
                        result.success(null)
                    }
                    "stopVoiceService" -> {
                        stopListening()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        initSpeechRecognizer()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "VoiceAssistantService onStartCommand")
        startListening()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "VoiceAssistantService onDestroy")
        stopListening()
        flutterEngine?.destroy()
        eventSink = null
        eventSinkStatic = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Voice Assistant Service Channel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            // FIX 2: R is now imported
            .setContentTitle("Assist Lens")
            .setContentText("Listening for commands...")
            .setSmallIcon(R.mipmap.ic_launcher) // FIX 2: Use R.mipmap.ic_launcher
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun startForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // FIX 3: Use ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE explicitly
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun initSpeechRecognizer() {
        if (SpeechRecognizer.isRecognitionAvailable(this)) {
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
            speechRecognizer?.setRecognitionListener(this)
            speechRecognizerIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            }
        } else {
            Log.e(TAG, "Speech recognition not available on this device.")
            eventSink?.error("SPEECH_NOT_AVAILABLE", "Speech recognition not available", null)
        }
    }

    private fun startListening() {
        if (speechRecognizer != null) {
            stopListening()
            speechRecognizer?.startListening(speechRecognizerIntent)
            Log.d(TAG, "SpeechRecognizer started listening.")
        } else {
            Log.e(TAG, "SpeechRecognizer is null, cannot start listening.")
            eventSink?.error("SPEECH_RECOGNIZER_NULL", "Speech recognizer not initialized", null)
        }
    }

    private fun stopListening() {
        speechRecognizer?.stopListening()
        speechRecognizer?.cancel()
        Log.d(TAG, "SpeechRecognizer stopped listening.")
    }

    override fun onReadyForSpeech(params: android.os.Bundle?) {
        Log.d(TAG, "onReadyForSpeech")
        eventSink?.success("LISTENING_STARTED")
    }

    override fun onBeginningOfSpeech() {
        Log.d(TAG, "onBeginningOfSpeech")
    }

    override fun onRmsChanged(rmsdB: Float) {
        // Log.d(TAG, "onRmsChanged: $rmsdB")
    }

    override fun onBufferReceived(buffer: ByteArray?) {
        // Log.d(TAG, "onBufferReceived")
    }

    override fun onEndOfSpeech() {
        Log.d(TAG, "onEndOfSpeech")
        startListening()
    }

    override fun onError(error: Int) {
        val errorMessage = when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
            SpeechRecognizer.ERROR_CLIENT -> "Client side error"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Insufficient permissions"
            SpeechRecognizer.ERROR_NETWORK -> "Network error"
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
            SpeechRecognizer.ERROR_NO_MATCH -> "No match found"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognition service busy"
            SpeechRecognizer.ERROR_SERVER -> "Server error"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech input"
            else -> "Unknown speech recognition error"
        }
        Log.e(TAG, "onError: $errorMessage ($error)")
        eventSink?.error("SPEECH_ERROR", errorMessage, error)
        startListening()
    }

    override fun onResults(results: android.os.Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (!matches.isNullOrEmpty()) {
            val recognizedText = matches[0]
            Log.d(TAG, "onResults: $recognizedText")
            eventSink?.success(recognizedText)
        }
        startListening()
    }

    override fun onPartialResults(partialResults: android.os.Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (!matches.isNullOrEmpty()) {
            val partialText = matches[0]
            Log.d(TAG, "onPartialResults: $partialText")
            eventSink?.success(partialText)
        }
    }

    override fun onEvent(eventType: Int, params: android.os.Bundle?) {
        Log.d(TAG, "onEvent: $eventType")
    }
}
