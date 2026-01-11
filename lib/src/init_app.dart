import 'dart:async';
import '../agha_db.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

// --- Firebase Core Mocks ---

class Firebase {
  /// [isAuthOnly] اگر ٹرو ہوگا تو صرف آتھنٹیکیشن انیشیلائز ہوگی
  /// اگر فالس ہوگا تو ڈیٹا بیس (Firestore) بھی انیشیلائز ہوگا
  static Future<FirebaseApp> initializeApp({
    String? name,
    FirebaseOptions? options,
    bool isAuthOnly = false,
  }) async {
    if (isAuthOnly) {
      // یہاں صرف Auth سے متعلقہ انیشیلائزیشن کریں
      await FirebaseAuth.instance.init();
    } else {
      // یہاں Auth اور Firestore دونوں کو انیشیلائز کریں
      await FirebaseAuth.instance.init();
      await FirebaseFirestore.instance.init();
    }

    return FirebaseApp(
      name: name ?? '[DEFAULT]',
      options: options ?? const FirebaseOptions(),
    );
  }
}

class FirebaseApp {
  final String name;
  final FirebaseOptions options;
  FirebaseApp({required this.name, required this.options});
}

class FirebaseOptions {
  final String projectId;
  const FirebaseOptions({this.projectId = 'mock-project-id'});
}

// --- FirebaseAuth Mock (Simple) ---
