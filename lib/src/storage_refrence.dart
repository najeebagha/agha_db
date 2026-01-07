import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb; // ویب چیک کرنے کے لیے
import 'package:path_provider/path_provider.dart';

/// **FirebaseStorage (Mock Version - Dynamic Path)**
class FirebaseStorage {
  // Singleton Instance
  static final FirebaseStorage _instance = FirebaseStorage._internal();
  static FirebaseStorage get instance => _instance;

  FirebaseStorage._internal();

  String get bucket => "local-storage-bucket";

  Reference ref([String? path]) {
    return Reference(path ?? "");
  }
}

class Reference {
  final String _path; // فائر بیس کا پاتھ (جیسے: images/product.jpg)

  Reference(this._path);

  String get name => _path.split('/').last;
  String get fullPath => _path;

  /// **[پاتھ لاجک]**: یہ فنکشن سسٹم کے حساب سے صحیح فولڈر بتائے گا
  Future<String> _getLocalSystemPath() async {
    String rootPath;

    if (Platform.isWindows) {
      // ونڈوز کے لیے آپ کا کسٹم پاتھ
      // 'r' کا مطلب ہے raw string تاکہ backslashes (\) مسئلہ نہ کریں
      rootPath = r"F:\My____Flutter\Images_Show\products images";
    } else {
      // اینڈرائیڈ یا آئی او ایس کے لیے ایپ کا ڈاکیومنٹ فولڈر
      final directory = await getApplicationDocumentsDirectory();
      rootPath = directory.path;
    }

    // پاتھ کے سلیشز کو سسٹم کے مطابق درست کرنا
    String normalizedRelativePath = _path.replaceAll(
      '/',
      Platform.pathSeparator,
    );

    // اگر _path خالی ہے تو روٹ دیں، ورنہ مکمل پاتھ
    return _path.isEmpty
        ? rootPath
        : "$rootPath${Platform.pathSeparator}$normalizedRelativePath";
  }

  Reference child(String path) {
    String newPath = _path.isEmpty ? path : "$_path/$path";
    return Reference(newPath);
  }

  /// **[putFile]**: فائل محفوظ کریں
  UploadTask putFile(File file) {
    final controller = StreamController<TaskSnapshot>();
    _handleUpload(controller, file: file);
    return UploadTask(controller.stream);
  }

  /// **[putData]**: بائٹس (Uint8List) محفوظ کریں
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) {
    final controller = StreamController<TaskSnapshot>();
    _handleUpload(controller, data: data);
    return UploadTask(controller.stream);
  }

  /// **[Main Upload Logic]**
  Future<void> _handleUpload(
    StreamController<TaskSnapshot> controller, {
    File? file,
    Uint8List? data,
  }) async {
    try {
      // 1. مکمل پاتھ حاصل کریں
      final fullPath = await _getLocalSystemPath();
      final targetFile = File(fullPath);

      // 2. اگر فولڈر نہیں بنا ہوا تو بنائیں (Recursive)
      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }

      int totalBytes = file != null ? await file.length() : data!.length;
      int bytesTransferred = 0;

      // 3. ڈیٹا لکھنا شروع کریں
      final outputSink = targetFile.openWrite();

      if (file != null) {
        // فائل سے پڑھ کر لکھیں (سٹریم)
        final inputStream = file.openRead();
        await for (var chunk in inputStream) {
          outputSink.add(chunk);
          bytesTransferred += chunk.length;
          _updateProgress(controller, bytesTransferred, totalBytes);
        }
      } else if (data != null) {
        // براہ راست بائٹس لکھیں
        outputSink.add(data);
        bytesTransferred = totalBytes;
        _updateProgress(controller, bytesTransferred, totalBytes);
      }

      await outputSink.close();

      // 4. کامیابی کا پیغام بھیجیں
      controller.add(
        TaskSnapshot(
          bytesTransferred: totalBytes,
          totalBytes: totalBytes,
          state: TaskState.success,
        ),
      );
      await controller.close();
    } catch (e) {
      print("Upload Error: $e"); // ڈیبگنگ کے لیے
      controller.addError(e);
      await controller.close();
    }
  }

  void _updateProgress(
    StreamController<TaskSnapshot> controller,
    int transferred,
    int total,
  ) {
    if (!controller.isClosed) {
      controller.add(
        TaskSnapshot(
          bytesTransferred: transferred,
          totalBytes: total,
          state: TaskState.running,
        ),
      );
    }
  }

  /// **[getDownloadURL]**: یہ آپ کو لوکل پاتھ دے گا جسے آپ Image.file میں استعمال کریں
  Future<String> getDownloadURL() async {
    return await _getLocalSystemPath();
  }

  Future<void> delete() async {
    final fullPath = await _getLocalSystemPath();
    final file = File(fullPath);
    if (await file.exists()) await file.delete();
  }
}

// --- Supporting Classes ---

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

  // Future that completes when the upload is done
  Future<TaskSnapshot> get lastSnapshot => snapshotEvents.last;

  // Stream to listen to progress
  Stream<TaskSnapshot> get onStateChanged => snapshotEvents;
}

class SettableMetadata {
  final String? contentType;
  final Map<String, String>? customMetadata;

  SettableMetadata({this.contentType, this.customMetadata});
}
