import argparse

import logging

import time

from datetime import datetime

import os

import threading

import sys

#!/usr/bin/evn python3

import socket

import numpy as np

import io

import json

import requests

import speech_recognition as sr 

import base64

from typing import Optional, Dict, List, Tuple

import queue # Added for AudioSystem speech queue



# --- API Key Configuration ---

# It's recommended to set these as environment variables for security

# It's recommended to set these as environment variables for security

GEMINI_API_KEY = "AIzaSyBGBCH8LciYNjGAh04_8aL-i8a18NCo5CM"

OPENWEATHER_API_KEY = "1c745e325c0cd04629e6194f9e309872"



# Conditional imports for hardware and vision components

try:

    import RPi.GPIO as GPIO

    HAS_GPIO = True

except ImportError:

    HAS_GPIO = False

    # If GPIO is not available, provide a mock object to prevent crashes

    class MockGPIO:

        BCM = None

        IN = None

        OUT = None

        PUD_UP = None

        HIGH = None

        LOW = None

        FALLING = None

        @staticmethod

        def setmode(mode): pass

        @staticmethod

        def setup(pin, mode, pull_up_down=None): pass

        @staticmethod

        def output(pin, value): pass

        @staticmethod

        def input(pin): return 0 # Simulate low

        @staticmethod

        def add_event_detect(pin, edge, callback=None, bouncetime=None): pass

        @staticmethod

        def remove_event_detect(pin): pass

        @staticmethod

        def cleanup(): pass

        @staticmethod

        def PWM(pin, frequency): return MockPWM() # Mock PWM for buzzer

    

    class MockPWM:

        @staticmethod

        def start(dc): pass

        @staticmethod

        def ChangeDutyCycle(dc): pass

        @staticmethod

        def ChangeFrequency(freq): pass

        @staticmethod

        def stop(): pass



    GPIO = MockGPIO()

    logging.warning("RPi.GPIO not found. Hardware features will be disabled. Using mock GPIO.")



try:

    from picamera2 import Picamera2

    HAS_CAMERA = True

except ImportError:

    HAS_CAMERA = False

    logging.warning("Picamera2 not found. Camera features will be disabled.")



try:

    from pynput import keyboard

    HAS_PYNPUT = True

except ImportError:

    HAS_PYNPUT = False

    logging.warning("pynput not found. Keyboard monitoring will be disabled. Install with 'pip install pynput'")



try:

    import cv2

    HAS_OPENCV = True

except ImportError:

    HAS_OPENCV = False

    logging.warning("OpenCV (cv2) not found. Computer vision features will be limited. Install with 'pip install opencv-python'")



try:

    import pytesseract

    HAS_TESSERACT = True

except ImportError:

    HAS_TESSERACT = False

    logging.warning("pytesseract not found. Text reading (OCR) will be limited. Install with 'pip install pytesseract'")



try:

    import speech_recognition as sr

    HAS_SPEECH_RECOGNITION = True

except ImportError:

    HAS_SPEECH_RECOGNITION = False

    logging.warning("speech_recognition not found. Voice input will be disabled. Install with 'pip install SpeechRecognition'")



try:

    import vosk

    HAS_VOSK = True

except ImportError:

    HAS_VOSK = False

    logging.warning("vosk not found. Offline speech recognition will be unavailable. Install with 'pip install vosk'")



try:

    import pyttsx3

    HAS_PYTTSX3 = True

except ImportError:

    HAS_PYTTSX3 = False # Moved this assignment here for global definition

    logging.warning("pyttsx3 not found. Text-to-speech will be disabled.")





# Placeholder for SocketIO setup (assuming Flask-SocketIO)

try:

    from flask import Flask, render_template, Response, request, jsonify

    from flask_socketio import SocketIO, emit

    HAS_FLASK_SOCKETIO = True

except ImportError:

    HAS_FLASK_SOCKETIO = False

    logging.error("Flask or Flask-SocketIO not found. Web interface will not function. Install with 'pip install Flask Flask-SocketIO'")



# --- Logging Setup ---

# Set logging level for the AssistiveLens logger to DEBUG for detailed output

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')

logger = logging.getLogger('AssistiveLens')

# Set this logger to DEBUG level to get detailed output from _get_image_data and gen_frames

logger.setLevel(logging.DEBUG)



# --- Utility Functions ---

def is_online(host="8.8.8.8", port=53, timeout=3):

    """

    Check for internet connectivity by trying to connect to Google's DNS.

    Returns:

        bool: True if connection is successful, False otherwise.

    """

    try:

        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

        s.settimeout(timeout)

        s.connect((host, port))

        s.close() 

        return True

    except (socket.error, OSError) as ex:

        logger.warning(f"Internet connectivity check failed: {ex}")

        return False

    except Exception as e:

        logger.error(f"An unexpected error occurred during connectivity check: {e}")

        return False



# --- Global Flask and SocketIO instances ---

app = Flask(__name__) if HAS_FLASK_SOCKETIO else None

#socketio = SocketIO(app) if HAS_FLASK_SOCKETIO else None

socketio = SocketIO(app, async_mode='eventlet', cors_allowed_origins="*") if HAS_FLASK_SOCKETIO else None

# --- Hardware System Class (Raspberry Pi GPIO, Sensors) ---

class HardwareSystem:

    """Manages Raspberry Pi GPIO pins for LED, Buzzer, Ultrasonic Sensor, and 4-button gesture input."""

    def __init__(self, enable_distance_sensor: bool = True):

        self.pins_setup = False

        self.enable_distance_sensor = enable_distance_sensor



        # GPIO Pin Definitions (BCM numbering)

        self.led_pin = 18       # Status LED

        self.buzzer_pin = 19    # Buzzer

        self.trigger_pin = 23   # Ultrasonic Sensor Trigger (Trig)

        self.echo_pin = 24      # Ultrasonic Sensor Echo (Echo) - NOTE: Requires voltage divider!



        self.status_led_on = False # Keep track of LED state



        # 4-Button Configuration (New Pin Assignments for clarity)

        self.button_pins = {

            'BUTTON_1': 17,  # Main Action (Describe, Read, Detect)

            'BUTTON_2': 27,  # Navigation (Location, Weather, Toggle Nav)

            'BUTTON_3': 22,  # Alerts/Utility (Obstacle, Buzzer, Emergency)

            'BUTTON_4': 2   # Voice/Accessibility (Toggle Voice, Repeat, Stop Speaking)

        }



        # Button State Tracking for Gestures

        self.button_states = {

            pin: {'last_press_time': 0, 'press_count': 0, 'press_start_time': 0, 'is_pressed': False, 'timer': None}

            for pin in self.button_pins.values()

        }

        self.DOUBLE_TAP_WINDOW = 0.4  # seconds

        self.LONG_PRESS_DURATION = 1.0  # seconds



        if HAS_GPIO:

            try:

                GPIO.setmode(GPIO.BCM)

                GPIO.setup(self.led_pin, GPIO.OUT)

                GPIO.setup(self.buzzer_pin, GPIO.OUT)

                

                if self.enable_distance_sensor:

                    GPIO.setup(self.trigger_pin, GPIO.OUT)

                    GPIO.setup(self.echo_pin, GPIO.IN)

                    logger.info(f"HardwareSystem: Ultrasonic sensor (Trig:{self.trigger_pin}, Echo:{self.echo_pin}) configured.")

                else:

                    logger.info("HardwareSystem: Ultrasonic sensor disabled by configuration.")



                # Setup Buttons for input with pull-up resistors

                for name, pin in self.button_pins.items():

                    GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)

                    # Add event detection for both rising and falling edges to track press start/end

                    GPIO.add_event_detect(pin, GPIO.BOTH, callback=self._button_event_callback, bouncetime=50) # Increased bouncetime for stability

                    logger.info(f"HardwareSystem: Button '{name}' on GPIO {pin} configured.")



                # Ensure initial state is off

                GPIO.output(self.led_pin, GPIO.LOW)

                GPIO.output(self.buzzer_pin, GPIO.LOW)



                self.pins_setup = True

                logger.info("HardwareSystem: GPIO pins initialized successfully.")

            except Exception as e:

                logger.error(f"HardwareSystem: GPIO setup failed: {e}. Hardware features may be limited.")

        else:

            logger.warning("HardwareSystem: RPi.GPIO not available. Hardware features are disabled.")



    def _button_event_callback(self, channel):

        """Callback for GPIO button events (both rising and falling edges)."""

        current_time = time.time()

        button_state = self.button_states[channel]



        if GPIO.input(channel) == GPIO.LOW:  # Button is pressed (falling edge)

            button_state['is_pressed'] = True

            button_state['press_start_time'] = current_time

            # Start a timer to check for long press

            if button_state['timer']:

                button_state['timer'].cancel() # Cancel any pending timer for double tap if button pressed again

            button_state['timer'] = threading.Timer(self.LONG_PRESS_DURATION, self._long_press_detected, args=[channel])

            button_state['timer'].start()

            logger.debug(f"Button {channel} pressed.")

        else:  # Button is released (rising edge)

            button_state['is_pressed'] = False

            if button_state['timer']:

                button_state['timer'].cancel() # Cancel long press timer if released before duration



            press_duration = current_time - button_state['press_start_time']

            

            if press_duration < self.LONG_PRESS_DURATION: # Not a long press, process as short press

                logger.debug(f"Button {channel} released after short press ({press_duration:.3f}s).")

                if (current_time - button_state['last_press_time']) < self.DOUBLE_TAP_WINDOW:

                    button_state['press_count'] += 1

                    if button_state['press_count'] == 2:

                        self._dispatch_gesture(channel, 'double_tap')

                        button_state['press_count'] = 0 # Reset for next gesture

                        button_state['last_press_time'] = 0

                else:

                    button_state['press_count'] = 1

                    button_state['last_press_time'] = current_time

                    # Start a timer to confirm single press if no second press occurs

                    threading.Timer(self.DOUBLE_TAP_WINDOW, self._check_single_press, args=[channel]).start()

            # If it was a long press, _long_press_detected would have handled it.



    def _check_single_press(self, channel):

        """Checks if a single press was confirmed after the double-tap window."""

        button_state = self.button_states[channel]

        current_time = time.time()

        if (button_state['press_count'] == 1 and 

            (current_time - button_state['last_press_time']) >= self.DOUBLE_TAP_WINDOW):

            self._dispatch_gesture(channel, 'single_press')

            button_state['press_count'] = 0 # Reset

            button_state['last_press_time'] = 0



    def _long_press_detected(self, channel):

        """Called when a long press is detected."""

        button_state = self.button_states[channel]

        if button_state['is_pressed']: # Ensure button is still held down

            logger.debug(f"Button {channel} long press detected.")

            self._dispatch_gesture(channel, 'long_press')

            button_state['press_count'] = 0 # Reset counts after a long press

            button_state['last_press_time'] = 0

            button_state['is_pressed'] = False # Simulate release for state machine consistency



    def _dispatch_gesture(self, channel, gesture_type):

        """Dispatches the detected gesture to the system instance."""

        button_name = next(name for name, pin in self.button_pins.items() if pin == channel)

        logger.info(f"Gesture detected: {button_name} - {gesture_type}")

        # Emit to SocketIO for web interface feedback (optional, but good for debugging/status)

        if socketio:

            socketio.emit('button_gesture', {'button': button_name, 'gesture': gesture_type})

        

        # Pass control to the main system handler

        system_instance.handle_button_gesture(button_name, gesture_type)



    def set_status_led(self, on: bool):

        """Turns the status LED on or off."""

        if self.pins_setup:

            GPIO.output(self.led_pin, GPIO.HIGH if on else GPIO.LOW)

            self.status_led_on = on

            logger.info(f"HardwareSystem: Status LED {'ON' if on else 'OFF'}")

        else:

            logger.warning("HardwareSystem: Cannot control LED, GPIO not set up.")



    def toggle_status_led(self):

        """Toggles the status LED on/off."""

        self.set_status_led(not self.status_led_on)



    def trigger_buzzer(self, duration: float = 0.1):

        """Triggers the buzzer for a specified duration."""

        if self.pins_setup:

            try:

                GPIO.output(self.buzzer_pin, GPIO.HIGH)

                time.sleep(duration)

                GPIO.output(self.buzzer_pin, GPIO.LOW)

                logger.info(f"HardwareSystem: Buzzer triggered for {duration}s.")

            except Exception as e:

                logger.error(f"HardwareSystem: Error triggering buzzer: {e}")

        else:

            logger.warning("HardwareSystem: Cannot trigger buzzer, GPIO not set up.")



    def get_distance(self) -> float:

        """Gets distance reading from ultrasonic sensor (HC-SR04). Returns distance in cm."""

        if not self.pins_setup or not self.enable_distance_sensor:

            return 50.0  # Mock distance if hardware not available/enabled



        try:

            # Ensure trigger is low before pulse

            GPIO.output(self.trigger_pin, False)

            time.sleep(0.000002)



            # Send 10us pulse to trigger

            GPIO.output(self.trigger_pin, True)

            time.sleep(0.00001)

            GPIO.output(self.trigger_pin, False)



            pulse_start_time = time.time()

            pulse_end_time = time.time()



            timeout_start = time.time()

            # Wait for echo to go HIGH

            while GPIO.input(self.echo_pin) == 0:

                pulse_start_time = time.time()

                if time.time() - timeout_start > 0.02: # 20ms timeout for pulse start

                    logger.warning("HardwareSystem: Ultrasonic: Echo pulse start timeout.")

                    return -1.0

            

            timeout_end = time.time()

            # Wait for echo to go LOW

            while GPIO.input(self.echo_pin) == 1:

                pulse_end_time = time.time()

                if time.time() - timeout_end > 0.04: # 40ms timeout for pulse end (total 60ms)

                    logger.warning("HardwareSystem: Ultrasonic: Echo pulse end timeout.")

                    return -1.0



            pulse_duration = pulse_end_time - pulse_start_time

            distance = pulse_duration * 17150  # Speed of sound (34300 cm/s / 2)

            distance = round(distance, 2)



            # Filter out invalid readings (e.g., too close, too far, or errors)

            if 2 <= distance <= 400:

                return distance

            else:

                logger.warning(f"HardwareSystem: Ultrasonic: Invalid distance reading: {distance} cm. Returning -1.0")

                return -1.0

        except Exception as e:

            logger.error(f"HardwareSystem: Error getting distance: {e}")

            return -1.0



    def cleanup(self):

        """Cleans up GPIO settings."""

        if self.pins_setup and HAS_GPIO:

            GPIO.cleanup()

            logger.info("HardwareSystem: GPIO cleanup complete.")



# --- AI Vision System Class (Camera, Image Processing, LLM Integration) ---

class AIVisionSystem:

    """Manages camera operations and AI vision tasks."""

    def __init__(self, socketio_instance, enable_camera: bool = True):

        self.socketio = socketio_instance

        self.enable_camera = enable_camera

        self.picam2 = None

        self.last_capture_time = 0



        # API and Model Configuration

        self.gemini_api_key = GEMINI_API_KEY

        self.gemini_vision_model = "gemini-2.0-flash" # Model for multimodal inputs

        self.gemini_text_model = "gemini-2.0-flash" # Model for text-only inputs

        if not self.gemini_api_key:

            logger.warning("GEMINI_API_KEY environment variable not set. Online AI features will be disabled.")



        if self.enable_camera and HAS_CAMERA:

            try:

                self.picam2 = Picamera2()

                camera_config = self.picam2.create_video_configuration(main={"size": (640, 480)})

                self.picam2.configure(camera_config)

                self.picam2.options["quality"] = 90 # Set JPEG quality for captures

                self.picam2.start()

                logger.info("AIVisionSystem: Camera initialized.")

                time.sleep(2) # Warm-up time

            except Exception as e:

                logger.error(f"AIVisionSystem: Camera initialization failed: {e}. Camera features disabled.")

                self.enable_camera = False

        else:

            logger.warning("AIVisionSystem: Camera not available or disabled by configuration.")



    def _get_image_data(self) -> Optional[str]:

        """

        Captures an image and returns it as base64 encoded JPEG.

        Returns None if camera is not enabled/initialized or an error occurs.

        """

        if not self.enable_camera or self.picam2 is None:

            logger.warning("AIVisionSystem: Camera not enabled or initialized. Cannot capture image. Returning None.")

            return None



        try:

            array = self.picam2.capture_array()

            logger.debug(f"AIVisionSystem: Captured array shape: {array.shape}, dtype: {array.dtype}") # Debug log for array info

            

            if HAS_OPENCV:

                # picamera2.capture_array() usually returns RGB or XBGR.

                # XBGR is effectively BGR, so if 3 channels, we assume BGR and proceed.

                # If grayscale (2D array), convert to BGR.

                if len(array.shape) == 2:  # Grayscale image (H, W)

                    array_bgr = cv2.cvtColor(array, cv2.COLOR_GRAY2BGR)

                    logger.debug("AIVisionSystem: Converted grayscale (2D) to BGR.")

                elif array.shape[2] == 3:  # Color image (H, W, 3) - assume it's already BGR or compatible

                    array_bgr = array

                    logger.debug("AIVisionSystem: Image is 3-channel, using directly (assuming BGR/compatible).")

                elif array.shape[2] == 4:  # Color image with Alpha channel (H, W, 4)

                    array_bgr = cv2.cvtColor(array, cv2.COLOR_RGBA2BGR)

                    logger.debug("AIVisionSystem: Converted 4-channel (RGBA) to BGR.")

                else:

                    logger.error(f"AIVisionSystem: Unexpected image array shape: {array.shape}. Returning None.")

                    return None



                ret, buffer = cv2.imencode('.jpg', array_bgr)

                if not ret or buffer.size == 0: # Check buffer size in addition to 'ret'

                    logger.error("AIVisionSystem: Failed to encode image to JPEG or resulting buffer is empty. Ret: %s, Buffer size: %s. Returning None.", ret, buffer.size if ret else 'N/A')

                    return None

                

                b64_image = base64.b64encode(buffer).decode('utf-8')

                logger.debug("AIVisionSystem: Successfully encoded image to base64.")

                return f"data:image/jpeg;base64,{b64_image}"

            else:

                logger.warning("AIVisionSystem: OpenCV not found for JPEG encoding. Cannot reliably capture image. Returning None.")

                return None



        except Exception as e:

            logger.error(f"AIVisionSystem: Error capturing or processing image: {e}. Returning None.")

            return None



    def describe_scene(self, prompt_suffix: str = "") -> str:

        """Captures an image and uses an LLM to describe the scene."""

        logger.info("AIVisionSystem: Describing scene...")

        if not is_online() or not self.gemini_api_key:

            offline_msg = "Cannot describe scene. Internet connection or AI service is unavailable."

            self.socketio.emit('speech_output', {'message': offline_msg}) # Still emit for web log

            system_instance.audio_system.speak(offline_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = offline_msg

            return "Scene description unavailable offline."



        image_data = self._get_image_data()

        if image_data:

            try:

                base_prompt = "Describe the scene in detail, focusing on objects, colors, and overall environment."

                full_prompt = f"{base_prompt} {prompt_suffix}".strip()

                response_text = self._call_llm_vision(full_prompt, image_data)

                self.socketio.emit('speech_output', {'message': f"Scene: {response_text}"}) # Still emit for web log

                system_instance.audio_system.speak(f"Scene: {response_text}") # Now also speak directly on Pi

                # Store the last spoken response

                system_instance.last_spoken_response = f"Scene: {response_text}"

                return f"Scene described: {response_text}"

            except Exception as e:

                logger.error(f"AIVisionSystem: Error describing scene with LLM: {e}")

                error_msg = "Sorry, I couldn't describe the scene at the moment."

                self.socketio.emit('speech_output', {'message': error_msg}) # Still emit for web log

                system_instance.audio_system.speak(error_msg) # Now also speak directly on Pi

                system_instance.last_spoken_response = error_msg

                return "Failed to describe scene."

        else:

            no_image_msg = "Sorry, I can't capture an image to describe the scene."

            self.socketio.emit('speech_output', {'message': no_image_msg}) # Still emit for web log

            system_instance.audio_system.speak(no_image_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = no_image_msg

            return "No image captured for scene description."



    def read_text_from_image(self) -> str:

        """Captures an image and uses OCR to read text, with online/offline fallback."""

        logger.info("AIVisionSystem: Reading text from image...")



        if not self.enable_camera or self.picam2 is None:

            no_image_msg = "Sorry, I can't capture an image to read text."

            self.socketio.emit('speech_output', {'message': no_image_msg}) # Still emit for web log

            system_instance.audio_system.speak(no_image_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = no_image_msg

            return "No image captured for text reading."



        # --- Online Path (Gemini Vision) ---

        if is_online() and self.gemini_api_key:

            logger.info("AIVisionSystem: Using online AI for text reading.")

            image_data = self._get_image_data()

            if image_data:

                try:

                    prompt = "Read all the text in this image. If there is no text, say 'No text found'."

                    response_text = self._call_llm_vision(prompt, image_data)

                    response_msg = f"I read: {response_text.strip()}"

                    self.socketio.emit('speech_output', {'message': response_msg}) # Still emit for web log

                    system_instance.audio_system.speak(response_msg) # Now also speak directly on Pi

                    system_instance.last_spoken_response = response_msg

                    return f"Text read (online): {response_text.strip()}"

                except Exception as e:

                    logger.error(f"AIVisionSystem: Error reading text with LLM, falling back to offline: {e}")

                    # Fall through to offline method if online fails

            else:

                logger.warning("AIVisionSystem: Could not get image for online OCR, falling back.")



        # --- Offline Path (Tesseract) ---

        logger.info("AIVisionSystem: Using offline Tesseract for text reading.")

        if not HAS_TESSERACT or not HAS_OPENCV:

            no_ocr_msg = "Offline text reading is not available. Please install Tesseract OCR and OpenCV."

            self.socketio.emit('speech_output', {'message': no_ocr_msg}) # Still emit for web log

            system_instance.audio_system.speak(no_ocr_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = no_ocr_msg

            return "Text reading not available."



        try:

            array = self.picam2.capture_array()

            # Convert to grayscale for better OCR performance

            if array.shape[2] == 4:

                array = cv2.cvtColor(array, cv2.COLOR_RGBA2BGR)

            gray_image = cv2.cvtColor(array, cv2.COLOR_BGR2GRAY)

            text = pytesseract.image_to_string(gray_image)

            

            if text.strip():

                response_msg = f"I read: {text.strip()}"

                self.socketio.emit('speech_output', {'message': response_msg}) # Still emit for web log

                system_instance.audio_system.speak(response_msg) # Now also speak directly on Pi

                system_instance.last_spoken_response = response_msg

                return f"Text read (offline): {text.strip()}"

            else:

                no_text_msg = "No readable text found in the image."

                self.socketio.emit('speech_output', {'message': no_text_msg}) # Still emit for web log

                system_instance.audio_system.speak(no_text_msg) # Now also speak directly on Pi

                system_instance.last_spoken_response = no_text_msg

                return "No text found."

        except Exception as e:

            logger.error(f"AIVisionSystem: Error reading text with Tesseract: {e}")

            error_msg = "Sorry, I encountered an error while trying to read text."

            self.socketio.emit('speech_output', {'message': error_msg}) # Still emit for web log

            system_instance.audio_system.speak(error_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = error_msg

            return "Failed to read text."



    def detect_objects(self, prompt_suffix: str = "") -> str:

        """Captures an image and uses an LLM to detect objects."""

        logger.info("AIVisionSystem: Detecting objects...")

        if not is_online() or not self.gemini_api_key:

            offline_msg = "Cannot detect objects. Internet connection or AI service is unavailable."

            self.socketio.emit('speech_output', {'message': offline_msg}) # Still emit for web log

            system_instance.audio_system.speak(offline_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = offline_msg

            return "Object detection unavailable offline."



        image_data = self._get_image_data()

        if image_data:

            try:

                base_prompt = "List all prominent objects you see in this image. Be concise."

                full_prompt = f"{base_prompt} {prompt_suffix}".strip()

                response_text = self._call_llm_vision(full_prompt, image_data)

                response_msg = f"Objects detected: {response_text}"

                self.socketio.emit('speech_output', {'message': response_msg}) # Still emit for web log

                system_instance.audio_system.speak(response_msg) # Now also speak directly on Pi

                system_instance.last_spoken_response = response_msg

                return f"Objects detected: {response_text}"

            except Exception as e:

                logger.error(f"AIVisionSystem: Error detecting objects with LLM: {e}")

                error_msg = "Sorry, I couldn't detect objects at the moment."

                self.socketio.emit('speech_output', {'message': error_msg}) # Still emit for web log

                system_instance.audio_system.speak(error_msg) # Now also speak directly on Pi

                system_instance.last_spoken_response = error_msg

                return "Failed to detect objects."

        else:

            no_image_msg = "Sorry, I can't capture an image to detect objects."

            self.socketio.emit('speech_output', {'message': no_image_msg}) # Still emit for web log

            system_instance.audio_system.speak(no_image_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = no_image_msg

            return "No image captured for object detection."



    def recognize_face(self) -> str:

        """Captures an image and attempts face recognition (placeholder)."""

        logger.info("AIVisionSystem: Attempting face recognition...")

        if not is_online() or not self.gemini_api_key:

            offline_msg = "Cannot recognize faces. Internet connection or AI service is unavailable."

            self.socketio.emit('speech_output', {'message': offline_msg}) # Still emit for web log

            system_instance.audio_system.speak(offline_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = offline_msg

            return "Face recognition unavailable offline."



        image_data = self._get_image_data()

        if image_data:

            try:

                # In a real system, you'd send image_data to a face recognition model/API

                # This is a placeholder for the actual logic.

                prompt = "Is there a human face in this image? If so, describe any identifiable features. Do not attempt to identify individuals."

                response_text = self._call_llm_vision(prompt, image_data)

                if "face" in response_text.lower():

                    response_msg = f"I see a face. Description: {response_text}"

                    self.socketio.emit('speech_output', {'message': response_msg}) # Still emit for web log

                    system_instance.audio_system.speak(response_msg) # Now also speak directly on Pi

                else:

                    response_msg = "I don't detect a human face."

                    self.socketio.emit('speech_output', {'message': response_msg}) # Still emit for web log

                    system_instance.audio_system.speak(response_msg) # Now also speak directly on Pi

                system_instance.last_spoken_response = response_msg

                return f"Face recognition attempt: {response_text}"

            except Exception as e:

                logger.error(f"AIVisionSystem: Error during face recognition: {e}")

                error_msg = "Sorry, I couldn't perform face recognition at this time."

                self.socketio.emit('speech_output', {'message': error_msg}) # Still emit for web log

                system_instance.audio_system.speak(error_msg) # Now also speak directly on Pi

                system_instance.last_spoken_response = error_msg

                return "Face recognition failed."

        else:

            no_image_msg = "Sorry, I can't capture an image for face recognition."

            self.socketio.emit('speech_output', {'message': no_image_msg}) # Still emit for web log

            system_instance.audio_system.speak(no_image_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = no_image_msg

            return "No image captured for face recognition."



    def _call_llm_text(self, prompt: str) -> str:

        """

        Calls a text-only LLM like Gemini Pro.

        """

        if not self.gemini_api_key:

            logger.warning("GEMINI_API_KEY not set. Using mock LLM response.")

            mock_response = "This is a simulated AI response. Please set GEMINI_API_KEY for real AI."

            system_instance.audio_system.speak(mock_response) # Speak mock response

            return mock_response



        try:

            headers = {'Content-Type': 'application/json'}

            payload = {

                "contents": [{"parts": [{"text": prompt}]}],

                "generationConfig": {

                    "temperature": 0.5,

                    "maxOutputTokens": 125,

                },

                "safetySettings": [

                    {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},

                    {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},

                    {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},

                    {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"}

                ]

            }



            api_url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.gemini_text_model}:generateContent?key={self.gemini_api_key}"

            response = requests.post(api_url, headers=headers, data=json.dumps(payload), timeout=20)

            response.raise_for_status()

            

            result = response.json()

            if result and result.get('candidates'):

                text = result['candidates'][0]['content']['parts'][0]['text']

                return text

            else:

                logger.warning(f"LLM text call received unexpected response structure: {result}")

                return "No coherent response from AI."



        except requests.exceptions.RequestException as e:

            logger.error(f"Error calling Gemini Text API: {e}")

            return "Error communicating with AI service."

        except Exception as e:

            logger.error(f"Unexpected error in LLM text call: {e}")

            return "An unexpected error occurred with the AI service."



    def _call_llm_vision(self, prompt: str, image_data: str) -> str:

        """

        Simulates an API call to a multimodal LLM like Gemini Vision.

        Replace with actual API call if you have Gemini API access.

        """

        if not self.gemini_api_key:

            logger.warning("GEMINI_API_KEY not set. Using mock LLM response.")

            mock_response = "This is a simulated AI response. Please set GEMINI_API_KEY for real AI."

            system_instance.audio_system.speak(mock_response) # Speak mock response

            return mock_response



        # Example structure for Gemini API call (conceptual, adjust to actual SDK/REST)

        # Note: This is a simplified direct fetch, in production you'd use a robust client library.

        try:

            headers = {

                'Content-Type': 'application/json',

            }

            # Remove "data:image/jpeg;base64," prefix for the actual data

            image_b64_only = image_data.split(',')[1] if ',' in image_data else image_data



            payload = {

                "contents": [

                    {

                        "parts": [

                            {"text": prompt},

                            {"inlineData": {"mimeType": "image/jpeg", "data": image_b64_only}}

                        ]

                    }

                ],

                "generationConfig": {

                    "temperature": 0.4,

                    "topK": 32,

                    "topP": 1,

                    "maxOutputTokens": 200,

                    "stopSequences": []

                },

                "safetySettings": [

                    {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},

                    {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},

                    {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},

                    {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"}

                ]

            }



            api_url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.gemini_vision_model}:generateContent?key={self.gemini_api_key}"

            response = requests.post(api_url, headers=headers, data=json.dumps(payload), timeout=20)

            response.raise_for_status() # Raise HTTPError for bad responses (4xx or 5xx)

            

            result = response.json()

            if result and result.get('candidates'):

                text = result['candidates'][0]['content']['parts'][0]['text']

                return text

            else:

                logger.warning(f"LLM call received unexpected response structure: {result}")

                return "No coherent response from AI."



        except requests.exceptions.RequestException as e:

            logger.error(f"Error calling Gemini Vision API: {e}")

            return "Error communicating with AI vision service."

        except json.JSONDecodeError:

            logger.error("Failed to decode JSON response from LLM.")

            return "Invalid AI response."

        except Exception as e:

            logger.error(f"Unexpected error in LLM vision call: {e}")

            return "An unexpected error occurred with AI vision."



    def cleanup(self):

        """Stops the camera."""

        if self.enable_camera and self.picam2:

            try:

                self.picam2.stop()

                self.picam2.close()

                logger.info("AIVisionSystem: Camera stopped.")

            except Exception as e:

                logger.error(f"AIVisionSystem: Error stopping camera: {e}")



# --- Location System Class (Placeholder) ---

class LocationSystem:

    """Manages location and weather services."""

    def __init__(self, socketio_instance, ai_vision_system: AIVisionSystem, enable_location: bool = True):

        self.socketio = socketio_instance

        self.ai_vision = ai_vision_system # Need access to the AI system for descriptions

        self.enable_location = enable_location

        self.openweather_api_key = OPENWEATHER_API_KEY

        

        # New: Store client-provided location

        self.client_latitude: Optional[float] = None

        self.client_longitude: Optional[float] = None



        if not self.openweather_api_key:

            logger.warning("OPENWEATHER_API_KEY not set. Weather features will be disabled.")

        # GPIO pin for a GPS PPS signal, moved to an unused pin

        self.location_sensor_pin = 6 # BCM 6 (physical pin 22), was 24, now moved to avoid conflict

        

        if self.enable_location and HAS_GPIO:

            try:

                GPIO.setup(self.location_sensor_pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)

                # You might add an event detect here if a GPS module provides a pulse-per-second (PPS) signal

                # GPIO.add_event_detect(self.location_sensor_pin, GPIO.FALLING, callback=self._handle_location_pulse, bouncetime=200)

                logger.info(f"LocationSystem: Location sensor pin GPIO {self.location_sensor_pin} configured.")

            except Exception as e:

                logger.error(f"LocationSystem: Failed to set up location sensor on GPIO {self.location_sensor_pin}: {e}")

        else:

            logger.warning("LocationSystem: Location sensor disabled or GPIO not available.")



    def update_client_location(self, lat: float, lon: float):

        """Updates the stored client location."""

        self.client_latitude = lat

        self.client_longitude = lon

        logger.info(f"LocationSystem: Client location updated to Lat: {lat}, Lon: {lon}")



    def get_current_location(self) -> Optional[Dict]:

        """

        Returns the current location as a dictionary, prioritizing client data.

        Returns None if location cannot be determined.

        """

        if not self.enable_location:

            logger.warning("Location services are disabled by configuration.")

            return None

        

        # Use client-provided location if available

        if self.client_latitude is not None and self.client_longitude is not None:

            logger.info("LocationSystem: Using client-provided location.")

            return {

                'city': 'Client City (approx)', # We don't have city/country directly from client lat/lon

                'country': 'Client Country (approx)',

                'lat': self.client_latitude,

                'lon': self.client_longitude

            }



        # Fallback to IP-based location if no client location

        if not is_online():

            logger.warning("Cannot get location, no internet connection and no client location provided.")

            return None



        try:

            response = requests.get('http://ip-api.com/json/', timeout=10)

            response.raise_for_status()

            data = response.json()

            if data.get('status') == 'success':

                location_info = {

                    'city': data.get('city', 'Unknown City'),

                    'country': data.get('country', 'Unknown Country'),

                    'lat': data.get('lat'),

                    'lon': data.get('lon')

                }

                logger.info(f"LocationSystem: Location found (IP-based): {location_info['city']}, {location_info['country']}")

                return location_info

            else:

                logger.error(f"LocationSystem: IP-based location API failed: {data.get('message')}")

                return None

        except requests.exceptions.RequestException as e:

            logger.error(f"LocationSystem: Could not get current location via IP: {e}")

            return None



    def announce_location(self):

        """Announces the current location via speech."""

        location_info = self.get_current_location()

        if location_info:

            if self.client_latitude is not None:

                 response_msg = f"Your current approximate location is Latitude {location_info['lat']:.4f}, Longitude {location_info['lon']:.4f}."

            else:

                response_msg = f"You are near {location_info['city']}, {location_info['country']}."

        else:

            response_msg = "Could not determine your current location."

        

        self.socketio.emit('speech_output', {'message': response_msg}) # Still emit for web log

        system_instance.audio_system.speak(response_msg) # Now also speak directly on Pi

        system_instance.last_spoken_response = response_msg

        logger.info(f"LocationSystem: Announcing location: {response_msg}")



    def _get_weather_data(self, lat: float, lon: float) -> Optional[Dict]:

        """Fetches weather data from OpenWeatherMap."""

        if not self.openweather_api_key:

            logger.warning("Cannot get weather, OpenWeatherMap API key not set.")

            return None

        

        api_url = f"https://api.openweathermap.org/data/2.5/weather?lat={lat}&lon={lon}&appid={self.openweather_api_key}&units=metric"

        try:

            response = requests.get(api_url, timeout=10)

            response.raise_for_status()

            logger.info("Successfully fetched weather data.")

            return response.json()

        except requests.exceptions.RequestException as e:

            logger.error(f"Error fetching weather data: {e}")

            return None



    def announce_weather(self):

        """Fetches weather, gets an AI description, and announces it."""

        logger.info("LocationSystem: Announcing weather...")

        if not is_online():

            offline_msg = "Weather information is not available offline."

            self.socketio.emit('speech_output', {'message': offline_msg}) # Still emit for web log

            system_instance.audio_system.speak(offline_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = offline_msg

            return



        location_info = self.get_current_location()

        if not location_info or not location_info.get('lat'):

            no_location_msg = "I need your location to get the weather, but I couldn't find it."

            self.socketio.emit('speech_output', {'message': no_location_msg}) # Still emit for web log

            system_instance.audio_system.speak(no_location_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = no_location_msg

            return



        weather_data = self._get_weather_data(location_info['lat'], location_info['lon'])

        if not weather_data:

            no_weather_msg = "Sorry, I couldn't retrieve the weather data right now."

            self.socketio.emit('speech_output', {'message': no_weather_msg}) # Still emit for web log

            system_instance.audio_system.speak(no_weather_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = no_weather_msg

            return



        try:

            relevant_weather = {

                "description": weather_data.get("weather", [{}])[0].get("description"),

                "temperature_celsius": weather_data.get("main", {}).get("temp"),

                "feels_like_celsius": weather_data.get("main", {}).get("feels_like"),

                "wind_speed_mps": weather_data.get("wind", {}).get("speed"),

                "humidity_percent": weather_data.get("main", {}).get("humidity"),

                "city": weather_data.get("name")

            }

            prompt = (f"You are an assistant for a visually impaired person. Based on the following weather data, "

                      f"provide a simple, helpful, and descriptive summary. Mention what it feels like and suggest "

                      f"if special clothing like a jacket or umbrella is needed. Weather data: {json.dumps(relevant_weather)}")

            weather_description = self.ai_vision._call_llm_text(prompt)

            self.socketio.emit('speech_output', {'message': weather_description}) # Still emit for web log

            system_instance.audio_system.speak(weather_description) # Now also speak directly on Pi

            system_instance.last_spoken_response = weather_description

            logger.info(f"Announced AI-powered weather description.")

        except Exception as e:

            logger.error(f"Failed to get AI weather description: {e}")

            error_msg = "I have the weather data, but I'm having trouble describing it."

            self.socketio.emit('speech_output', {'message': error_msg}) # Still emit for web log

            system_instance.audio_system.speak(error_msg) # Now also speak directly on Pi

            system_instance.last_spoken_response = error_msg



    def _handle_location_pulse(self, channel):

        """Callback for GPS PPS signal (placeholder)."""

        logger.info(f"LocationSystem: GPS PPS pulse detected on channel {channel}")

        # In a real system, this would be used to timestamp GPS fixes or synchronize.



# --- Audio System Class (Speech Output) ---

class AudioSystem:

    """Manages speech output on the Raspberry Pi using a queue to prevent conflicts."""

    def __init__(self, socketio_instance):

        self.socketio = socketio_instance

        self.engine = None

        self.speech_queue = queue.Queue() # Thread-safe queue for speech requests

        self.speech_thread = None

        self._initialize_pyttsx3()



    def _initialize_pyttsx3(self):

        if not HAS_PYTTSX3:

            logger.warning("pyttsx3 not available. Speech output will be disabled.")

            return



        try:

            self.engine = pyttsx3.init()

            

            # Set properties for a more natural and slower voice

            self.engine.setProperty('rate', 175)  # Words per minute (default is often 200, 175 is slower)

            self.engine.setProperty('volume', 1.0) # Volume (0.0 to 1.0)



            voices = self.engine.getProperty('voices')

            

            found_voice = False

            for voice in voices:

                # Prioritize English voices, especially US, or male voices for consistency

                if 'en-us' in voice.id.lower() or 'male' in voice.name.lower():

                    self.engine.setProperty('voice', voice.id)

                    logger.info(f"AudioSystem: pyttsx3 initialized with voice: {voice.name}")

                    found_voice = True

                    break

            if not found_voice:

                logger.info(f"AudioSystem: pyttsx3 initialized with default voice: {self.engine.getProperty('voice')}")

            

            # Start the speech processing thread

            self.speech_thread = threading.Thread(target=self._speech_processor, daemon=True)

            self.speech_thread.start()



        except Exception as e:

            logger.error(f"AudioSystem: Failed to initialize pyttsx3: {e}. Speech output may not work.")

            self.engine = None



    def speak(self, text: str):

        """Sends text to the client for speech synthesis and adds it to the Pi's speech queue."""

        if not self.engine:

            logger.error("AudioSystem: Speech engine not initialized. Cannot speak.")

            return

        if not text:

            logger.warning("AudioSystem: Attempted to speak empty text.")

            return



        logger.info(f"AudioSystem: Queuing speech for Pi: {text[:50]}...") # Log first 50 chars

        self.socketio.emit('speech_output', {'message': text}) # Emit for web log/display

        system_instance.last_spoken_response = text # Update the last spoken response globally

        

        try:

            self.speech_queue.put(text) # Add text to the thread-safe queue

        except Exception as e:

            logger.error(f"AudioSystem: Error adding text to speech queue: {e}")



    def _speech_processor(self):

        """Dedicated thread to process speech requests from the queue."""

        while True:

            text = self.speech_queue.get() # Blocks until an item is available

            if text is None: # Sentinel value to stop the thread

                logger.info("AudioSystem: Speech processor thread stopping.")

                break

            try:

                # Ensure previous speech is stopped before starting new one

                if self.engine._inLoop: 

                    self.engine.stop() 

                self.engine.say(text)

                self.engine.runAndWait()

            except Exception as e:

                logger.error(f"Error in pyttsx3 runAndWait thread: {e}")

            finally:

                self.speech_queue.task_done() # Mark the task as done



    def stop_speaking(self):

        """Sends a command to the client to stop current speech synthesis and stops Pi-side speech."""

        logger.info("AudioSystem: Stopping current speech.")

        self.socketio.emit('stop_speech') # Emit to web client to stop any browser-side speech

        if self.engine:

            try:

                # Stop the current speech without clearing the queue

                self.engine.stop()

            except Exception as e:

                logger.error(f"Error stopping pyttsx3 engine: {e}")



    def cleanup(self):

        """Cleans up the audio system, stopping the speech thread."""

        logger.info("AudioSystem: Initiating cleanup.")

        self.speech_queue.put(None) # Send sentinel to stop the thread

        if self.speech_thread and self.speech_thread.is_alive():

            self.speech_thread.join(timeout=2) # Wait for thread to finish

        if self.engine:

            try:

                # This is a bit tricky, pyttsx3 doesn't have a direct 'quit'

                # after runAndWait. Stopping the thread and waiting is the primary method.

                pass 

            except Exception as e:

                logger.warning(f"AudioSystem: Error during pyttsx3 engine finalization: {e}")





# --- Voice Input System Class ---

class VoiceInputSystem:

    """Manages speech-to-text and intent recognition."""

    def __init__(self, socketio_instance, ai_vision_system: AIVisionSystem):

        global HAS_SPEECH_RECOGNITION 

        self.socketio = socketio_instance

        self.ai_vision = ai_vision_system # For online NLU via Gemini

        self.recognizer = None

        self.microphone = None

        self.is_listening = False

        self.vosk_model = None



        # A map of spoken phrases to system command names.

        # Keys are phrases the user might say.

        # Values are the internal command names used by the system.

        # This is used for both online NLU context and offline keyword matching.

        self.command_map = {

            "describe scene": "describe_scene",

            "read text": "read_text",

            "detect objects": "detect_objects",

            "recognize face": "recognize_face",

            "check obstacle": "check_and_announce_distance",

            "toggle light": "toggle_light",

            "turn on light": "toggle_light", 

            "turn off light": "toggle_light",

            "trigger buzzer": "trigger_buzzer",

            "emergency alert": "emergency_alert",

            "where am i": "announce_location",

            "get location": "announce_location",

            "what's the weather": "announce_weather",

            "repeat last": "repeat_last",

            "start navigation": "start_navigation", 

            "stop navigation": "stop_navigation",   

            "stop speaking": "stop_speaking",       

            "send status update": "send_status_update_to_caretaker", # NEW VOICE COMMAND

            # Add more commands and synonyms here

        }



        if HAS_SPEECH_RECOGNITION:

            try:

                self.recognizer = sr.Recognizer()

                self.microphone = sr.Microphone()

                logger.info("VoiceInputSystem: Speech recognition initialized.")

                # Initialize Vosk for offline recognition if available

                if HAS_VOSK:

                    # Note: You must download a Vosk model and place it in a 'model' directory.

                    # e.g., https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip

                    if os.path.exists("model"):

                        self.vosk_model = vosk.Model("model")

                        logger.info("VoiceInputSystem: Offline Vosk model loaded successfully.")

            except Exception as e:

                logger.error(f"VoiceInputSystem: Error initializing microphone: {e}. Voice input disabled.") 

                HAS_SPEECH_RECOGNITION = False

        else:

            logger.warning("VoiceInputSystem: Speech recognition library not available.")



    def start_listening(self):

        if not HAS_SPEECH_RECOGNITION:

            system_instance.audio_system.speak("Voice input is not available.")

            return



        if self.is_listening:

            logger.info("VoiceInputSystem: Already listening.")

            return



        self.is_listening = True

        system_instance.audio_system.speak("Listening for command...")

        logger.info("VoiceInputSystem: Starting listening thread.")

        threading.Thread(target=self._listen_loop, daemon=True).start()



    def stop_listening(self):

        if self.is_listening:

            self.is_listening = False

            logger.info("VoiceInputSystem: Stopped listening.")

            system_instance.audio_system.speak("Stopped listening.")



    def _listen_loop(self):

        with self.microphone as source:

            self.recognizer.adjust_for_ambient_noise(source) # Adjust for ambient noise once

            while self.is_listening:

                try:

                    audio = self.recognizer.listen(source, timeout=5, phrase_time_limit=5) # Listen for up to 5 seconds

                    text = self._process_audio(audio)

                    if text:

                        system_instance.audio_system.speak(f"Heard: {text}")

                        self._process_command(text)

                    else:

                        system_instance.audio_system.speak("Did not hear a clear command.")

                except sr.WaitTimeoutError:

                    logger.debug("VoiceInputSystem: No speech detected within timeout.")

                    system_instance.audio_system.speak("No command heard. Listening again...")

                except sr.UnknownValueError:

                    logger.warning("VoiceInputSystem: Speech Recognition could not understand audio.")

                    system_instance.audio_system.speak("Sorry, I didn't understand that. Please try again.")

                except sr.RequestError as e:

                    logger.error(f"VoiceInputSystem: Could not request results from speech recognition service; {e}")

                    system_instance.audio_system.speak("Speech service error. Please check internet connection.")

                except Exception as e:

                    logger.error(f"VoiceInputSystem: An unexpected error occurred during listening: {e}")

                    system_instance.audio_system.speak("An error occurred with voice input.")

                finally:

                    if not self.is_listening:

                        break

                    time.sleep(0.1) # Small delay to prevent busy-waiting



    def _process_audio(self, audio) -> Optional[str]:

        """Converts audio data to text using online or offline STT."""

        text = None

        # --- Online STT (Google Web Speech API) ---

        if is_online():

            logger.info("VoiceInputSystem: Attempting online speech recognition (Google).")

            try:

                text = self.recognizer.recognize_google(audio)

                logger.info(f"VoiceInputSystem: Online STT result: '{text}'")

                return text.lower()

            except sr.UnknownValueError:

                logger.warning("VoiceInputSystem: Google Speech Recognition could not understand audio.")

            except sr.RequestError as e:

                logger.error(f"VoiceInputSystem: Could not request results from Google; {e}. Falling back to offline.")



        # --- Offline STT (Vosk) ---

        if self.vosk_model:

            logger.info("VoiceInputSystem: Attempting offline speech recognition (Vosk).")

            try:

                rec = vosk.KaldiRecognizer(self.vosk_model, self.microphone.SAMPLE_RATE)

                rec.AcceptWaveform(audio.get_raw_data(convert_rate=self.microphone.SAMPLE_RATE, convert_width=self.microphone.SAMPLE_WIDTH))

                result = json.loads(rec.FinalResult())

                text = result.get('text', '')

                if text:

                    logger.info(f"VoiceInputSystem: Offline STT result: '{text}'")

                    return text.lower()

            except Exception as e:

                logger.error(f"VoiceInputSystem: Error during offline Vosk recognition: {e}")

        else:

            logger.warning("VoiceInputSystem: Vosk model not loaded, cannot perform offline STT.")



        return None # Return None if all methods fail



    def _process_command(self, text: str):

        """Processes the recognized text to find and execute a command."""

        command_to_execute = None

        

        # --- Online NLU (Gemini) ---

        if is_online() and self.ai_vision.gemini_api_key:

            logger.info("VoiceInputSystem: Using online AI for intent recognition.")

            try:

                # Create a precise prompt for Gemini

                command_list_str = ", ".join(self.command_map.values())

                prompt = (f"The user of an assistive device for the visually impaired said: '{text}'. "

                          f"Which of the following system commands is the best match? "

                          f"System commands: [{command_list_str}]. "

                          f"Respond with ONLY the single best-matching command name from the list, or 'unknown' if there is no good match.")

                

                gemini_response = self.ai_vision._call_llm_text(prompt).strip().lower().replace("`", "")

                

                if gemini_response in self.command_map.values():

                    command_to_execute = gemini_response

                    logger.info(f"VoiceInputSystem: Online NLU matched '{text}' to command '{command_to_execute}'.")

            except Exception as e:

                logger.error(f"VoiceInputSystem: Error with online NLU, falling back to offline: {e}")



        # --- Offline NLU (Keyword Matching) ---

        if not command_to_execute:

            logger.info("VoiceInputSystem: Using offline keyword matching for intent recognition.")

            for phrase, command in self.command_map.items():

                if phrase in text:

                    command_to_execute = command

                    logger.info(f"VoiceInputSystem: Offline NLU matched '{text}' to command '{command_to_execute}'.")

                    break



        if command_to_execute:

            self.socketio.emit('command', {'command': command_to_execute})

        else:

            logger.warning(f"VoiceInputSystem: Could not map '{text}' to any known command.")

            system_instance.audio_system.speak("Sorry, I couldn't understand that command.")



# --- Enhanced Assistive Lens System (Orchestrator) ---

class EnhancedAssistiveLensSystem:

    """Main system orchestrator for assistive lens features."""

    def __init__(self, socketio_instance, enable_camera: bool = True,

                 enable_location: bool = True, enable_distance_sensor: bool = True,

                 enable_buttons: bool = True, enable_keyboard: bool = True):

        

        self.socketio = socketio_instance

        self.hardware = HardwareSystem(enable_distance_sensor=enable_distance_sensor)

        self.ai_vision = AIVisionSystem(socketio_instance, enable_camera=enable_camera)

        # Initialize AudioSystem FIRST as other components will use it for speaking

        self.audio_system = AudioSystem(socketio_instance)

        # Pass the ai_vision instance to LocationSystem for AI-powered descriptions

        self.voice_input = VoiceInputSystem(socketio_instance, self.ai_vision) 

        self.location_system = LocationSystem(socketio_instance, self.ai_vision, enable_location=enable_location)

        

        self.enable_buttons = enable_buttons

        self.enable_keyboard = enable_keyboard



        self.last_spoken_response: str = "" # Store last spoken response for 'repeat' command

        self.is_navigation_active: bool = False

        self.navigation_target: Optional[str] = None # Stores a simple string description of destination

        self.navigation_interval_thread: Optional[threading.Thread] = None



        # Button Gesture Mapping - This defines what each button does for each gesture

        self.gesture_commands = {

            'BUTTON_1': {

                'single_press': self.describe_scene,

                'double_tap': self.read_text,

                'long_press': self.detect_objects

            },

            'BUTTON_2': {

                'single_press': self.announce_location,

                'double_tap': self.announce_weather,

                'long_press': self.toggle_navigation 

            },

            'BUTTON_3': {

                'single_press': self.check_and_announce_distance,

                'double_tap': self.trigger_alert_buzzer,

                'long_press': self.emergency_alert

            },

            'BUTTON_4': {

                'single_press': self.toggle_voice_input,

                'double_tap': self.repeat_last,

                'long_press': self.stop_speaking 

            }

        }

        

        self.keyboard_listener = None

        self.is_running = True



        # Buttons are now setup within HardwareSystem's __init__

        self._start_distance_monitoring()



    def handle_button_gesture(self, button_name: str, gesture_type: str):

        """Handles a detected button gesture and maps it to a system command."""

        logger.info(f"System received gesture: {button_name} - {gesture_type}")

        

        command_func = self.gesture_commands.get(button_name, {}).get(gesture_type)

        if command_func:

            # Execute the command in a separate thread to prevent blocking

            threading.Thread(target=command_func).start()

        else:

            self.audio_system.speak(f"No action defined for {button_name} {gesture_type}.")

            logger.warning(f"No action defined for button '{button_name}' with gesture '{gesture_type}'.")



    def _start_distance_monitoring(self):

        """Starts a background thread to continuously monitor distance."""

        if self.hardware.enable_distance_sensor:

            logger.info("Starting distance monitoring thread.")

            self.distance_thread = threading.Thread(target=self._monitor_distance_loop, daemon=True)

            self.distance_thread.start()

        else:

            logger.info("Distance monitoring disabled by configuration.")



    def _monitor_distance_loop(self):

        """Loop for continuous distance monitoring."""

        while self.is_running and self.hardware.enable_distance_sensor:

            distance = self.hardware.get_distance()

            if distance != -1.0:

                # Emit distance for potential client display

                self.socketio.emit('status_update', {

                    'type': 'distance_reading',

                    'data': {'distance': distance, 'timestamp': datetime.now().isoformat()}

                })



                # Proactive obstacle alert

                if distance < 100.0: # Threshold for close obstacle (e.g., 100 cm = 1 meter)

                    if distance < 30.0: # Very close, stronger buzz

                        self.hardware.trigger_buzzer(duration=0.1) # Short buzz

                        alert_level = "critical"

                        message = f"Immediate obstacle detected at {distance} cm! Clear your path."

                    else: # Less critical, softer buzz/alert

                        self.hardware.trigger_buzzer(duration=0.05)

                        alert_level = "warning"

                        message = f"Obstacle detected at {distance} cm. Be cautious."



                    self.socketio.emit('status_update', {

                        'type': 'obstacle_alert',

                        'data': {'message': message, 'distance': distance, 'level': alert_level}

                    })

                    logger.info(f"Obstacle alert ({alert_level}): {distance} cm")

            time.sleep(0.5) # Check every 0.5 seconds



    # --- Core Features (exposed as SocketIO commands and button gestures) ---

    def describe_scene(self, prompt_suffix: str = ""):

        """Triggers scene description via AI vision."""

        logger.info(f"Command: describe_scene received. Suffix: {prompt_suffix}")

        self.audio_system.speak("Analyzing the scene...") 

        response = self.ai_vision.describe_scene(prompt_suffix=prompt_suffix) 

        self.socketio.emit('status_update', {'type': 'system_status', 'data': {'message': response}})



    def read_text(self):

        """Triggers OCR to read text from image."""

        logger.info("Command: read_text received.")

        self.audio_system.speak("Reading text...")

        response = self.ai_vision.read_text_from_image()

        self.socketio.emit('status_update', {'type': 'system_status', 'data': {'message': response}})



    def detect_objects(self, prompt_suffix: str = ""):

        """Triggers object detection via AI vision."""

        logger.info(f"Command: detect_objects received. Suffix: {prompt_suffix}")

        self.audio_system.speak("Detecting objects...")

        response = self.ai_vision.detect_objects(prompt_suffix=prompt_suffix)

        self.socketio.emit('status_update', {'type': 'system_status', 'data': {'message': response}})



    def recognize_face(self):

        """Triggers face recognition via AI vision."""

        logger.info("Command: recognize_face received.")

        self.audio_system.speak("Looking for faces...")

        response = self.ai_vision.recognize_face()

        self.socketio.emit('status_update', {'type': 'system_status', 'data': {'message': response}})



    def check_and_announce_distance(self):

        """Gets and announces the current distance from ultrasonic sensor."""

        logger.info("Command: check_obstacle received.")

        self.audio_system.speak("Checking for obstacles...")

        distance = self.hardware.get_distance()

        if distance != -1.0:

            message = f"Obstacle is at {distance} centimeters."

            self.audio_system.speak(message) 

            self.socketio.emit('status_update', {'type': 'system_status', 'data': {'message': message}})

        else:

            message = "Could not get a clear distance reading."

            self.audio_system.speak(message) 

            self.socketio.emit('status_update', {'type': 'system_status', 'data': {'message': message}})



    def toggle_light(self):

        """Toggles the status LED on/off."""

        logger.info("Command: toggle_led received.")

        self.hardware.toggle_status_led()

        status_msg = "LED is now " + ("ON" if self.hardware.status_led_on else "OFF")

        self.audio_system.speak(status_msg) 

        self.socketio.emit('status_update', {'type': 'system_status', 'data': {'message': status_msg}})



    def trigger_alert_buzzer(self):

        """Triggers the buzzer for a short alert."""

        logger.info("Command: trigger_buzzer received.")

        self.hardware.trigger_buzzer(duration=0.5)

        alert_msg = "Buzzer alert activated."

        self.audio_system.speak(alert_msg) 

        self.socketio.emit('status_update', {'type': 'system_status', 'data': {'message': alert_msg}})



    def emergency_alert(self):

        """Triggers an emergency alert."""

        logger.warning("EMERGENCY ALERT ACTIVATED!")

        

        location_info = self.location_system.get_current_location()

        location_str = ""

        if location_info and location_info.get('lat') is not None and location_info.get('lon') is not None:

            if self.location_system.client_latitude is not None:

                 location_str = f" Current approximate location: Latitude {location_info['lat']:.4f}, Longitude {location_info['lon']:.4f}."

            else:

                location_str = f" Current location: {location_info['city']}, {location_info['country']} (Lat: {location_info['lat']:.4f}, Lon: {location_info['lon']:.4f})."

        elif location_info: # If city/country not available but lat/lon are

            location_str = f" Current approximate location: Lat: {location_info['lat']:.4f}, Lon: {location_info['lon']:.4f}."



        self.hardware.trigger_buzzer(duration=1.0) # Longer buzz

        message = f"Emergency alert activated. Seeking help.{location_str}"

        self.audio_system.speak(message) 

        self.socketio.emit('emergency_alert', {'message': message})

        self.socketio.emit('status_update', {'type': 'emergency_alert', 'data': {'message': message}})



    def announce_location(self):

        """Announces the current location."""

        logger.info("Command: announce_location received.")

        self.audio_system.speak("Getting your location...")

        self.location_system.announce_location() 



    def announce_weather(self):

        """Announces the current weather with AI description."""

        logger.info("Command: announce_weather received.")

        self.audio_system.speak("Getting the weather forecast...")

        self.location_system.announce_weather() 

        

    def toggle_voice_input(self):

        """Toggles voice command listening on/off."""

        if self.voice_input.is_listening:

            self.voice_input.stop_listening()

        else:

            self.voice_input.start_listening()



    def repeat_last(self):

        """Repeats the last spoken response."""

        logger.info("Command: repeat_last received.")

        if self.last_spoken_response:

            self.audio_system.speak(f"Repeating: {self.last_spoken_response}") 

        else:

            no_repeat_msg = "No previous response to repeat."

            self.audio_system.speak(no_repeat_msg) 



    def stop_speaking(self):

        """Stops any ongoing speech synthesis on the client side and Pi side."""

        logger.info("Command: stop_speaking received.")

        self.audio_system.stop_speaking()

        stop_speech_msg = "Speech stopped."

        # Do NOT update last_spoken_response with "Speech stopped" to avoid repeating it next time.

        self.socketio.emit('status_update', {'type': 'system_status', 'data': {'message': stop_speech_msg}})



    def process_caretaker_message(self, message: str):

        """Receives a message from the caretaker (web) and speaks it on the Pi."""

        logger.info(f"Caretaker message received: {message}")

        self.audio_system.speak(f"Message from caretaker: {message}")

        self.socketio.emit('system_status', {'message': f"Caretaker message received: {message}"})



    def send_status_update_to_caretaker(self):

        """Composes and sends a status update message from the user to the caretaker."""

        logger.info("Sending status update to caretaker.")

        location_info = self.location_system.get_current_location()

        location_str = "unknown location"

        if location_info:

            if self.location_system.client_latitude is not None:

                location_str = f"Latitude {location_info['lat']:.4f}, Longitude {location_info['lon']:.4f}"

            else:

                location_str = f"{location_info['city']}, {location_info['country']}"



        status_message = f"User is currently at {location_str} and is okay. If more help is needed, I will alert."

        self.audio_system.speak("Sending status update to caretaker.") # Acknowledge on Pi

        self.socketio.emit('user_message', {'message': status_message}) # Send to web

        self.socketio.emit('system_status', {'message': "Status update sent to caretaker."})

        logger.info(f"Status update sent: {status_message}")





    def toggle_navigation(self):

        """Toggles the navigation mode (starts if off, stops if on)."""

        if self.is_navigation_active:

            self.stop_navigation()

        else:

            self.start_navigation(destination="unknown") # Use a default/placeholder destination for toggling



    def start_navigation(self, destination: str = "unknown"):

        """Starts the navigation mode."""

        if self.is_navigation_active:

            self.audio_system.speak("Navigation is already active.")

            return



        self.is_navigation_active = True

        self.navigation_target = destination

        message = f"Starting navigation to {self.navigation_target}. I will guide you."

        self.audio_system.speak(message)

        self.socketio.emit('navigation_status', {'status': 'started', 'destination': self.navigation_target, 'message': message})

        logger.info(message)



        # Start a periodic navigation guidance thread

        self.navigation_interval_thread = threading.Thread(target=self._navigation_guidance_loop, daemon=True)

        self.navigation_interval_thread.start()



    def stop_navigation(self):

        """Stops the navigation mode."""

        if not self.is_navigation_active:

            self.audio_system.speak("Navigation is not currently active.")

            return



        self.is_navigation_active = False

        self.navigation_target = None

        message = "Stopping navigation. You are now free to roam."

        self.audio_system.speak(message)

        self.socketio.emit('navigation_status', {'status': 'stopped', 'message': message})

        logger.info(message)



    def _navigation_guidance_loop(self):

        """Provides periodic navigation guidance while navigation is active."""

        mock_instructions = [

            "Continue straight for fifty meters.",

            "You are approaching an intersection. Be cautious.",

            "After the intersection, turn left.",

            "Walk along the sidewalk for another hundred meters.",

            "You have arrived at your approximate destination."

        ]

        instruction_index = 0

        

        while self.is_navigation_active:

            # Check for immediate obstacles

            distance = self.hardware.get_distance()

            if 2 <= distance < 100.0: # Obstacle within 1 meter

                self.socketio.emit('navigation_instruction', {

                    'instruction': f"Obstacle detected ahead at {distance} centimeters. Be careful!",

                    'type': 'alert'

                })

                self.hardware.trigger_buzzer(duration=0.15) # Stronger buzz for navigation obstacles

                logger.info(f"Navigation obstacle alert: {distance} cm")

            

            # Provide general guidance based on current "progress"

            current_location_info = self.location_system.get_current_location()

            if current_location_info and instruction_index < len(mock_instructions):

                instruction = mock_instructions[instruction_index]

                self.audio_system.speak(instruction)

                self.socketio.emit('navigation_instruction', {

                    'instruction': instruction,

                    'type': 'guidance'

                })

                logger.info(f"Navigation instruction: {instruction}")

                instruction_index += 1

                if instruction_index == len(mock_instructions):

                    # End navigation after last instruction

                    time.sleep(5) # Give user time to hear "arrived"

                    self.stop_navigation()

                    break # Exit loop

            else:

                if self.is_navigation_active: # Ensure still active before saying

                    self.audio_system.speak("Continuing on current path. No specific instruction at this moment.")

                    self.socketio.emit('navigation_instruction', {

                        'instruction': "Continuing on current path.",

                        'type': 'status'

                    })

            

            # Periodically describe the scene with navigation context

            self.describe_scene(prompt_suffix="Focus on path conditions, potential hazards like curbs or stairs, and upcoming turns.")

            

            time.sleep(10) # Provide guidance every 10 seconds



    # --- System Lifecycle Management ---

    def start_system(self):

        """Starts all background system components."""

        logger.info("Starting all assistive lens system components.")

        if self.enable_keyboard and HAS_PYNPUT:

            self.keyboard_listener = keyboard.Listener(on_press=self._on_key_press)

            self.keyboard_listener.start()

            logger.info("Keyboard listener started.")

        self.is_running = True

        logger.info("Assistive Lens System is running.")

        

    def stop_system(self):

        """Stops all background system components and cleans up."""

        logger.info("Stopping all assistive lens system components.")

        self.is_running = False

        if self.keyboard_listener:

            self.keyboard_listener.stop()

        if self.navigation_interval_thread and self.navigation_interval_thread.is_alive():

            self.navigation_interval_thread.join(timeout=1) # Give it a moment to finish

        self.hardware.cleanup()

        self.ai_vision.cleanup()

        # Clean up pyttsx3 engine

        self.audio_system.cleanup() # Call the new cleanup method for AudioSystem

        logger.info("Assistive Lens System gracefully shut down.")

        os._exit(0) # Force exit to ensure all threads terminate





    def _on_key_press(self, key):

        """Handles keyboard key presses for desktop control."""

        try:

            # Re-map keyboard shortcuts to directly call system functions, not button names

            # This is simpler now that button gestures are handled internally.

            if key == keyboard.Key.space:

                logger.info("Keyboard: Spacebar pressed (Toggle Voice Input).")

                threading.Thread(target=self.toggle_voice_input).start()

            elif key == keyboard.Key.enter:

                logger.info("Keyboard: Enter pressed (Emergency Alert).")

                threading.Thread(target=self.emergency_alert).start()

            elif key == keyboard.Key.backspace:

                logger.info("Keyboard: Backspace pressed (Repeat Last).")

                threading.Thread(target=self.repeat_last).start()

            elif hasattr(key, 'char'): # Check if it's a character key

                if key.char == 'd':

                    logger.info("Keyboard: 'd' pressed (Describe Scene).")

                    threading.Thread(target=self.describe_scene).start()

                elif key.char == 'r':

                    logger.info("Keyboard: 'r' pressed (Read Text).")

                    threading.Thread(target=self.read_text).start()

                elif key.char == 'o':

                    logger.info("Keyboard: 'o' pressed (Detect Objects).")

                    threading.Thread(target=self.detect_objects).start()

                elif key.char == 'l':

                    logger.info("Keyboard: 'l' pressed (Announce Location).")

                    threading.Thread(target=self.announce_location).start()

                elif key.char == 'w':

                    logger.info("Keyboard: 'w' pressed (Announce Weather).")

                    threading.Thread(target=self.announce_weather).start()

                elif key.char == 'n':

                    logger.info("Keyboard: 'n' pressed (Toggle Navigation).")

                    threading.Thread(target=self.toggle_navigation).start() # Toggle navigation

                elif key.char == 's':

                    logger.info("Keyboard: 's' pressed (Stop Speaking).")

                    threading.Thread(target=self.stop_speaking).start()

                elif key.char == 'u': # New keyboard shortcut for sending status update

                    logger.info("Keyboard: 'u' pressed (Send Status Update to Caretaker).")

                    threading.Thread(target=self.send_status_update_to_caretaker).start()

                elif key.char == 'q':

                    logger.info("Keyboard: 'q' pressed. Shutting down system.")

                    self.stop_system()

        except AttributeError:

            pass # Ignore non-character keys (e.g., modifier keys)



# --- Flask Web Interface ---

if HAS_FLASK_SOCKETIO:

    @app.route('/')

    def index():

        return render_template('index.html')



    @app.route('/video_feed')

    def video_feed():

        return Response(gen_frames(system_instance.ai_vision), mimetype='multipart/x-mixed-replace; boundary=frame')



    def gen_frames(ai_vision_system):

        """Generates JPEG frames for video streaming."""

        while True:

            frame_b64 = ai_vision_system._get_image_data()

            

            # This is the crucial check for valid base64 image data

            if frame_b64 and frame_b64.startswith("data:image/jpeg;base64,"):

                # Remove the data URL prefix for direct byte conversion

                try:

                    frame_bytes = base64.b64decode(frame_b64.split(',')[1])

                    yield (b'--frame\r\n'

                           b'Content-Type: image/jpeg\r\n\r\n' + frame_bytes + b'\r\n')

                except Exception as e:

                    logger.warning(f"gen_frames: Error decoding base64 image data: {e}. Skipping frame.")

                    time.sleep(0.1)

            else:

                # If no valid image data, send a placeholder or just wait

                # For video feed, it's better to keep sending something if possible,

                # but if the camera is off, just wait briefly.

                if not ai_vision_system.enable_camera:

                    logger.debug("gen_frames: Camera disabled, no frames to send.")

                else:

                    logger.warning("gen_frames: Invalid image data or camera error. Skipping frame.")

                time.sleep(0.5) # Wait briefly to avoid busy-waiting if camera is problematic



    @socketio.on('connect')

    def handle_connect():

        logger.info('Client connected to SocketIO.')

        emit('system_status', {'message': 'Raspberry Pi system connected.'})



    @socketio.on('disconnect')

    def handle_disconnect():

        logger.info('Client disconnected from SocketIO.')



    @socketio.on('command')

    def handle_command(data):

        command = data.get('command')

        logger.info(f"Remote command received: {command}")

        

        # Define a map of commands to system methods

        command_map = {

            'describe_scene': system_instance.describe_scene,

            'read_text': system_instance.read_text,

            'detect_objects': system_instance.detect_objects,

            'recognize_face': system_instance.recognize_face,

            'check_obstacle': system_instance.check_and_announce_distance,

            'toggle_led': system_instance.toggle_light,

            'trigger_buzzer': system_instance.trigger_alert_buzzer,

            'emergency_alert': system_instance.emergency_alert,

            'announce_location': system_instance.announce_location,

            'announce_weather': system_instance.announce_weather,

            'toggle_voice_input': system_instance.toggle_voice_input, 

            'repeat_last': system_instance.repeat_last,

            'start_navigation': system_instance.start_navigation, 

            'stop_navigation': system_instance.stop_navigation, 

            'stop_speaking': system_instance.stop_speaking,

            'caretaker_message': system_instance.process_caretaker_message # NEW: Caretaker message to Pi

        }



        action = command_map.get(command)

        if action:

            try:

                # Handle commands that need arguments differently

                if command in ['start_navigation']:

                    destination = data.get('destination', 'unknown place')

                    threading.Thread(target=action, args=(destination,)).start()

                elif command in ['describe_scene', 'detect_objects']: # For AI vision with custom prompts

                    prompt_suffix = data.get('prompt_suffix', '')

                    threading.Thread(target=action, args=(prompt_suffix,)).start()

                elif command == 'caretaker_message': # Handle caretaker message with its content

                    message_content = data.get('message', '')

                    if message_content:

                        threading.Thread(target=action, args=(message_content,)).start()

                    else:

                        logger.warning("Caretaker message command received without message content.")

                        emit('command_response', {'command': command, 'status': 'failed', 'error': 'No message content provided.'})

                        system_instance.audio_system.speak("Error: No message content received.")

                else:

                    # Execute the action in a separate thread to prevent blocking SocketIO

                    # and allow immediate response to the client.

                    threading.Thread(target=action).start()

                emit('command_response', {'command': command, 'status': 'processing'})

            except Exception as e:

                logger.error(f"Error executing command '{command}': {e}")

                emit('command_response', {'command': command, 'status': 'failed', 'error': str(e)})

                # Still speak the error on the Pi

                system_instance.audio_system.speak(f"Error processing {command}.")

        else:

            logger.warning(f"Unknown command received: {command}")

            emit('command_response', {'command': command, 'status': 'unknown'})

            # Still speak the unknown command on the Pi

            system_instance.audio_system.speak(f"Unknown command: {command}.")



    @socketio.on('location_update')

    def handle_location_update(data):

        """Receives location updates from the client."""

        lat = data.get('latitude')

        lon = data.get('longitude')

        if lat is not None and lon is not None:

            system_instance.location_system.update_client_location(lat, lon)

        else:

            logger.warning("Received invalid location_update data: %s", data)



    @socketio.on('user_message') # NEW: Listener for messages from the user (Pi) to caretaker (web)

    def handle_user_message(data):

        message = data.get('message')

        if message:

            logger.info(f"User message received for caretaker: {message}")

            emit('user_message', {'message': message}, broadcast=True) # Send to all connected web clients

        else:

            logger.warning("Received empty user_message.")





# --- HTML Template Creation (for simple web interface) ---

def create_html_template():

    """Creates a simple HTML template for the web interface if it doesn't exist."""

    template_dir = os.path.join(os.path.dirname(__file__), 'templates')

    os.makedirs(template_dir, exist_ok=True)

    index_html_path = os.path.join(template_dir, 'index.html')



    if not os.path.exists(index_html_path):

        html_content = """

        <!DOCTYPE html>

        <html>

        <head>

            <title>Assistive Lens Control</title>

            <meta name="viewport" content="width=device-width, initial-scale=1.0">

            <style>

                body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f0f0f0; color: #333; }

                #container { max-width: 800px; margin: 0 auto; background-color: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }

                h1 { text-align: center; color: #333; }

                #video-feed { width: 100%; max-width: 640px; border: 1px solid #ccc; display: block; margin: 20px auto; }

                #controls { text-align: center; margin-top: 20px; }

                .command-button {

                    padding: 10px 20px;

                    margin: 5px;

                    font-size: 16px;

                    cursor: pointer;

                    background-color: #007bff;

                    color: white;

                    border: none;

                    border-radius: 5px;

                    transition: background-color 0.3s ease;

                }

                .command-button:hover { background-color: #0056b3; }

                .command-button.danger { background-color: #dc3545; }

                .command-button.danger:hover { background-color: #bd2130; }

                #status-log { margin-top: 20px; border: 1px solid #eee; padding: 10px; height: 200px; overflow-y: scroll; background-color: #f9f9f9; border-radius: 5px; }

                .log-entry { margin-bottom: 5px; font-size: 14px; }

                .log-error { color: #dc3545; font-weight: bold; }

                .log-warning { color: #ffc107; }

                .status-display { text-align: center; font-size: 1.2em; margin-top: 10px; color: #007bff; font-weight: bold; }

            </style>

            <script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.0.0/socket.io.js"></script>

        </head>

        <body>

            <div id="container">

                <h1>Assistive Lens Control (Web)</h1>

                <div class="status-display" id="connection-status">Connecting...</div>

                <div class="status-display" id="system-status">System Idle</div>

                <img id="video-feed" src="/video_feed" alt="Live Camera Feed" />

                <div id="controls">

                    <button class="command-button" onclick="sendCommand('describe_scene')">Describe Scene</button>

                    <button class="command-button" onclick="sendCommand('read_text')">Read Text</button>

                    <button class="command-button" onclick="sendCommand('detect_objects')">Detect Objects</button>

                    <button class="command-button" onclick="sendCommand('recognize_face')">Recognize Face</button>

                    <button class="command-button" onclick="sendCommand('check_obstacle')">Check Obstacle</button>

                    <button class="command-button" onclick="sendCommand('toggle_led')">Toggle LED</button>

                    <button class="command-button" onclick="sendCommand('trigger_buzzer')">Trigger Buzzer</button>

                    <button class="command-button" onclick="sendCommand('toggle_voice_input')">Voice Command</button>

                    <button class="command-button" onclick="sendCommand('announce_location')">Announce Location</button>

                    <button class="command-button" onclick="sendCommand('announce_weather')">Announce Weather</button>

                    <button class="command-button" onclick="sendCommand('repeat_last')">Repeat Last</button>

                    <button class="command-button" onclick="sendCommand('stop_speaking')">Stop Speaking</button> 

                    <button class="command-button danger" onclick="sendCommand('emergency_alert')">Emergency Alert</button>

                </div>



                <!-- NEW: Caretaker to User Communication Section -->

                <div style="margin-top: 20px; padding: 15px; border: 1px solid #ddd; border-radius: 8px; background-color: #f8f8f8;">

                    <h2>ðŸ’¬ Message to User (Spoken on Glasses)</h2>

                    <input type="text" id="caretaker-message-input" placeholder="Type message for user..." 

                           style="width: calc(100% - 80px); padding: 8px; margin-right: 10px; border: 1px solid #ccc; border-radius: 4px;">

                    <button class="command-button" onclick="sendCaretakerMessage()" style="width: 70px;">Send</button>

                </div>



                <!-- NEW: User to Caretaker Messages Section -->

                <div style="margin-top: 20px; padding: 15px; border: 1px solid #ddd; border-radius: 8px; background-color: #f8f8f8;">

                    <h2>ðŸ“¥ Messages from User</h2>

                    <div id="user-messages-log" style="height: 150px; overflow-y: auto; border: 1px solid #eee; padding: 10px; background-color: #fff; border-radius: 5px;">

                        <p style="font-style: italic; color: #7f8c8d;">No messages yet.</p>

                    </div>

                </div>



                <div id="status-log"></div>

            </div>



            <audio id="speech-audio"></audio>

            <script>

                var socket = io();

                var statusLog = document.getElementById('status-log');

                var connectionStatus = document.getElementById('connection-status');

                var systemStatus = document.getElementById('system-status');

                var speechAudio = document.getElementById('speech-audio');

                var caretakerMessageInput = document.getElementById('caretaker-message-input'); // NEW

                var userMessagesLog = document.getElementById('user-messages-log'); // NEW



                socket.on('connect', function() {

                    console.log('Connected to server');

                    connectionStatus.textContent = 'Connected to Glasses';

                });



                socket.on('disconnect', function() {

                    console.log('Disconnected from server');

                    connectionStatus.textContent = 'Disconnected';

                });



                socket.on('system_status', function(data) {

                    console.log('System Status:', data.message);

                    addLog('System Status: ' + data.message);

                    systemStatus.textContent = 'Status: ' + data.message;

                });



                socket.on('speech_output', function(data) {

                    console.log('Speech Output:', data.message);

                    addLog('Speech: ' + data.message);

                    // Pi handles speech, this is just for web log/display

                });



                socket.on('stop_speech', function() { 

                    addLog('Speech stop signal received (Pi handled).', 'log-info');

                });



                socket.on('obstacle_alert', function(data) {

                    addLog('OBSTACLE ALERT: ' + data.message, 'log-error');

                    // Play a distinct sound or vibration in a real web app

                });



                socket.on('emergency_alert', function(data) {

                    addLog('EMERGENCY: ' + data.message, 'log-error');

                    // Play a loud, distinct sound

                    speechAudio.src = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBIAAAABAAEAQB8AAEAfAAABAAgAAABDSUNDZXQAAAAAAAAAAGRhdGEAAAAcAAAACgEBAgMBBgAHBggKCwwNDg8QDw8PDw8'; // Short beep

                    speechAudio.play();

                });



                socket.on('command_response', function(data) {

                    addLog('Command Response for ' + data.command + ': ' + data.status);

                    systemStatus.textContent = 'Status: ' + data.command + ' ' + data.status;

                });



                // NEW: Listener for messages coming from the user (Pi)

                socket.on('user_message', function(data) {

                    console.log('Message from User:', data.message);

                    addLog('User -> Caretaker: ' + data.message, 'log-success');

                    

                    // Remove "No messages yet." placeholder if it exists

                    const placeholder = userMessagesLog.querySelector('p[style*="italic"]');

                    if (placeholder) {

                        userMessagesLog.removeChild(placeholder);

                    }



                    var p = document.createElement('p');

                    p.textContent = new Date().toLocaleTimeString() + ': ' + data.message;

                    userMessagesLog.prepend(p); // Add to top

                });



                function sendCommand(cmd) {

                    console.log('Sending command:', cmd);

                    socket.emit('command', { command: cmd });

                    addLog('Sent command: ' + cmd);

                }



                // NEW: Function to send message from caretaker to user (Pi)

                function sendCaretakerMessage() {

                    const message = caretakerMessageInput.value.trim();

                    if (message) {

                        console.log('Sending caretaker message:', message);

                        socket.emit('command', { command: 'caretaker_message', message: message });

                        addLog('Caretaker -> User: ' + message);

                        caretakerMessageInput.value = ''; // Clear input

                    } else {

                        addLog('Cannot send empty message.', 'log-warning');

                    }

                }



                function addLog(message, className = '') {

                    var div = document.createElement('div');

                    div.className = 'log-entry ' + className;

                    div.textContent = new Date().toLocaleTimeString() + ': ' + message;

                    statusLog.prepend(div); 

                    if (statusLog.children.length > 50) {

                        statusLog.removeChild(statusLog.lastChild);

                    }

                }

            </script>

        </body>

        </html>

        """

        with open(index_html_path, 'w') as f:

            f.write(html_content)

        logger.info(f"Created HTML template at {index_html_path}")



# --- Main Execution Block ---

if __name__ == '__main__':

    parser = argparse.ArgumentParser(description="Enhanced Assistive Lens System for Raspberry Pi.")

    parser.add_argument('--web-port', type=int, default=5000, help='Port for the web interface')

    parser.add_argument('--no-camera', action='store_true', help='Disable camera services')

    parser.add_argument('--no-location', action='store_true', help='Disable location services')

    parser.add_argument('--no-distance', action='store_true', help='Disable distance sensor')

    parser.add_argument('--no-buttons', action='store_true', help='Disable hardware buttons')

    parser.add_argument('--no-keyboard', action='store_true', help='Disable keyboard monitoring')

    parser.add_argument('--web-only', action='store_true', help='Run web interface only')

    parser.add_argument('--no-voice-input', action='store_true', help='Disable voice command input.') # Add this back if removed



    args = parser.parse_args()



    # Create HTML template (only if Flask/SocketIO is available)

    if HAS_FLASK_SOCKETIO:

        create_html_template()



    # Initialize system

    # IMPORTANT: Initialize AudioSystem first as other components will use it for speaking.

    system_instance = EnhancedAssistiveLensSystem(

        socketio_instance=socketio,

        enable_camera=not args.no_camera,

        enable_location=not args.no_location,

        enable_distance_sensor=not args.no_distance,

        enable_buttons=not args.no_buttons,

        enable_keyboard=not args.no_keyboard

    )

    

    if not args.web_only:

        # Start system components

        system_instance.start_system()



    try:

        if HAS_FLASK_SOCKETIO:

            logger.info(f"Starting web interface on port {args.web_port}...")

            socketio.run(app, host='0.0.0.0', port=args.web_port, allow_unsafe_werkzeug=True)

        else:

            logger.error("Flask/SocketIO not available. Web interface cannot be started.")

            if not args.web_only:

                logger.info("Running system components without web interface. Press Ctrl+C to exit.")

                while system_instance.is_running:

                    time.sleep(1) # Keep main thread alive

            else:

                logger.info("Web interface requested but Flask/SocketIO not found. Exiting.")

    except KeyboardInterrupt:

        logger.info("System shutdown initiated by user.")

    except Exception as e:

        logger.critical(f"Unhandled exception in main execution: {e}")

    finally:

        system_instance.stop_system()

        logger.info("Assistive Lens System gracefully shut down.")



