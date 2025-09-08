import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../singleton.dart';

class FirebaseCloud {
  final firestore = FirebaseFirestore.instance;
  final singleton = Singleton();

  String generateUUID() {
    return const Uuid().v4();
  }

  Future<void> createUser(String name, String profileImage, String email,
      int postNum, int exerNum) async {
    String userId = generateUUID();
    singleton.setUID(userId);
    DocumentSnapshot existingDoc =
        await firestore.collection('users').doc(userId).get();
    if (existingDoc.exists) {
    } else {
      try {
        await firestore.collection('users').doc(userId).set({
          'name': name,
          'profileImage': profileImage,
          'email': email,
          'postNum': postNum,
          'exerNum': exerNum,
          'logs': [],
          'schedules': []
        });
      } catch (e) {
        print('Error creating user: $e');
      }
    }
  }

  Future<void> getUser() async {
    String documentId = await singleton.getUID();
    try {
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(documentId)
          .get();

      if (documentSnapshot.exists) {
        singleton.setName(documentSnapshot.get('name'));
        singleton.setImage(documentSnapshot.get('profileImage'));
        singleton.setEmail(documentSnapshot.get('email'));
        singleton.setPostNum(documentSnapshot.get('postNum'));
        singleton.setExerNum(documentSnapshot.get('exerNum'));

        Map<String, dynamic> data1 =
            documentSnapshot.data() as Map<String, dynamic>;
        List<dynamic> logs = data1['logs'] as List<dynamic>;
        List<String> logList =
            logs.map((dynamic item) => item.toString()).toList();
        singleton.setLogIDs(logList);

        Map<String, dynamic> data2 =
            documentSnapshot.data() as Map<String, dynamic>;
        List<dynamic> schedules = data2['schedules'] as List<dynamic>;
        List<String> scheduleList =
            schedules.map((dynamic item) => item.toString()).toList();
        singleton.setScheduleIDs(scheduleList);

        // Perform actions with the data
        print('Document ID: ${documentSnapshot.id}');
      } else {
        print('Document with ID $documentId does not exist.');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> updateUser(
      String name, String profileImage, String email) async {
    String documentId = await singleton.getUID();
    try {
      // Reference to the Firestore document
      DocumentReference documentReference =
          FirebaseFirestore.instance.collection('users').doc(documentId);

      // Create a map of fields to update
      Map<String, dynamic> updatedFields = {
        'name': name,
        'profileImage': profileImage,
        'email': email,
      };

      // Update the fields in the document
      await documentReference.update(updatedFields);

      print('Document with ID $documentId updated successfully.');
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> updateNums(int p, int e) async {
    String documentId = await singleton.getUID();
    try {
      // Reference to the Firestore document
      DocumentReference documentReference =
          FirebaseFirestore.instance.collection('users').doc(documentId);

      // Create a map of fields to update
      Map<String, dynamic> updatedFields = {'postNum': p, 'exerNum': e};

      // Update the fields in the document
      await documentReference.update(updatedFields);

      print('Document with ID $documentId updated successfully.');
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> idList(bool listType) async {
    String documentId = await singleton.getUID();
    try {
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(documentId)
          .get();

      if (documentSnapshot.exists) {
        if (listType) {
          Map<String, dynamic> data =
              documentSnapshot.data() as Map<String, dynamic>;
          List<dynamic> logs = data['logs'] as List<dynamic>;
          List<String> logList =
              logs.map((dynamic item) => item.toString()).toList();
          singleton.setLogIDs(logList);
        } else {
          Map<String, dynamic> data =
              documentSnapshot.data() as Map<String, dynamic>;
          List<dynamic> schedules = data['schedules'] as List<dynamic>;
          List<String> scheduleList =
              schedules.map((dynamic item) => item.toString()).toList();
          singleton.setScheduleIDs(scheduleList);
        }

        // Perform actions with the data
        print('Document ID: ${documentSnapshot.id}');
      } else {
        print('Document with ID $documentId does not exist.');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> createLogs(String time, String symptom, String severity) async {
    String documentId = generateUUID();
    updateLogsList(documentId);
    DocumentSnapshot existingDoc =
        await firestore.collection('logs').doc(documentId).get();
    if (existingDoc.exists) {
      DocumentReference documentReference =
          FirebaseFirestore.instance.collection('logs').doc(documentId);
      Map<String, dynamic> updatedFields = {
        'time': time,
        'symptom': symptom,
        'severity': severity,
      };
      await documentReference.update(updatedFields);
    } else {
      try {
        await firestore.collection('logs').doc(documentId).set({
          'time': time,
          'symptom': symptom,
          'severity': severity,
        });
      } catch (e) {
        print('Error creating log: $e');
      }
    }
  }

  Future<void> getLogs(String documentId) async {
    try {
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection('logs')
          .doc(documentId)
          .get();

      if (documentSnapshot.exists) {
        singleton.addLogList(documentSnapshot.get('time'),
            documentSnapshot.get('symptom'), documentSnapshot.get('severity'));

        // Perform actions with the data
        print('Document ID: ${documentSnapshot.id}');
      } else {
        print('Document with ID $documentId does not exist.');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  void updateLogsList(String logsId) async {
    String documentId = await singleton.getUID();
    DocumentReference docRef = firestore.collection('users').doc(documentId);

    try {
      await docRef.update({
        'logs': FieldValue.arrayUnion([logsId])
      });

      print('Field updated successfully.');
    } catch (e) {
      print('Error updating field: $e');
    }
  }

  Future<void> createSchedule(String name, String details, String days) async {
    String documentId = generateUUID();
    updateSchedulesList(documentId);
    DocumentSnapshot existingDoc =
        await firestore.collection('schedules').doc(documentId).get();
    if (existingDoc.exists) {
      DocumentReference documentReference =
          FirebaseFirestore.instance.collection('schedules').doc(documentId);
      Map<String, dynamic> updatedFields = {
        'name': name,
        'details': details,
        'days': days,
      };
      await documentReference.update(updatedFields);
    } else {
      try {
        await firestore.collection('schedules').doc(documentId).set({
          'name': name,
          'details': details,
          'days': days,
        });
      } catch (e) {
        print('Error creating schedules: $e');
      }
    }
  }

  Future<void> getSchedules(String documentId) async {
    try {
      DocumentSnapshot documentSnapshot = await FirebaseFirestore.instance
          .collection('schedules')
          .doc(documentId)
          .get();

      if (documentSnapshot.exists) {
        singleton.addScheduleList(documentSnapshot.get('name'),
            documentSnapshot.get('details'), documentSnapshot.get('days'));

        // Perform actions with the data
        print('Document ID: ${documentSnapshot.id}');
      } else {
        print('Document with ID $documentId does not exist.');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  void updateSchedulesList(String schedulesId) async {
    String documentId = await singleton.getUID();
    DocumentReference docRef = firestore.collection('users').doc(documentId);

    try {
      await docRef.update({
        'schedules': FieldValue.arrayUnion([schedulesId])
      });

      print('Field updated successfully.');
    } catch (e) {
      print('Error updating field: $e');
    }
  }

  Future<void> createPost(
      String postId,
      String userId,
      String userName,
      String profileImage,
      String title,
      String description,
      String dateCreated,
      String lastUpdated,
      int likes,
      int views,
      String video) async {
    DocumentSnapshot existingDoc =
        await firestore.collection('posts').doc(postId).get();
    if (existingDoc.exists) {
    } else {
      try {
        await firestore.collection('posts').doc(postId).set({
          'uid': userId,
          'userName': userName,
          'profileImage': profileImage,
          'title': title,
          'description': description,
          'dateCreated': dateCreated,
          'lastUpdated': lastUpdated,
          'likes': likes,
          'views': views,
        });
      } catch (e) {
        print('Error creating user: $e');
      }
    }
  }

  void deleteDocument(String collectionName, String documentId) async {
    // Reference to the Firestore document you want to delete
    DocumentReference docReference =
        FirebaseFirestore.instance.collection(collectionName).doc(documentId);

    try {
      // Use the delete method to delete the document
      await docReference.delete();
      print('Document deleted successfully.');
    } catch (e) {
      print('Error deleting document: $e');
    }
  }

  Future<void> deleteCloudList(int index, String listName) async {
    String documentId = await singleton.getUID();
    try {
      // Get a reference to the Firestore document
      DocumentReference documentReference =
          FirebaseFirestore.instance.collection('users').doc(documentId);

      // Retrieve the current list from Firestore
      DocumentSnapshot documentSnapshot = await documentReference.get();
      Map<String, dynamic> data =
          documentSnapshot.data() as Map<String, dynamic>;
      List<dynamic> list = data[listName] as List<dynamic>;
      List<String> currentList =
          list.map((dynamic item) => item.toString()).toList();

      // Remove the desired value from the list
      currentList.removeAt(index);

      // Update the document with the modified list
      await documentReference.update({listName: currentList});

      print('Value deleted from the list successfully!');
    } catch (e) {
      print('Error deleting value from the list: $e');
    }
  }
}
