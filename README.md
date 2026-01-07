# 🚀 Mock Firebase (Offline Hive-based Core)

This library provides a powerful **Mock Firebase System** for **Flutter/Dart** applications. It is entirely offline and mimics the behavior of **Firestore**, **Auth**, and **Storage** using the **Hive** database. It is designed to help developers test app logic without an internet connection or a real Firebase project.

## ✨ Key Features

- **Firestore Mock:** Supports `where` filters, `orderBy` sorting, `limit`, and `Real-time Snapshots`.
- **Auth Mock:** Email/Password sign-up, sign-in, session persistence, and password reset simulation.
- **Storage Mock:** Manages files using the local file system with `putFile` and `putData` support.
- **Pagination:** Fully functional cursor support using `startAtDocument`, `startAfterDocument`, etc.

------

## 🛠 Dependencies

To use this code, ensure you have the following packages added to your `pubspec.yaml`:

YAML

```yaml
dependencies:
  hive: ^2.2.3
  uuid: ^4.0.0
  path_provider: ^2.1.0
```

------

## 📖 How to Use

### 1. Initialization

You must initialize the services before using them:

Dart

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive boxes for Auth and Firestore
  await FirebaseFirestore.instance.init();
  await FirebaseAuth.instance.init();
}
```

------

### 2. Firestore Operations

#### Fetching Data (Queries & Filters)

Dart

```dart
final usersRef = FirebaseFirestore.instance.collection('users');

// Get data with filters and sorting
final snapshot = await usersRef
    .where('age', isGreaterThan: 18)
    .orderBy('name', descending: false)
    .limit(10)
    .get();

for (var doc in snapshot.docs) {
  print(doc.data());
}
```

#### Real-time Updates (Snapshots)

Dart

```dart
usersRef.snapshots().listen((snapshot) {
  print("Total users: ${snapshot.size}");
});
```

------

### 3. Authentication

#### Sign Up & Profile Management

Dart

```dart
final auth = FirebaseAuth.instance;

// Create a new account
await auth.createUserWithEmailAndPassword(
  email: "test@example.com", 
  password: "password123"
);

// Update Email (Automatically handles Hive key migration)
await auth.currentUser?.updateEmail("newemail@example.com");
```

------

### 4. Firebase Storage

#### Uploading Files or Bytes

Dart

```dart
final storageRef = FirebaseStorage.instance.ref("uploads/profile.png");

// Upload a file
final uploadTask = storageRef.putFile(File("path/to/image.png"));

uploadTask.snapshotEvents.listen((task) {
  print("Progress: ${task.progress}%");
  if (task.state == TaskState.success) {
    print("Upload Complete!");
  }
});
```

------

## 🏗 Class Architecture

| **Class**           | **Purpose**                                              |
| ------------------- | -------------------------------------------------------- |
| `FirebaseFirestore` | Main entry point for database operations (Singleton).    |
| `Query`             | Handles logic for filtering, sorting, and pagination.    |
| `FirebaseAuth`      | Manages user sessions, registration, and local security. |
| `FirebaseStorage`   | Simulates bucket storage using local device directories. |
| `DocumentSnapshot`  | Contains data and metadata for a specific document.      |

------

## ⚠️ Important Notes

1. **Persistence:** All data is stored locally in Hive boxes on the device.
2. **Password Reset:** The `sendPasswordResetEmail` method is a simulation; it logs the "email" content to the console instead of sending a real one.
3. **File Paths:** Storage uses `path_provider` to ensure files are saved in the correct application documents directory.

-------------

