//import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

//import '../Community/topic.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  //Checks the current user owns the post
  bool checkPostID() {
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // StreamBuilder<QuerySnapshot>(
              //     stream: FirebaseFirestore.instance
              //         .collection('posts')
              //         .snapshots(),
              //     builder: (context, snapshot) {
              //       if (!snapshot.hasData) {
              //         return const CircularProgressIndicator(); // Loading indicator while fetching data
              //       }

              //       var documents = snapshot.data!.docs;

              //       return ListView.builder(
              //           scrollDirection: Axis.vertical,
              //           shrinkWrap: true,
              //           physics: const ClampingScrollPhysics(),
              //           itemCount: documents.length,
              //           itemBuilder: (context, index) {
              //             var document = documents[index];
              //             return Container(
              //               margin: const EdgeInsets.all(1.0),
              //               padding: const EdgeInsets.all(16.0),
              //               decoration: BoxDecoration(
              //                   border: Border.all(color: Colors.black)),
              //               child: Column(
              //                   mainAxisAlignment: MainAxisAlignment.center,
              //                   crossAxisAlignment: CrossAxisAlignment.start,
              //                   children: [
              //                     Row(
              //                       children: <Widget>[
              //                         Text(
              //                           document['title'],
              //                           style: const TextStyle(
              //                               color: Colors.black,
              //                               fontSize: 15,
              //                               fontWeight: FontWeight.bold),
              //                         ),
              //                         const SizedBox(width: 20),
              //                         IconButton(
              //                             onPressed: () {
              //                               Navigator.of(context)
              //                                   .push(MaterialPageRoute(
              //                                 builder: (context) =>
              //                                     const TopicScreen(),
              //                               ));
              //                             },
              //                             icon: const Icon(
              //                               Icons.arrow_forward,
              //                               color: Colors.black,
              //                             ))
              //                       ],
              //                     ),
              //                     Row(
              //                       children: [
              //                         Column(
              //                           mainAxisAlignment:
              //                               MainAxisAlignment.center,
              //                           crossAxisAlignment:
              //                               CrossAxisAlignment.start,
              //                           children: [
              //                             Text(
              //                               "Date of creation: $document['dateCreated'] at 1:00",
              //                               style: const TextStyle(
              //                                   color: Colors.black,
              //                                   fontSize: 10,
              //                                   fontWeight: FontWeight.bold),
              //                             ),
              //                             Text(
              //                               "Last Updated: $document['lastUpdated'] at 1:00",
              //                               style: const TextStyle(
              //                                   color: Colors.black,
              //                                   fontSize: 10,
              //                                   fontWeight: FontWeight.bold),
              //                             ),
              //                           ],
              //                         ),
              //                         const SizedBox(width: 10),
              //                         Visibility(
              //                           visible: checkPostID(),
              //                           child: CircleAvatar(
              //                             backgroundColor: Colors.grey,
              //                             radius: 15.0,
              //                             child: IconButton(
              //                                 iconSize: 15,
              //                                 icon: const Icon(Icons.edit),
              //                                 color: Colors.black,
              //                                 onPressed: () {}),
              //                           ),
              //                         ),
              //                       ],
              //                     ),
              //                   ]),
              //             );
              //           });
              //     })
            ]));
  }
}
