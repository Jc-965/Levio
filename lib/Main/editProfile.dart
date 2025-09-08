import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:parkinson/main.dart';

import '../Firebase/firebase_cloud.dart';
import '../singleton.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final singleton = Singleton();
  String name = "[Name]";
  String email = "[Email]";
  String image = "images/711128.png";
  final picker = ImagePicker();

  Future<void> updateImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        image = pickedFile.path;
      });
    }
  }

  void updateAccount() {
    singleton.setEmail(email);
    singleton.setName(name);
    singleton.setImage(image);
    FirebaseCloud().createUser(name, image, email, 0, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: false,
        body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const SizedBox(height: 20),
                  Center(
                    child: CircleAvatar(
                      backgroundColor: Colors.transparent,
                      radius: 50.0,
                      child: IconButton(
                        onPressed: () {
                          setState(() {
                            updateImage();
                          });
                        },
                        icon: Transform.scale(
                          scale: 1,
                          child: Image.asset(
                            image,
                            height: 100,
                            width: 100,
                          ),
                        ),
                      ),
                    ),
                  ),
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
                  const SizedBox(height: 25),
                  Center(
                    child: TextButton(
                      onPressed: () async {
                        updateAccount();
                        if (singleton.firstTime) {
                          singleton.setFirstTime(false);
                          Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => MyApp()),
                              (r) => false);
                        } else {
                          Navigator.pushNamed(context, '/');
                        }
                      },
                      child: const Text(
                        'Submit',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.normal),
                      ),
                    ),
                  ),
                ]))));
  }
}
