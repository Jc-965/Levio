import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
//import 'package:parkinson/Firebase/firebase_cloud.dart';
import '../singleton.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final singleton = Singleton();
  String name = "[Name]";
  String email = "[Email]";
  String image = "images/711128.png";
  final picker = ImagePicker();
  String posts = "0";
  String exercises = "0";

  Future<void> updateImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        image = pickedFile.path;
      });
      singleton.setImage(image);
    }
  }

  @override
  void initState() {
    image = singleton.image;
    name = singleton.name;
    email = singleton.email;
    posts = '${singleton.postNum}';
    exercises = '${singleton.exerNum}';
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: Colors.transparent,
                radius: 50.0,
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      updateImage();
                    });
                  },
                  icon: Transform.scale(
                    scale: 2,
                    child: Image.asset(
                      image,
                      height: 50,
                      width: 50,
                    ),
                  ),
                ),
              ),
              Text(
                name,
                style: const TextStyle(
                    fontSize: 40.0, fontWeight: FontWeight.bold),
              ),
              Text(
                email,
                style: const TextStyle(
                    fontSize: 20.0, fontWeight: FontWeight.normal),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.messenger_rounded,
                    size: 35.0,
                  ),
                  const SizedBox(width: 20),
                  const Text(
                    'Posts: ',
                    style: TextStyle(
                        fontSize: 30.0, fontWeight: FontWeight.normal),
                  ),
                  const SizedBox(width: 20),
                  Text(
                    exercises,
                    style: const TextStyle(
                        fontSize: 30.0, fontWeight: FontWeight.normal),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.directions_run_rounded,
                    size: 35.0,
                  ),
                  const SizedBox(width: 20),
                  const Text(
                    "Exercises: ",
                    style: TextStyle(
                        fontSize: 30.0, fontWeight: FontWeight.normal),
                  ),
                  const SizedBox(width: 20),
                  Text(
                    exercises,
                    style: const TextStyle(
                        fontSize: 30.0, fontWeight: FontWeight.normal),
                  ),
                ],
              ),
            ]));
  }
}
