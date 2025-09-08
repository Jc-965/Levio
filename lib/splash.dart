// import 'package:flutter/material.dart';
// import 'package:parkinson/Main/editProfile.dart';
// import 'navbar.dart';
// import 'singleton.dart';

// class SplashScreen extends StatefulWidget {
//   const SplashScreen({super.key});

//   @override
//   State<SplashScreen> createState() => _SplashScreenState();
// }

// class _SplashScreenState extends State<SplashScreen> {
//   final singleton = Singleton();
//   @override
//   Widget build(BuildContext context) {
//     Future.delayed(const Duration(seconds: 2), () {
//       // Navigate to the main screen after the delay
//       if (singleton.firstTime) {
//         Navigator.of(context).pushReplacement(MaterialPageRoute(
//           builder: (context) => const EditProfileScreen(),
//         ));
//       } else {
//         Navigator.of(context).pushReplacement(MaterialPageRoute(
//           builder: (context) => const Navbar(),
//         ));
//       }
//     });
//     return Scaffold(
//         body: Center(
//             child: ClipOval(
//                 child: Image.network(
//                     "https://lh5.googleusercontent.com/zMMhwXrl94r3PbjZImPfd3zI-LtMd0mGh8dm7uXIipT47JXaHwv9q4AGvCGkO6-ID5DiP46TF5NSs3n6BPem01YuowYzGH8sY2QAS0k-mrFHfkvgD_l4Bd_mkIUF9fOyAkbs-Cpr",
//                     width: 200,
//                     height: 200,
//                     fit: BoxFit.cover))));
//   }
// }
