import 'package:flutter/material.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:parkinson/main.dart';
// import 'package:parkinson/navbar.dart';
import 'package:restart_app/restart_app.dart';

import 'singleton.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final singleton = Singleton();
  double sound = 20;
  bool notification = false;
  bool theme = false;

  @override
  void initState() {
    super.initState();
    if (singleton.colorMode == 0) {
      theme = false;
    } else {
      theme = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
            ),
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => MyApp()),
                  (r) => false);
            },
          ),
          title: const Text(
            "Settings",
            style: TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
          ),
        ),
        body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                    const Text(
                      "Light",
                      style: TextStyle(
                          fontSize: 20.0, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 5),
                    FlutterSwitch(
                      width: 75.0,
                      height: 35.0,
                      toggleSize: 20.0,
                      value: theme,
                      borderRadius: 20.0,
                      padding: 2.0,
                      activeToggleColor: const Color(0xFF6E40C9),
                      inactiveToggleColor: const Color(0xFF2F363D),
                      activeSwitchBorder: Border.all(
                        color: const Color(0xFF3C1E70),
                        width: 6.0,
                      ),
                      inactiveSwitchBorder: Border.all(
                        color: const Color(0xFFD1D5DA),
                        width: 6.0,
                      ),
                      activeColor: const Color(0xFF271052),
                      inactiveColor: Colors.white,
                      activeIcon: const Icon(
                        Icons.nightlight_round,
                        color: Color(0xFFF8E3A1),
                      ),
                      inactiveIcon: const Icon(
                        Icons.wb_sunny,
                        color: Color(0xFFFFDF5D),
                      ),
                      onToggle: (val) {
                        setState(() {
                          theme = val;
                          print(val);
                          singleton.switchColorTheme(val);
                          Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => MyApp()),
                              (r) => false);
                        });
                      },
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      "Dark",
                      style: TextStyle(
                          fontSize: 20.0, fontWeight: FontWeight.bold),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                  //   const Text(
                  //     "Notifications",
                  //     style: TextStyle(
                  //         fontSize: 20.0, fontWeight: FontWeight.bold),
                  //   ),
                  //   const SizedBox(width: 10),
                  //   FlutterSwitch(
                  //     width: 55.0,
                  //     height: 25.0,
                  //     valueFontSize: 12.0,
                  //     toggleSize: 18.0,
                  //     value: notification,
                  //     onToggle: (val) {
                  //       setState(() {
                  //         notification = val;
                  //       });
                  //     },
                  //   ),
                  // ]),
                  ElevatedButton(
                    onPressed: () {
                      showDialog<String>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                                content:
                                    const Text('Account Deletion Successful!'),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () async {
                                      await singleton.deleteAccount();
                                      Restart.restartApp();
                                    },
                                    child: const Text('Ok'),
                                  ),
                                ],
                              ));
                    },
                    child: const Text(
                      'Delete Account',
                      style:
                          TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                    ),
                  )
                ]))));
  }
}
