import 'dart:io';

import 'package:agha_db/agha_db.dart';

void main() async {
  // await Hive.initFlutter(); // Init For Flutter apps
  await FirebaseFirestore.instance.init();

  var usersRef1 = FirebaseFirestore.instance.collection('users');

  await usersRef1.doc('user123').set({
    'name': 'agha',
    'age': 33,
    'email': 'noormoh3@gmail.com',
  });

  var querySnapshot = await usersRef1.where('age', isGreaterThan: 30).get();

  for (var doc in querySnapshot.docs) {
    print("User: id ${doc.id}${doc.data()}");
  }

  // --- Realtime Listen ---
  usersRef1.snapshots().listen((snapshot) {
    print("Database changed! New count: ${snapshot.docs.length}");
  });

  //For Storage Refrence Upload File

  File image = File("path_to_your_image.jpg");

  await FirebaseStorage.instance
      .ref()
      .child("uploads")
      .child("profile.jpg")
      .putFile(image);

  await FirebaseStorage.instance
      .ref()
      .child("uploads")
      .child("profile.png")
      .getDownloadURL();
}
