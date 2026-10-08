import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/detection_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
