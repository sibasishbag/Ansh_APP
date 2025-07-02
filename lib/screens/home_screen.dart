import 'package:flutter/material.dart';
import 'dart:io'; // For Directory and File operations
import 'package:path_provider/path_provider.dart'; // To get accessible directory paths
import 'package:dropdown_search/dropdown_search.dart'; // For the dropdown
import 'package:permission_handler/permission_handler.dart'; // For storage permissions

import '../services/python_bridge.dart';
// For file picking, if that's how audio input is handled.
// import 'package:file_picker/file_picker.dart';


// Define the directory name for voice profiles, relative to a public directory
const String voiceProfilesSubDir = "OfflineTranslatorVoiceProfiles";

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _inputText = "";
  String _translatedText = "";
  bool _isDenoiseEnabled = false;
  bool _isLoading = false;

  String? _selectedVoiceProfileFile; // Stores the full path to the selected .wav file
  List<File> _voiceProfileFiles = []; // Stores File objects for available .wav profiles

  TextEditingController _newProfileNameController = TextEditingController();


  @override
  void initState() {
    super.initState();
    _loadVoiceProfiles();
  }

  Future<Directory?> _getVoiceProfilesDirectory() async {
    // Request storage permission
    var status = await Permission.manageExternalStorage.request(); // More encompassing
    if (status.isDenied) {
       status = await Permission.storage.request(); // Fallback for older Android or less strict
    }

    if (status.isGranted) {
        // Try to get a common public directory like Documents or Downloads
        //getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        // Or use app's external files directory which doesn't require special permissions for app's own files
        Directory? baseDir = await getExternalStorageDirectory(); // App's external files dir: /storage/emulated/0/Android/data/com.example.app/files
        if (baseDir != null) {
            final profileDir = Directory('${baseDir.path}/$voiceProfilesSubDir');
            if (!await profileDir.exists()) {
                await profileDir.create(recursive: true);
            }
            print("Voice profiles directory: ${profileDir.path}");
            return profileDir;
        }
    } else {
        print("Storage permission denied.");
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Storage permission is required to manage voice profiles.")),
        );
    }
    return null;
  }

  Future<void> _loadVoiceProfiles() async {
    Directory? profilesDir = await _getVoiceProfilesDirectory();
    if (profilesDir != null) {
        final List<FileSystemEntity> entities = await profilesDir.list().toList();
        final List<File> wavFiles = entities
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.wav'))
            .toList();
        setState(() {
            _voiceProfileFiles = wavFiles;
            // If a selected profile was stored, try to re-select it if it still exists
            if (_selectedVoiceProfileFile != null && !wavFiles.any((f) => f.path == _selectedVoiceProfileFile)) {
                _selectedVoiceProfileFile = null;
            } else if (wavFiles.isNotEmpty && _selectedVoiceProfileFile == null) {
                // Optionally default to the first profile or "latest_speaker.wav" if present
                // _selectedVoiceProfileFile = wavFiles.first.path;
            }
        });
    }
  }

  // TODO: Implement function to save current output voice (if any) as a new named profile
  // This would involve:
  // 1. Getting the path of the "latest_speaker.wav" (or the last generated output.wav if that's the source) from Python.
  //    This might require Python to return this path, or for Flutter to know its location.
  //    Python currently saves "latest_speaker.wav" in its CWD's "voice_profiles" subdir.
  //    Flutter needs access to this file to copy it.
  //    This implies the Python's VOICE_PROFILES_DIR should be the same as Flutter's _getVoiceProfilesDirectory().
  //    This needs careful path synchronization between Python and Flutter.
  //
  // 2. Showing a dialog to get a name for the new profile.
  // 3. Copying the source .wav file to "{profilesDir.path}/{new_profile_name}.wav".
  // 4. Calling _loadVoiceProfiles() to refresh the list.

  Future<void> _showSaveProfileDialog() async {
    // First, ensure there's a "latest_speaker.wav" to save.
    // This requires knowing its path. Let's assume Python places it in the shared voice profiles dir.
    Directory? profilesDir = await _getVoiceProfilesDirectory();
    if (profilesDir == null) return;

    final latestSpeakerFile = File('${profilesDir.path}/latest_speaker.wav');
    if (!await latestSpeakerFile.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("No recent voice recording (latest_speaker.wav) found to save.")),
        );
        return;
    }

    _newProfileNameController.clear();
    showDialog(
        context: context,
        builder: (context) {
            return AlertDialog(
                title: Text("Save New Voice Profile"),
                content: TextField(
                    controller: _newProfileNameController,
                    decoration: InputDecoration(hintText: "Enter profile name (e.g., John)"),
                ),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("Cancel"),
                    ),
                    ElevatedButton(
                        onPressed: () async {
                            String name = _newProfileNameController.text.trim();
                            if (name.isNotEmpty) {
                                final newProfileFile = File('${profilesDir.path}/$name.wav');
                                if (await newProfileFile.exists()) {
                                     ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("A profile with this name already exists.")),
                                    );
                                    return;
                                }
                                try {
                                    await latestSpeakerFile.copy(newProfileFile.path);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Profile '$name' saved.")),
                                    );
                                    _loadVoiceProfiles(); // Refresh list
                                    Navigator.pop(context);
                                } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Error saving profile: $e")),
                                    );
                                }
                            }
                        },
                        child: Text("Save"),
                    ),
                ],
            );
        },
    );
}


  Future<void> _translate({String? textFromInput, String? audioPathFromPicker}) async {
    // Use _inputText if textFromInput is not directly provided (e.g. button press uses state)
    final String currentText = textFromInput ?? _inputText;

    if ((currentText.isEmpty) && (audioPathFromPicker == null || audioPathFromPicker.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter text or select an audio file.")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _translatedText = ""; // Clear previous translation
    });

    try {
      // Determine mode: "slow" for voice cloning (if audioPath is given or a voice profile is selected for text input)
      // or "fast" (default voice) otherwise.
      // The python script's `mode` parameter:
      // - "slow": uses `speaker_wav` (either the input audio itself or a selected profile)
      // - not "slow" (e.g. "fast"): ignores `speaker_wav`, uses default TTS voice

      String mode = "fast"; // Default mode
      String? speakerWavPath;

      if (audioPath != null && audioPath.isNotEmpty) {
        // Voice input: use the input audio for cloning if mode is slow
        mode = "slow"; // Assuming voice input always tries to clone from itself
        speakerWavPath = audioPath;
      } else if (text != null && text.isNotEmpty && _selectedVoiceProfile != null) {
        // Text input with a selected voice profile: use the profile for cloning
        mode = "slow";
        // This requires knowing the full path to the selected voice profile.
        // speakerWavPath = await getVoiceProfilePath(_selectedVoiceProfile!); // Implement this
        // For now, assuming python_bridge or python script handles resolving "username.wav"
        speakerWavPath = _selectedVoiceProfile;
      }


      final result = await PythonBridge.translate(
        text: text, // Pass text from TextField or null if audio input
        path: audioPath, // Pass audio file path or null if text input
        denoise: _isDenoiseEnabled,
        mode: mode, // "slow" for cloning, "fast" for default voice
        // lang_pair: "en2hi", // This could be configurable in UI
        // The `speaker_wav` argument for `tts.tts_to_file` is handled inside `translator.py`
        // based on `mode` and `path`. If a specific voice profile is to be used for text input,
        // the `path` argument to `PythonBridge.translate` might need to carry that profile's path
        // and `mode` set to "slow".
        // Let's adjust `PythonBridge.translate` or `translator.py` if `speaker_wav` needs to be explicit outside of `path`.
        // Current `translator.py` uses `path` as `speaker_wav` if `mode == "slow"`.
        // So, if translating text with a specific voice profile, that profile's path should be passed as `path`.
        // This means `audioPath` parameter here could be the voice profile path for text translation.

        // Revised logic for python call:
        // If text input and voice profile selected: text=text, path=profile_path, mode="slow"
        // If audio input: text=null, path=audio_file_path, mode="slow" (for cloning from source) or "fast"
        // If text input, no profile: text=text, path=null, mode="fast"
      );

      if (result.containsKey("translated")) {
        setState(() {
          _translatedText = result["translated"]!;
        });
        if (result.containsKey("audio") && result["audio"] != null) {
          PythonBridge.playAudio(result["audio"]!);
        }
      } else if (result.containsKey("error")) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${result["error"]}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to translate: $e")),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Example function to pick an audio file (requires file_picker package)
  /*
  Future<void> _pickAudioFile() async {
    // FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.audio);
    // if (result != null) {
    //   String? filePath = result.files.single.path;
    //   if (filePath != null) {
    //     _translate(audioPath: filePath);
    //   }
    // } else {
    //   // User canceled the picker
    // }
  }
  */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Offline Translator"),
        // TODO: Add actions for settings or voice profile management if needed
      ),
      body: SingleChildScrollView( // Added SingleChildScrollView for smaller screens
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Text Input Field
            TextField(
              decoration: InputDecoration(
                hintText: "Enter text to translate",
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _inputText = value,
              onSubmitted: (value) {
                _inputText = value; // Ensure _inputText is updated
                _translate(text: _inputText);
              },
            ),
            SizedBox(height: 12),

            // Voice Profile Dropdown
            if (_voiceProfileFiles.isNotEmpty) // Only show if profiles exist
              DropdownSearch<File>(
                items: _voiceProfileFiles,
                itemAsString: (File? file) => file != null ? file.path.split('/').last.replaceAll('.wav', '') : "Select Profile",
                selectedItem: _voiceProfileFiles.firstWhere((f) => f.path == _selectedVoiceProfileFile, orElse: () => _voiceProfileFiles.first), // Handle null case better
                onChanged: (File? newValue) {
                  setState(() {
                    _selectedVoiceProfileFile = newValue?.path;
                  });
                },
                dropdownDecoratorProps: DropDownDecoratorProps(
                  dropdownSearchDecoration: InputDecoration(
                    labelText: "Select Voice Profile (for text input)",
                    border: OutlineInputBorder(),
                  ),
                ),
                popupProps: PopupProps.menu(
                  showSearchBox: true,
                  itemBuilder: (context, item, isSelected) => ListTile(
                    title: Text(item.path.split('/').last.replaceAll('.wav', '')),
                    // subtitle: Text(item.path), // Optionally show full path
                  ),
                  searchFieldProps: TextFieldProps(
                    decoration: InputDecoration(
                      hintText: "Search profiles...",
                      border: OutlineInputBorder(),
                    )
                  )
                ),
              ),
            SizedBox(height: 12),

            // Save Voice Profile Button
            ElevatedButton.icon(
                icon: Icon(Icons.save_alt),
                label: Text("Save Current Voice as Profile"),
                onPressed: _showSaveProfileDialog,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            ),
            SizedBox(height: 12),


            // Translate Button for Text Input
            ElevatedButton(
              onPressed: _isLoading ? null : () => _translate(textFromInput: _inputText),
              child: Text("Translate Text"),
              style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12)),
            ),
            SizedBox(height: 20),

            // TODO: Implement Audio Input Button (requires file_picker package and logic)
            // ElevatedButton(
            //   onPressed: _isLoading ? null : () => _pickAudioFileAndTranslate(),
            //   child: Text("Translate from Audio File"),
            //   style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12)),
            // ),
            // SizedBox(height: 20),

            // Denoise Switch
            SwitchListTile(
              title: Text("Enable Noise Reduction (for audio input)"),
              value: _isDenoiseEnabled,
              onChanged: (bool value) {
                setState(() {
                  _isDenoiseEnabled = value;
                });
              },
            ),
            SizedBox(height: 20),

            // Loading Indicator
            if (_isLoading) Center(child: CircularProgressIndicator()),
            SizedBox(height: 20),

            // Translated Output
            Text(
              "Translated Output:",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _translatedText.isEmpty && !_isLoading ? "Translation will appear here." : _translatedText,
                style: TextStyle(fontSize: 16),
                minLines: 3, // Ensure some space for the text
                maxLines: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
