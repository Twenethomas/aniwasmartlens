# Add rules to this file for your application.
#
# To learn more about ProGuard rules, please see:
#   https://developer.android.com/studio/build/shrink-code#custom-rules
#
# For details about the Flutter build process, see:
#   https://docs.flutter.dev/deployment/android#reviewing-the-gradle-build-configuration

# Flutter library rules - usually provided by Flutter itself, but good to keep in mind
# -keep class io.flutter.app.** { *; }
# -keep class io.flutter.plugin.** { *; }
# -keep class io.flutter.view.** { *; }
# -keep class io.flutter.embedding.** { *; }

# Rules for Google ML Kit to prevent R8 from removing necessary classes.
# These rules are crucial for ensuring the ML Kit models and components
# are not stripped out during release builds.

# General ML Kit rules
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Specifically for Text Recognition to keep all script options
# The error log indicates specific missing classes for different scripts.
# Keeping all options ensures any script used by TextRecognizer is available.
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }
-keep class com.google.mlkit.vision.text.latin.** { *; } # Ensure Latin is also kept if used
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.**

# For TensorFlow Lite GPU delegate, mentioned in the error
-keep class org.tensorflow.lite.gpu.** { *; }
-dontwarn org.tensorflow.lite.gpu.**

# Rules for Object Detection, if specific models/labels are used
# These might not be strictly necessary if the general ML Kit rules cover them,
# but can be added for robustness if you encounter issues.
-keep class com.google.mlkit.vision.objects.** { *; }
-dontwarn com.google.mlkit.vision.objects.**

# General TensorFlow Lite rules if any custom models are loaded
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Add any other project-specific ProGuard rules here if necessary.
