import 'dart:io';
import 'package:agha_db/agha_db.dart';
import 'package:agha_db/src/auth.dart';

void main() async {
  // 1. ڈیٹا بیس کو شروع (Initialize) کریں
  final firestore = FirebaseFirestore.instance;
  await firestore.init(storagePath: "./my_local_db");

  print("--- Firestore Example ---");

  // 2. ڈیٹا شامل کرنا (Add Data)
  final productRef = firestore.collection('products');

  await productRef.doc("laptop_001").set({
    "productName": "Apple laptop",
    "price": 27000,
    "category": "ELECTRONICS",
  });

  await productRef.doc("shampoo_002").set({
    "productName": "Bio amla Shampoo",
    "price": 340,
    "category": "COSMETICS",
  });

  // 3. Query اور Cursors کا استعمال (startAt / limit)
  print("\nقیمت کے حساب سے ترتیب اور فلٹر:");
  final querySnapshot = await productRef
      .orderBy("price")
      .startAt([340]) // 340 سے شروع کریں
      .limit(2) // صرف 2 پروڈکٹس دکھائیں
      .get();

  for (var doc in querySnapshot.docs) {
    print("نام: ${doc.get('productName')}, قیمت: ${doc.get('price')}");
  }

  print("\n--- Storage Example ---");

  // 4. فائل اپ لوڈنگ اور پراگریس (Firebase Storage)
  final storage = FirebaseStorage.instance;
  File myFile = File("./test_image.jpg"); // یقینی بنائیں کہ یہ فائل موجود ہو

  if (await myFile.exists()) {
    print("فائل اپ لوڈ ہو رہی ہے...");

    final uploadTask = storage.ref("uploads/profile.jpg").putFile(myFile);

    // اپ لوڈ پراگریس سنیں
    uploadTask.snapshotEvents.listen((snapshot) {
      double percent = snapshot.progress;
      print("پراگریس: ${percent.toStringAsFixed(2)}%");

      if (snapshot.state == TaskState.success) {
        print("اپ لوڈ مکمل ہو گیا!");
      }
    });

    // ڈاؤن لوڈ URL (لوکل پاتھ) حاصل کریں
    String localUrl = await storage.ref("uploads/profile.jpg").getDownloadURL();
    print("لوکل اسٹوریج پاتھ: $localUrl");
  } else {
    print("ٹیسٹ فائل './test_image.jpg' نہیں ملی۔");
  }

  auth() async {
    await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: 'noormoh3@gmail.com',
      password: '123123',
    );

    FirebaseAuth.instance.signOut();
    FirebaseAuth.instance.delete();
    await FirebaseAuth.instance.sendPasswordResetEmail(
      email: 'noormoh3@gmail.com',
    );
  }
}
