import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// **Example:**
/// ```dart
/// void uploadData() async {
///  File image = File("path_to_your_image.jpg");
///
///  await FirebaseStorage.instance
///      .ref()
///      .child("uploads")
///      .child("profile.png")
///      .putFile(image);
///
///  String path = await FirebaseStorage.instance
///      .ref()
///      .child("uploads")
///      .child("profile.png")
///      .getDownloadURL();
///
///  print("د لوکل فائل پته: $path");
/// }
///
///
///
/// ```

class FirebaseStorage {
  static FirebaseStorage get instance => FirebaseStorage();

  String get bucket => "local-storage-bucket";

  Reference ref([String? path]) => Reference(path ?? "");
}

class Reference {
  final String _path;

  Reference(this._path);

  String get name => _path.split('/').last;
  String get fullPath => _path;
  String get bucket => "local-storage-bucket";

  Reference? get parent {
    List<String> parts = _path.split('/');
    if (parts.length <= 1) return null;
    parts.removeLast();
    return Reference(parts.join('/'));
  }

  Reference get root => Reference("");

  Reference child(String path) {
    String newPath = _path.isEmpty ? path : "$_path/$path";
    return Reference(newPath);
  }

  // Upload file to local directory
  Future<void> putFile(File file) async {
    final directory = await getApplicationDocumentsDirectory();
    final targetPath = "${directory.path}/$_path";
    final targetFile = File(targetPath);

    if (!await targetFile.parent.exists()) {
      await targetFile.parent.create(recursive: true);
    }
    await file.copy(targetPath);
  }

  // Get local file path
  Future<String> getDownloadURL() async {
    final directory = await getApplicationDocumentsDirectory();
    return "${directory.path}/$_path";
  }

  // Delete the local file or directory
  Future<void> delete() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File("${directory.path}/$_path");
    if (await file.exists()) {
      await file.delete();
    }
  }

  // List all files and folders in the current directory
  Future<ListResult> listAll() async {
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory("${directory.path}/$_path");

    List<Reference> items = [];
    List<Reference> prefixes = [];

    if (await folder.exists()) {
      final entities = await folder.list().toList();
      for (var entity in entities) {
        // Extract relative path to create new Reference
        String relativePath = entity.path.replaceFirst(
          "${directory.path}/",
          "",
        );
        if (entity is File) {
          items.add(Reference(relativePath));
        } else if (entity is Directory) {
          prefixes.add(Reference(relativePath));
        }
      }
    }
    return ListResult(items: items, prefixes: prefixes);
  }

  // Get metadata of the file
  Future<FullMetadata> getMetadata() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File("${directory.path}/$_path");

    if (await file.exists()) {
      return FullMetadata(
        name: name,
        size: await file.length(),
        updated: await file.lastModified(),
      );
    }
    throw Exception("File does not exist");
  }
}

// Helper class for List results
class ListResult {
  final List<Reference> items; // Files
  final List<Reference> prefixes; // Folders

  ListResult({required this.items, required this.prefixes});
}

// Helper class for Metadata
class FullMetadata {
  final String name;
  final int size;
  final DateTime updated;

  FullMetadata({required this.name, required this.size, required this.updated});
}
