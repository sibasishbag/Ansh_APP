import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart'; // Ensure this path is correct

class SetupScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("App Setup"),
      ),
      body: Center( // Centered the content
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // Vertically center content
            crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch button horizontally
            children: <Widget>[
              Text(
                "Welcome to Offline Translator!",
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              Text(
                "This is a one-time setup. We'll configure some default settings for you.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  textStyle: TextStyle(fontSize: 18),
                ),
                onPressed: () async { // Added async for SharedPreferences
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    // Set default preferences as per the original specification
                    await prefs.setString("mode", "slow");
                    await prefs.setString("outputMode", "voice+text");

                    // Navigate to HomeScreen and remove SetupScreen from back stack
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => HomeScreen()),
                    );
                  } catch (e) {
                    // Handle potential errors, e.g., SharedPreferences failing
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error saving settings: $e")),
                    );
                  }
                },
                child: Text("Complete Setup & Start App"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
