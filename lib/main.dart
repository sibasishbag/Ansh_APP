import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart'; // Corrected import path
import 'screens/setup_screen.dart'; // Corrected import path

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Translator',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        visualDensity: VisualDensity.adaptivePlatformDensity, // Added for better cross-platform aesthetics
      ),
      home: InitApp(),
    );
  }
}

class InitApp extends StatelessWidget {
  Future<bool> isFirstLaunch() async {
    // Ensure SharedPreferences is initialized before accessing it.
    // WidgetsFlutterBinding.ensureInitialized(); // Usually needed if SharedPreferences is used before runApp, but FutureBuilder handles init.
    final prefs = await SharedPreferences.getInstance();
    // Check if specific keys exist, indicating setup has been completed.
    // Using "mode" and "outputMode" as per the setup_screen.dart logic.
    return !(prefs.containsKey("mode") && prefs.containsKey("outputMode"));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: isFirstLaunch(),
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show a loading indicator while checking first launch status
          return Scaffold( // Added Scaffold for proper layout of CircularProgressIndicator
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          // Handle errors, e.g., if SharedPreferences fails
          return Scaffold( // Added Scaffold
            body: Center(child: Text("Error initializing app: ${snapshot.error}")),
          );
        }
        if (snapshot.hasData) {
          // If data is available, decide which screen to show
          return snapshot.data! ? SetupScreen() : HomeScreen();
        } else {
          // Fallback, though ideally hasData should cover all non-error states after waiting
          return Scaffold( // Added Scaffold
            body: Center(child: Text("Initializing...")),
          );
        }
      },
    );
  }
}
