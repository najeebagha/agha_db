import 'dart:async';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class FirebaseAuth {
  static final FirebaseAuth instance = FirebaseAuth._();

  final String _boxName = 'firebase_auth_store';

  FirebaseAuth._();

  Future<void> init({String? storagePath}) async {
    String path;

    // اگر پاتھ دیا گیا ہے (ونڈوز کے لیے)
    if (storagePath != null) {
      path = storagePath;
    } else {
      // اگر پاتھ نہیں دیا گیا تو اینڈرائیڈ کے لیے ڈیفالٹ ڈائریکٹری حاصل کریں
      final directory = await getApplicationDocumentsDirectory();
      path = directory.path;
    }

    // Hive کو اس مخصوص پاتھ پر انیشلائز کریں
    Hive.init(path);

    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }

    _recoverSession();
  }

  User? _currentUser;
  final StreamController<User?> _authStateController =
      StreamController<User?>.broadcast();

  User? get currentUser => _currentUser;
  Stream<User?> authStateChanges() => _authStateController.stream;
  Box get _box => Hive.box(_boxName);

  void _recoverSession() {
    final sessionEmail = _box.get('current_session_email');
    if (sessionEmail != null) {
      final userData = _box.get('user_$sessionEmail');
      if (userData != null) {
        _currentUser = User(uid: userData['uid'], email: userData['email']);
        _authStateController.add(_currentUser);
      }
    } else {
      _authStateController.add(null);
    }
  }

  // --- سائن ان / سائن اپ (پرانے میتھڈز) ---

  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (_box.containsKey('user_$email')) {
      throw FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'یہ ای میل پہلے سے رجسٹرڈ ہے۔',
      );
    }
    final uid = const Uuid().v4();
    final userData = {'uid': uid, 'email': email, 'password': password};
    await _box.put('user_$email', userData);
    await _signInInternal(email, uid);
    return UserCredential(user: _currentUser!);
  }

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final userData = _box.get('user_$email');
    if (userData == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'کوئی یوزر اس ای میل کے ساتھ نہیں ملا۔',
      );
    }
    if (userData['password'] != password) {
      throw FirebaseAuthException(
        code: 'wrong-password',
        message: 'پاسورڈ غلط ہے۔',
      );
    }
    await _signInInternal(email, userData['uid']);
    return UserCredential(user: _currentUser!);
  }

  Future<void> signOut() async {
    await _box.delete('current_session_email');
    _currentUser = null;
    _authStateController.add(null);
  }

  Future<void> _signInInternal(String email, String uid) async {
    _currentUser = User(uid: uid, email: email);
    await _box.put('current_session_email', email);
    _authStateController.add(_currentUser);
  }

  // --- [NEW] پاسورڈ ریسیٹ (Forgot Password) ---

  /// پاسورڈ ریسیٹ ای میل بھیجنے کی نقل (Simulation)
  Future<void> sendPasswordResetEmail({required String email}) async {
    // 1. چیک کریں کہ یوزر موجود ہے یا نہیں
    if (!_box.containsKey('user_$email')) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'اس ای میل پر کوئی اکاؤنٹ موجود نہیں ہے۔',
      );
    }

    // 2. چونکہ یہ آف لائن ہے، ہم ای میل نہیں بھیج سکتے، بس لاگ پرنٹ کریں گے
    print("--- MOCK EMAIL SENT ---");
    print("To: $email");
    print("Subject: Reset your password");
    print("Body: Click here to reset your password...");
    print("-----------------------");

    // اصلی ایپ میں یہاں نیٹ ورک کال ہوتی ہے
    await Future.delayed(Duration(seconds: 1)); // تھوڑا انتظار تاکہ اصلی لگے
  }

  // --- [NEW] پروفائل اپ ڈیٹ میتھڈز ---

  /// موجودہ یوزر کا پاسورڈ تبدیل کریں
  Future<void> updatePassword(String newPassword) async {
    if (_currentUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'کوئی یوزر لاگ ان نہیں ہے۔',
      );
    }
    final email = _currentUser!.email!;
    final userData = Map<String, dynamic>.from(_box.get('user_$email'));

    // نیا پاسورڈ سیٹ کریں
    userData['password'] = newPassword;
    await _box.put('user_$email', userData);

    print("پاسورڈ کامیابی سے تبدیل ہو گیا!");
  }

  /// موجودہ یوزر کا ای میل تبدیل کریں
  Future<void> updateEmail(String newEmail) async {
    if (_currentUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'کوئی یوزر لاگ ان نہیں ہے۔',
      );
    }
    final oldEmail = _currentUser!.email!;

    if (oldEmail == newEmail) return; // اگر ای میل وہی ہے تو کچھ نہ کریں

    // چیک کریں کہ نیا ای میل پہلے سے کسی اور کا تو نہیں
    if (_box.containsKey('user_$newEmail')) {
      throw FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'یہ ای میل کسی اور اکاؤنٹ پر استعمال ہو رہی ہے۔',
      );
    }

    // پرانا ڈیٹا حاصل کریں
    final userData = Map<String, dynamic>.from(_box.get('user_$oldEmail'));

    // ڈیٹا میں ای میل اپ ڈیٹ کریں
    userData['email'] = newEmail;

    // 1. نئے ای میل (Key) کے ساتھ ڈیٹا محفوظ کریں
    await _box.put('user_$newEmail', userData);

    // 2. پرانا ای میل (Key) ڈیلیٹ کریں
    await _box.delete('user_$oldEmail');

    // 3. سیشن اپ ڈیٹ کریں
    await _signInInternal(newEmail, userData['uid']);

    print("ای میل کامیابی سے تبدیل ہو گئی: $newEmail");
  }

  /// موجودہ یوزر کا اکاؤنٹ ڈیلیٹ کریں
  Future<void> delete() async {
    if (_currentUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'کوئی یوزر لاگ ان نہیں ہے۔',
      );
    }
    final email = _currentUser!.email!;

    // ڈیٹا بیس سے یوزر ہٹائیں
    await _box.delete('user_$email');

    // سائن آؤٹ کریں
    await signOut();

    print("اکاؤنٹ ڈیلیٹ کر دیا گیا ہے۔");
  }
}

// --- Supporting Classes (Exceptions & Models) ---

class User {
  final String uid;
  final String? email;
  User({required this.uid, this.email});

  // یوزر کے اپنے میتھڈز کو شارٹ کٹ کے طور پر کال کرنے کے لیے
  Future<void> updatePassword(String newPassword) =>
      FirebaseAuth.instance.updatePassword(newPassword);
  Future<void> updateEmail(String newEmail) =>
      FirebaseAuth.instance.updateEmail(newEmail);
  Future<void> delete() => FirebaseAuth.instance.delete();
}

class UserCredential {
  final User user;
  UserCredential({required this.user});
}

class FirebaseAuthException implements Exception {
  final String code;
  final String message;
  FirebaseAuthException({required this.code, required this.message});
  @override
  String toString() => message; // UI میں سیدھا میسج دکھانے کے لیے
}
