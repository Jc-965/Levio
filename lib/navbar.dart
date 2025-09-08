import 'package:flutter/material.dart';
import 'package:parkinson/linechart.dart';

import 'Firebase/firebase_cloud.dart';
import 'Main/manage.dart';
import 'Main/recovery.dart';
import 'Main/community.dart';
import 'Main/profile.dart';
import 'singleton.dart';

class Navbar extends StatefulWidget {
  const Navbar({super.key});

  @override
  State<Navbar> createState() => _NavbarState();
}

class _NavbarState extends State<Navbar> {
  final singleton = Singleton();
  int currentIndex = 0;
  bool button = false;
  bool addPost = false;
  bool editProfile = false;
  IconData iconButton = Icons.edit;
  String name = "[Name]";
  String email = "[Email]";

  final List<Widget> tabs = [
    //const HomeScreen(),
    const LineChartSample1(),
    const ManageScreen(),
    const RecoveryScreen(),
    const CommunityScreen(),
    const ProfileScreen()
  ];

  List<String> title = ["Home", "Manage", "Recovery", "Community", "Profile"];

  void checkTab() {
    button = true;
    if (currentIndex == 3) {
      editProfile = false;
      addPost = true;
      iconButton = Icons.add;
    }
    if (currentIndex == 4) {
      addPost = false;
      editProfile = true;
      iconButton = Icons.edit;
    }
  }

  @override
  void initState() {
    super.initState();
    currentIndex = singleton.page;
    if (currentIndex == 3 || currentIndex == 4) checkTab();
  }

  void updateAccount() async {
    singleton.setEmail(email);
    singleton.setName(name);
    FirebaseCloud().updateUser(name, singleton.image, email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
          leadingWidth: 200,
          leading: Text(
            "    ${title[currentIndex]}",
            style: const TextStyle(fontSize: 25.0, fontWeight: FontWeight.bold),
          ),
          actions: <Widget>[
            IconButton(
                iconSize: 30,
                icon: const Icon(Icons.settings),
                onPressed: () {
                  Navigator.pushNamed(context, '/settingsScreen');
                })
          ]),
      body: tabs[currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: singleton.themeColor[singleton.colorMode][21],
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
        selectedItemColor: singleton.themeColor[singleton.colorMode]
            [19], // Color for selected item
        unselectedItemColor: singleton.themeColor[singleton.colorMode]
            [20], // Color for unselected items
        onTap: (int index) {
          setState(() {
            currentIndex = index;
            singleton.setPage(index);
            button = false;
            if (currentIndex == 3 || currentIndex == 4) checkTab();
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: title[0],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.manage_search_rounded),
            label: title[1],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.healing_rounded),
            label: title[2],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.people_alt_rounded),
            label: title[3],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: title[4],
          ),
        ],
      ),
      floatingActionButton: Visibility(
        visible: button,
        child: Ink(
          decoration: ShapeDecoration(
            color: singleton.themeColor[singleton.colorMode][2],
            shape: const CircleBorder(),
          ),
          child: IconButton(
            iconSize: 35,
            icon: Icon(iconButton),
            color: Colors.white,
            onPressed: () {
              setState(() {
                if (addPost) {}

                if (editProfile) {
                  showDialog<String>(
                      context: context,
                      builder: (BuildContext c) => AlertDialog(
                            content: const Text(
                              'Edit Profile',
                              style: TextStyle(
                                  fontSize: 15.0,
                                  fontWeight: FontWeight.normal),
                            ),
                            actions: <Widget>[
                              TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Name: ',
                                  // You can customize other properties like labelStyle, hintStyle, etc.
                                ),
                                onChanged: (text) {
                                  name = text;
                                },
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                decoration: const InputDecoration(
                                  labelText: 'Email: ',
                                  // You can customize other properties like labelStyle, hintStyle, etc.
                                ),
                                onChanged: (text) {
                                  email = text;
                                },
                              ),
                              const SizedBox(height: 20),
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.pop(c);
                                        Navigator.pushNamedAndRemoveUntil(
                                            context, '/', (r) => false);
                                      },
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                            color: singleton.themeColor[
                                                singleton.colorMode][13],
                                            fontSize: 15,
                                            fontWeight: FontWeight.normal),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        updateAccount();
                                        Navigator.pop(c);
                                        Navigator.pushNamedAndRemoveUntil(
                                            context, '/', (r) => false);
                                      },
                                      child: Text(
                                        'Submit',
                                        style: TextStyle(
                                            color: singleton.themeColor[
                                                singleton.colorMode][13],
                                            fontSize: 15,
                                            fontWeight: FontWeight.normal),
                                      ),
                                    ),
                                  ]),
                            ],
                          ));
                }
              });
            },
          ),
        ),
      ),
    );
  }
}
