import 'package:flutter/services.dart';

class PythonBridge {
  // Define the method channel. The name must match the one used in the native (Android/iOS) part.
  static const platform = MethodChannel("translator_channel");

  static Future<Map<String, dynamic>> translate({
    String? text, // Text to translate (optional if path is provided)
    String? path, // Path to audio file (optional if text is provided)
    bool denoise = false, // Whether to apply noise reduction
    String mode = "slow", // Translation mode: "slow" for voice cloning, "fast" for default voice
    String lang_pair = "en2hi", // Language pair, e.g., "en2hi"
    // Added path and lang_pair to match Python script's capabilities more directly.
    // The original snippet had `text`, `denoise`, `mode`.
    // `path` is crucial for audio input or for specifying a voice profile for text-to-speech.
    // `lang_pair` allows specifying the translation languages.
  }) async {
    try {
      final result = await platform.invokeMethod("translate", {
        "text": text,
        "path": path, // Pass the audio path to Python
        "denoise": denoise,
        "mode": mode,
        "lang_pair": lang_pair, // Pass the language pair
      });

      // Ensure the result is a Map<String, dynamic>
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      } else {
        // Handle unexpected result type
        return {"error": "Invalid response type from platform method."};
      }
    } on PlatformException catch (e) {
      // Handle platform exceptions (e.g., method not implemented, Python error)
      print("Error calling 'translate' method: ${e.message}");
      return {"error": "Platform communication error: ${e.message}"};
    } catch (e) {
      // Handle other unexpected errors
      print("Unexpected error in PythonBridge.translate: $e");
      return {"error": "An unexpected error occurred."};
    }
  }

  static Future<void> playAudio(String path) async {
    try {
      await platform.invokeMethod("play_audio", {"path": path});
    } on PlatformException catch (e) {
      // Handle platform exceptions
      print("Error calling 'play_audio' method: ${e.message}");
      // Optionally, rethrow or handle as needed by the UI
    } catch (e) {
      // Handle other unexpected errors
      print("Unexpected error in PythonBridge.playAudio: $e");
    }
  }

  // TODO: Consider adding other methods if needed, e.g.,
  // - To manage voice profiles (list, save, delete)
  // - To get available languages
  // - To initialize Python backend or models if that's a separate step
}
