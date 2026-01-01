import 'dart:io';
import 'dart:async';
import 'dart:typed_data'; // Uint8List کے لیے ضروری
import 'package:path_provider/path_provider.dart';

/// **FirebaseStorage (لوکل ورژن):**
class FirebaseStorage {
  static FirebaseStorage get instance => FirebaseStorage();
  String get bucket => "local-storage-bucket";

  Reference ref([String? path]) {
    return Reference(path ?? "", isRoot: path == null || path.isEmpty);
  }
}

class Reference {
  final String _path;
  final bool _isRoot;

  Reference(this._path, {bool isRoot = false}) : _isRoot = isRoot;

  String get name => _path.split('/').last;
  String get fullPath => _path;

  Future<String> _getBasePath() async {
    if (_isRoot) {
      final directory = await getApplicationDocumentsDirectory();
      return directory.path;
    } else {
      return Directory.current.path;
    }
  }

  Reference child(String path) {
    String newPath = _path.isEmpty ? path : "$_path/$path";
    return Reference(newPath, isRoot: _isRoot);
  }

  /// **[putFile]**: فائل اپ لوڈ کرنے کے لیے
  UploadTask putFile(File file) {
    final controller = StreamController<TaskSnapshot>();
    _handleUpload(controller, file: file);
    return UploadTask(controller.stream);
  }

  /// **[NEW] [putData]**: بائٹس (Uint8List) اپ لوڈ کرنے کے لیے
  UploadTask putData(Uint8List data) {
    final controller = StreamController<TaskSnapshot>();
    _handleUpload(controller, data: data);
    return UploadTask(controller.stream);
  }

  /// مشترکہ ہینڈلر جو فائل یا بائٹس دونوں کو سنبھالتا ہے
  Future<void> _handleUpload(
    StreamController<TaskSnapshot> controller, {
    File? file,
    Uint8List? data,
  }) async {
    try {
      final basePath = await _getBasePath();
      final targetPath = _path.isEmpty ? basePath : "$basePath/$_path";
      final targetFile = File(targetPath);

      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }

      int totalBytes = file != null ? await file.length() : data!.length;
      int bytesTransferred = 0;

      // آؤٹ پٹ سنک کھولیں
      final outputSink = targetFile.openWrite();

      if (file != null) {
        // فائل کو ٹکڑوں میں پڑھنا
        final inputStream = file.openRead();
        await for (var chunk in inputStream) {
          outputSink.add(chunk);
          bytesTransferred += chunk.length;
          _updateProgress(controller, bytesTransferred, totalBytes);
        }
      } else if (data != null) {
        // بائٹس کو ایک ساتھ یا ٹکڑوں میں لکھنا (یہاں سادگی کے لیے ایک ساتھ لکھا ہے)
        outputSink.add(data);
        bytesTransferred = totalBytes;
        _updateProgress(controller, bytesTransferred, totalBytes);
      }

      await outputSink.close();
      controller.add(
        TaskSnapshot(
          bytesTransferred: totalBytes,
          totalBytes: totalBytes,
          state: TaskState.success,
        ),
      );
      await controller.close();
    } catch (e) {
      controller.addError(e);
      await controller.close();
    }
  }

  void _updateProgress(
    StreamController<TaskSnapshot> controller,
    int transferred,
    int total,
  ) {
    controller.add(
      TaskSnapshot(
        bytesTransferred: transferred,
        totalBytes: total,
        state: TaskState.running,
      ),
    );
  }

  Future<String> getDownloadURL() async {
    final basePath = await _getBasePath();
    return _path.isEmpty ? basePath : "$basePath/$_path";
  }

  Future<void> delete() async {
    final basePath = await _getBasePath();
    final file = File(_path.isEmpty ? basePath : "$basePath/$_path");
    if (await file.exists()) await file.delete();
  }
}

// --- سپورٹنگ کلاسز (پہلے جیسی ہی ہیں) ---
enum TaskState { running, success, error }

class TaskSnapshot {
  final int bytesTransferred;
  final int totalBytes;
  final TaskState state;

  TaskSnapshot({
    required this.bytesTransferred,
    required this.totalBytes,
    required this.state,
  });
  double get progress =>
      totalBytes == 0 ? 0 : (bytesTransferred / totalBytes) * 100;
}

class UploadTask {
  final Stream<TaskSnapshot> snapshotEvents;
  UploadTask(this.snapshotEvents);
  Future<TaskSnapshot> get lastSnapshot => snapshotEvents.last;
}
