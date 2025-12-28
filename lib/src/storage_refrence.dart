import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

/// **FirebaseStorage (لوکل ورژن):**
class FirebaseStorage {
  static FirebaseStorage get instance => FirebaseStorage();
  String get bucket => "local-storage-bucket";

  // یہاں ہم چیک کریں گے کہ آیا پاتھ پاس کیا گیا ہے یا نہیں
  Reference ref([String? path]) {
    return Reference(path ?? "", isRoot: path == null || path.isEmpty);
  }
}

class Reference {
  final String _path;
  final bool _isRoot; // یہ چیک کرنے کے لیے کہ پاتھ پاس ہوا ہے یا نہیں

  Reference(this._path, {bool isRoot = false}) : _isRoot = isRoot;

  String get name => _path.split('/').last;
  String get fullPath => _path;

  /// پاتھ کی لاجک:
  /// اگر پاتھ خالی ہے (Root) تو ApplicationDocumentsDirectory
  /// اگر پاتھ دیا گیا ہے تو Directory.current (موجودہ پروجیکٹ ڈائریکٹری)
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
    // چائلڈ بناتے وقت ہم وہی روٹ سٹیٹس برقرار رکھیں گے
    return Reference(newPath, isRoot: _isRoot);
  }

  UploadTask putFile(File file) {
    final controller = StreamController<TaskSnapshot>();
    _startUpload(file, controller);
    return UploadTask(controller.stream);
  }

  Future<void> _startUpload(
    File file,
    StreamController<TaskSnapshot> controller,
  ) async {
    try {
      final basePath = await _getBasePath();
      // اگر روٹ ہے تو پاتھ وہی ہوگا، ورنہ بیس پاتھ کے ساتھ جوڑا جائے گا
      final targetPath = _path.isEmpty ? basePath : "$basePath/$_path";
      final targetFile = File(targetPath);

      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }

      int totalBytes = await file.length();
      final inputStream = file.openRead();
      final outputSink = targetFile.openWrite();

      int bytesTransferred = 0;

      await for (var chunk in inputStream) {
        outputSink.add(chunk);
        bytesTransferred += chunk.length;

        controller.add(
          TaskSnapshot(
            bytesTransferred: bytesTransferred,
            totalBytes: totalBytes,
            state: TaskState.running,
          ),
        );
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
