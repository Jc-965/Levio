import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:parkinson/Firebase/firebase_cloud.dart';
import 'package:parkinson/routes.dart';
import 'package:parkinson/singleton.dart';

import 'Firebase/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

//import 'singleton.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final singleton = Singleton();
  await SharedPreferences.getInstance().then((prefs) async {
    if (prefs.containsKey('userID')) {
      FirebaseCloud().getUser();
    } else {
      singleton.setFirstTime(true);
    }
    if (prefs.containsKey('theme')) {
      singleton.switchColorTheme(await singleton.getTheme());
    } else {
      singleton.switchColorTheme(false);
    }
  });
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  MyApp({super.key});
  final singleton = Singleton();

  @override
  Widget build(BuildContext context) {
    final singleton = Singleton();
    return MaterialApp(
      routes: singleton.firstTime ? editProfileRoutes : screenRoutes,
      theme: ThemeData(
        colorScheme: ColorScheme(
          brightness: Brightness.light,
          surface: singleton.themeColor[0][22], //appbar
          onSurface: singleton.themeColor[singleton.colorMode]
              [1], // default color
          background: singleton.themeColor[0][0], // scaffold
          //Not needed
          primary: Colors.grey,
          onPrimary: Colors.grey,
          secondary: Colors.grey,
          onSecondary: Colors.grey,
          error: Colors.grey,
          onError: Colors.grey,
          onBackground: Colors.grey,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme(
          brightness: Brightness.dark,
          surface: singleton.themeColor[1][22], //appbar
          onSurface: singleton.themeColor[singleton.colorMode]
              [1], // default color
          background: singleton.themeColor[1][0], // scaffold
          //Not needed
          primary: Colors.grey,
          onPrimary: Colors.grey,
          secondary: Colors.grey,
          onSecondary: Colors.grey,
          error: Colors.grey,
          onError: Colors.grey,
          onBackground: Colors.grey,
        ),
      ),
      themeMode: singleton.colorMode == 0 ? ThemeMode.light : ThemeMode.dark,
      debugShowCheckedModeBanner: false,
    );
  }
}
