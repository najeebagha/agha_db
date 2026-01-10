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
        // [UPDATED] یہاں ڈسپلے نیم بھی لوڈ کریں
        _currentUser = User(
          uid: userData['uid'],
          email: userData['email'],
          displayName: userData['displayName'],
        );
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

    // [UPDATED] لاگ ان کرتے وقت ڈسپلے نیم بھی پاس کریں
    await _signInInternal(
      email,
      userData['uid'],
      displayName: userData['displayName'],
    );

    return UserCredential(user: _currentUser!);
  }

  Future<void> signOut() async {
    await _box.delete('current_session_email');
    _currentUser = null;
    _authStateController.add(null);
  }

  // [UPDATED] ڈسپلے نیم کو سپورٹ کرنے کے لیے اپ ڈیٹ کیا گیا
  Future<void> _signInInternal(
    String email,
    String uid, {
    String? displayName,
  }) async {
    _currentUser = User(uid: uid, email: email, displayName: displayName);
    await _box.put('current_session_email', email);
    _authStateController.add(_currentUser);
  }

  // --- [NEW] پاسورڈ ریسیٹ (Forgot Password) ---

  Future<void> sendPasswordResetEmail({required String email}) async {
    if (!_box.containsKey('user_$email')) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'اس ای میل پر کوئی اکاؤنٹ موجود نہیں ہے۔',
      );
    }

    print("--- MOCK EMAIL SENT ---");
    print("To: $email");
    print("Subject: Reset your password");
    print("Body: Click here to reset your password...");
    print("-----------------------");

    await Future.delayed(Duration(seconds: 1));
  }

  // --- [NEW] پروفائل اپ ڈیٹ میتھڈز ---

  /// **[NEW] ڈسپلے نیم اپ ڈیٹ کرنے کا میتھڈ**
  Future<void> updateDisplayName(String displayName) async {
    if (_currentUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'کوئی یوزر لاگ ان نہیں ہے۔',
      );
    }

    final email = _currentUser!.email!;
    // Hive سے موجودہ ڈیٹا حاصل کریں
    final userData = Map<String, dynamic>.from(_box.get('user_$email'));

    // ڈیٹا بیس میں نام اپ ڈیٹ کریں
    userData['displayName'] = displayName;
    await _box.put('user_$email', userData);

    // موجودہ سیشن (User Object) اپ ڈیٹ کریں
    _currentUser = User(
      uid: _currentUser!.uid,
      email: _currentUser!.email,
      displayName: displayName, // نیا نام
    );

    // ایپ کو مطلع کریں کہ نام تبدیل ہو گیا ہے
    _authStateController.add(_currentUser);

    print("ڈسپلے نیم کامیابی سے اپ ڈیٹ ہو گیا: $displayName");
  }

  Future<void> updatePassword(String newPassword) async {
    if (_currentUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'کوئی یوزر لاگ ان نہیں ہے۔',
      );
    }
    final email = _currentUser!.email!;
    final userData = Map<String, dynamic>.from(_box.get('user_$email'));

    userData['password'] = newPassword;
    await _box.put('user_$email', userData);

    print("پاسورڈ کامیابی سے تبدیل ہو گیا!");
  }

  Future<void> updateEmail(String newEmail) async {
    if (_currentUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'کوئی یوزر لاگ ان نہیں ہے۔',
      );
    }
    final oldEmail = _currentUser!.email!;

    if (oldEmail == newEmail) return;

    if (_box.containsKey('user_$newEmail')) {
      throw FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'یہ ای میل کسی اور اکاؤنٹ پر استعمال ہو رہی ہے۔',
      );
    }

    final userData = Map<String, dynamic>.from(_box.get('user_$oldEmail'));

    userData['email'] = newEmail;

    await _box.put('user_$newEmail', userData);
    await _box.delete('user_$oldEmail');

    // سیشن اپ ڈیٹ کریں (پرانا ڈسپلے نیم برقرار رکھتے ہوئے)
    await _signInInternal(
      newEmail,
      userData['uid'],
      displayName: userData['displayName'],
    );

    print("ای میل کامیابی سے تبدیل ہو گئی: $newEmail");
  }

  Future<void> delete() async {
    if (_currentUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'کوئی یوزر لاگ ان نہیں ہے۔',
      );
    }
    final email = _currentUser!.email!;

    await _box.delete('user_$email');
    await signOut();

    print("اکاؤنٹ ڈیلیٹ کر دیا گیا ہے۔");
  }
}

// --- Supporting Classes (Exceptions & Models) ---

class User {
  final String uid;
  final String? email;
  final String? displayName; // [ADDED]

  User({
    required this.uid,
    this.email,
    this.displayName, // [ADDED]
  });

  // شارٹ کٹس
  Future<void> updatePassword(String newPassword) =>
      FirebaseAuth.instance.updatePassword(newPassword);

  Future<void> updateEmail(String newEmail) =>
      FirebaseAuth.instance.updateEmail(newEmail);

  Future<void> delete() => FirebaseAuth.instance.delete();

  // [ADDED] شارٹ کٹ برائے اپ ڈیٹ ڈسپلے نیم
  Future<void> updateDisplayName(String name) =>
      FirebaseAuth.instance.updateDisplayName(name);
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
  String toString() => message;
}
