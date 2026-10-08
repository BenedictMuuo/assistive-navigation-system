import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'screens/detection_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Connect to the Firebase project before anything else runs.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Portrait only. The image converter assumes the phone is held upright,
  // which is how it is carried when walking.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const AssistiveNavApp());
}

class AssistiveNavApp extends StatelessWidget {
  const AssistiveNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Assistive Navigation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColours.primary),
        useMaterial3: true,
      ),
      home: const DetectionScreen(),
    );
  }
}