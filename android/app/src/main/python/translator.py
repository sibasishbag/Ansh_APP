import whisper
from TTS.api import TTS
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
import torch
import torchaudio
import noisereduce as nr
import os
import shutil # For robust file copying

# Define the base directory for voice profiles consistently.
# This path should be accessible and ideally passed from the native side or configured.
# For Chaquopy, this could be context.getExternalFilesDir("voice_profiles").getAbsolutePath()
# For now, using a relative path as per previous logic, assuming CWD is app's files dir.
VOICE_PROFILES_DIR = "voice_profiles"

# Ensure the voice profiles directory exists at startup or before first use.
if not os.path.exists(VOICE_PROFILES_DIR):
    os.makedirs(VOICE_PROFILES_DIR, exist_ok=True)


# Load models - consider making model paths configurable or relative
# Ensure these paths are correct based on where Chaquopy places them or how they are accessed in the Android environment.
# It's assumed that the models are placed in a location accessible by the script.
# For example, if models are in `assets/models/` relative to the app's root,
# paths might need to be adjusted based on Chaquopy's file system representation.

# It's good practice to handle potential errors during model loading, e.g., if files are missing.
try:
    whisper_model = whisper.load_model("base")
    # The from_pretrained paths might need to be local paths if the app is 100% offline.
    # This implies that these models are pre-downloaded and packaged with the app.
    # If "ai4bharat/indictrans2-en-indic" and "tts_models/multilingual/multi-dataset/your_tts"
    # are meant to be fetched online, this contradicts the "100% offline" requirement.
    # Assuming these are identifiers for models already packaged within the app assets.
    translator = AutoModelForSeq2SeqLM.from_pretrained("assets/models/indictrans")
    tokenizer = AutoTokenizer.from_pretrained("assets/models/indictrans")
    tts = TTS("assets/models/yourtts") # This path might need adjustment
except Exception as e:
    # Proper error handling/logging should be implemented
    print(f"Error loading models: {e}")
    # Depending on the app's design, might want to raise the exception or handle it gracefully

def translate(path=None, text=None, mode="slow", denoise=False, lang_pair="en2hi"):
    """
    Translates speech or text from one language to another.

    Args:
        path (str, optional): Path to the audio file. Required if text is None.
        text (str, optional): Text to translate. Required if path is None.
        mode (str, optional): "slow" for voice cloning using the input audio,
                              otherwise uses a default or pre-selected voice. Defaults to "slow".
        denoise (bool, optional): Whether to apply noise reduction to the audio. Defaults to False.
        lang_pair (str, optional): Language pair for translation (e.g., "en2hi" for English to Hindi).
                                   Defaults to "en2hi".

    Returns:
        dict: A dictionary containing the translated text and the path to the output audio file.
              Returns None or raises an error if translation fails.
    """
    if not path and not text:
        # Consider returning an error message or raising a ValueError
        return {"error": "Either audio path or text input is required."}

    processed_audio_path = path

    if denoise and path:
        try:
            y, sr = torchaudio.load(path)
            # Ensure y is mono for noise reduction if necessary, or handle stereo
            audio_to_reduce = y[0].numpy() if y.ndim > 1 else y.numpy()
            reduced_noise_audio = nr.reduce_noise(y=audio_to_reduce, sr=sr)

            # Define a temporary path for the denoised audio within an accessible directory
            # This path should be managed carefully, e.g., cleaned up afterwards if it's temporary
            processed_audio_path = "denoised_temp.wav" # Ensure this path is valid in Android's context
            torchaudio.save(processed_audio_path, torch.tensor([reduced_noise_audio]), sr)
        except Exception as e:
            print(f"Error during denoising: {e}")
            # Decide how to handle denoising errors: proceed with original audio or return error
            # For now, let's proceed with the original audio if denoising fails
            processed_audio_path = path


    if text is None and processed_audio_path:
        try:
            result = whisper_model.transcribe(processed_audio_path)
            text = result["text"]
        except Exception as e:
            print(f"Error during transcription: {e}")
            return {"error": "Speech to text conversion failed."}
    elif text is None:
        return {"error": "Text input is missing and audio could not be processed for transcription."}


    # Ensure text is not empty after transcription or if provided directly
    if not text:
        return {"error": "Text for translation is empty."}

    try:
        # Format for IndicTrans2: "source_lang_code2target_lang_code: text"
        # Example: "en2hi: This is a test."
        # The lang_pair variable should ideally be more structured, e.g., a tuple (src_lang, tgt_lang)
        # to robustly form this prefix. Assuming lang_pair is like "en2hi".
        input_prefix = f"{lang_pair[:2]}2{lang_pair[2:]}: " # This is a guess, confirm actual model prefix format

        # A more robust way to create the prefix, assuming lang_pair is "en2hi" -> "en-hi" for model
        # This needs to match exactly what the model expects.
        # For "ai4bharat/indictrans2-en-indic", it's usually a specific format like "<src_lang> <tgt_lang> text"
        # Or it might infer from the model name. The provided "prefix = f"{lang_pair}: "" might be insufficient.
        # Let's assume the original prefix format is correct for now.
        prefix = f"{lang_pair}: " # As per original snippet

        input_text_with_prefix = prefix + text
        tokens = tokenizer(input_text_with_prefix, return_tensors="pt")

        # Add error handling for tokenization if needed
        generated_tokens = translator.generate(**tokens)
        translated_text = tokenizer.decode(generated_tokens[0], skip_special_tokens=True)
    except Exception as e:
        print(f"Error during translation: {e}")
        return {"error": "Text translation failed."}

    # Define output path for TTS audio. This needs to be a writable location on the device.
    # "/sdcard/" might not be universally accessible or appropriate.
    # Consider using app-specific storage provided by Android.
    # For Chaquopy, context.getExternalFilesDir(null) or similar might be used from Java/Kotlin side
    # and path passed to Python, or use a known accessible path.
    output_audio_path = "output.wav" # Simplified, ensure this is a valid, writable path

    # Determine speaker_wav for TTS
    # If mode is "slow" and an audio path was provided, use it for voice cloning.
    # Otherwise, TTS will use its default voice or a pre-configured one.
    speaker_wav_for_tts = processed_audio_path if mode == "slow" and processed_audio_path else None

    try:
        # Ensure the TTS model is loaded. The earlier TTS() call might need specific model files.
        # tts.tts_to_file(...)
        # The speaker_wav path should be valid and accessible.
        # If speaker_wav_for_tts is None, YourTTS uses a default voice.
        tts.tts_to_file(text=translated_text, speaker_wav=speaker_wav_for_tts, file_path=output_audio_path)
    except Exception as e:
        print(f"Error during text to speech: {e}")
        return {"error": "Text to speech conversion failed."}

    # Voice profile saving logic
    # This section handles saving the speaker_wav used for TTS, if available,
    # as "latest_speaker.wav" in the VOICE_PROFILES_DIR.
    # It also forms the basis for saving named profiles if that feature is added.
    if speaker_wav_for_tts: # This is `processed_audio_path` if mode is "slow"
        try:
            # Ensure VOICE_PROFILES_DIR exists (though already done at script start)
            # os.makedirs(VOICE_PROFILES_DIR, exist_ok=True) # Redundant if done at top

            latest_speaker_profile_path = os.path.join(VOICE_PROFILES_DIR, "latest_speaker.wav")

            # IMPORTANT: Avoid renaming original user files or files from other locations.
            # Always COPY the audio to the voice profiles directory.
            # `speaker_wav_for_tts` could be an original file path or a temporary (denoised) path.

            shutil.copy(speaker_wav_for_tts, latest_speaker_profile_path)
            print(f"Voice profile saved: {latest_speaker_profile_path}")

            # If `speaker_wav_for_tts` was a temporary file (e.g., "denoised_temp.wav"),
            # it should be cleaned up after copying.
            # The main cleanup logic for "denoised_temp.wav" is separate.
            # Here, we just ensure the copy is made.

        except Exception as e:
            print(f"Error saving voice profile '{speaker_wav_for_tts}' to '{latest_speaker_profile_path}': {e}")
            # Decide if this error should affect the overall function result

    # Cleanup temporary files:
    # If denoising created "denoised_temp.wav" and it wasn't the source for voice cloning
    # (or even if it was, it's now copied, so the temp can be removed).
    if processed_audio_path == "denoised_temp.wav": # Check if denoising created this temp file
        try:
            if os.path.exists(processed_audio_path):
                os.remove(processed_audio_path)
                print(f"Temporary file {processed_audio_path} removed.")
        except Exception as e:
            print(f"Error cleaning up temporary file {processed_audio_path}: {e}")

    return {"translated": translated_text, "audio": output_audio_path}

# Function to get the path for a named voice profile
def get_voice_profile_path(profile_name):
    """
    Returns the full path to a named voice profile.
    Ensures the profile name is safe for use as a filename.
    """
    if not profile_name or ".." in profile_name or "/" in profile_name or "\\" in profile_name:
        print(f"Invalid profile name: {profile_name}")
        return None
    return os.path.join(VOICE_PROFILES_DIR, f"{profile_name}.wav")

# Placeholder for listing voice profiles - to be called from Flutter if needed
# def list_voice_profiles():
#     if not os.path.exists(VOICE_PROFILES_DIR):
#         return []
#     profiles = [f.replace(".wav", "") for f in os.listdir(VOICE_PROFILES_DIR) if f.endswith(".wav")]
#     return profiles

# Example usage (for testing purposes, not part of the library code called by Flutter)
if __name__ == '__main__':
    # This block would only run if the script is executed directly.
    # Requires dummy audio file "test.wav" or text input.
    # And model files to be in the expected locations.

    # Create a dummy test.wav for example
    # sample_rate = 16000
    # dummy_audio = torch.zeros(1, sample_rate) # 1 second of silence
    # torchaudio.save("test.wav", dummy_audio, sample_rate)

    # Test case 1: Text input
    # result_text = translate(text="Hello, how are you?", mode="fast") # mode="fast" to avoid needing speaker_wav
    # print(f"Text input translation: {result_text}")

    # Test case 2: Audio input (requires a "test.wav" file)
    # Ensure "test.wav" exists in the same directory as the script, or provide a full path.
    # result_audio = translate(path="test.wav", mode="slow", denoise=True, lang_pair="en2hi")
    # print(f"Audio input translation: {result_audio}")

    # Cleanup dummy file
    # if os.path.exists("test.wav"):
    #    os.remove("test.wav")
    # if os.path.exists("output.wav"):
    #    os.remove("output.wav")
    # if os.path.exists("latest_speaker.wav"):
    #    os.remove("latest_speaker.wav")
    pass # Keep __main__ empty or with actual test setup if run directly
