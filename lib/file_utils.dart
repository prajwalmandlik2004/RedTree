import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'FileManager.dart';
import 'SearchIndex.dart';
import 'note_utils.dart';
import 'package:get/get.dart';

import 'globals.dart';

class FileUtils {
  static Future<void> showPopupMenu(
      BuildContext context,
      File file,
      CameraDescription camera,
      TapDownDetails? tapDetails, {
        VoidCallback? onFileChanged,
        VoidCallback? onEnterMultiSelectMode,
        VoidCallback? onFilesMoved,
      }) async {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width - 160, 60, 20,
        overlay.size.height - 60,
      ),
      items: [
        PopupMenuItem(value: 'annotate', height: 36, child: Text('annotate'.tr)),
        PopupMenuItem(value: 'open', height: 36, child: Text('open'.tr)),
        PopupMenuItem(value: 'rename', height: 36, child: Text('rename'.tr)),
        PopupMenuItem(value: 'duplicate', height: 36, child: Text('duplicate'.tr)),
        PopupMenuItem(value: 'select', height: 36, child: Text('select'.tr)),
        PopupMenuItem(value: 'move', height: 36, child: Text('moveTo'.tr)),
        PopupMenuItem(value: 'share', height: 36, child: Text('share'.tr)),
        PopupMenuItem(value: 'suppress', height: 36, child: Text('suppress'.tr)),
      ],
    );

    switch (result) {
      case 'annotate':
        NoteUtils.showNoteInputModal(
          context,
          file.path,
              (imagePath, noteText) {
            NoteUtils.addOrUpdateNote(imagePath, noteText, mediaNotesNotifier);
          },
        );
        break;

      case 'open':
        final parentDir = file.parent;
        final mediaFiles = parentDir
            .listSync()
            .whereType<File>()
            .where((f) =>
        !p.basename(f.path).startsWith('.') &&
            (f.path.endsWith('.jpg') ||
                f.path.endsWith('.jpeg') ||
                f.path.endsWith('.png') ||
                f.path.endsWith('.mp4') ||
                f.path.endsWith('.mov') ||
                f.path.endsWith('.webm') ||
                f.path.endsWith('.avi')))
            .toList();

        final index = mediaFiles.indexWhere((f) => f.path == file.path);
        if (index != -1) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenMediaViewer(
                mediaFiles: mediaFiles,
                initialIndex: index,
                camera: camera,
              ),
            ),
          );
        } else {
          Fluttertoast.showToast(msg: "File not found in media list".tr);
        }
        break;

      case 'rename':
        final oldPath = file.path;

        final renamed = await showRenameDialog(
          context,
          file,
          onMoveRequested: () async {
            Fluttertoast.showToast(
              msg: "Select destination folder".tr,
              toastLength: Toast.LENGTH_LONG,
            );

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => FileManager(
                  selectedPaths: [file.path],
                  enableFolderSelection: true,
                  onFilesMoved: () {
                      onFileChanged?.call();
                      onFilesMoved?.call();
                  }
                ),
              ),
            );
          },
        );
        if (renamed != null) {
          final newPath = file.path;
        IndexManager.instance.updateForRename(
          file.path,
          renamed.path,
          renamed is Directory,
        );
        onFileChanged?.call();}

        break;
      case 'duplicate':
        final newFile = await duplicateFile(context, file);
        if (newFile != null) {
          await IndexManager.instance.updateForDuplicate(newFile.path, newFile is Directory);
          onFileChanged?.call();
        }
        break;

      case 'select':
        onEnterMultiSelectMode?.call();
        break;
      case 'move':

        Fluttertoast.showToast(
          msg: "Select destination folder".tr,
          toastLength: Toast.LENGTH_LONG,
        );

      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => FileManager(
              selectedPaths: [file.path],
              enableFolderSelection: true,
              onFilesMoved:() {

            onFileChanged?.call();
            onFilesMoved?.call();

            }
            ),
          ),  (route) => route.isFirst,

      );


        break;
      case 'share':
        await shareFile(context, file);
        break;
      case 'suppress':
        final deleted = await deleteFile(context, file);
        if (deleted != null) {
          IndexManager.instance.updateForDelete(file.path);
          onFileChanged?.call();
        }
        break;

    }
  }




  static Future<File?> deleteFile(BuildContext context, File file) async {
    try {
      await file.delete();

      final noteFile = File('${file.path}.txt');
      if (await noteFile.exists()) {
        await noteFile.delete();
      }
      mediaNotesNotifier.value.remove(file.path);
      mediaReloadNotifier.value++;

      Fluttertoast.showToast(msg: "fileDeleted".tr);
      return file;
    } catch (_) {
      Fluttertoast.showToast(msg: "fileDeleteFailed".tr);
      return null;
    }
  }


  static Future<File?> showRenameDialog(
      BuildContext context,
      File file, {
        VoidCallback? onMoveRequested,
      }) async {
    final controller = TextEditingController(text: p.basenameWithoutExtension(file.path));
    bool moveRequested = false;
    File? renamedFile;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("rename".tr),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_, false),
            child: Text("cancel".tr),
          ),
          TextButton(
            onPressed: () {
              moveRequested = true;
              Navigator.pop(_, true);
            },
            child: Text("move".tr),
          ),
          TextButton(
            onPressed: () async {
              final newPath = p.join(
                p.dirname(file.path),
                controller.text + p.extension(file.path),
              );
              try {
                final renamed = await file.rename(newPath);
                mediaReloadNotifier.value++;
                Fluttertoast.showToast(msg: "renameSuccess".tr);
                renamedFile = renamed;
                Navigator.pop(_, true);
              } catch (_) {
                Fluttertoast.showToast(msg: "renameFailed".tr);
                Navigator.pop(context, false);
              }
            },
            child: Text("rename".tr),
          ),
        ],
      ),
    );

    if (moveRequested && confirmed == true) {
      onMoveRequested?.call();
      return null;
    }

    return renamedFile;
  }




  static Future<File?> duplicateFile(BuildContext context, File file) async {
    try {
      String baseName = p.basenameWithoutExtension(file.path);
      String extension = p.extension(file.path);
      String dir = p.dirname(file.path);
      int copyNumber = 1;
      String newPath;

      do {
        newPath = p.join(dir, "$baseName ($copyNumber)$extension");
        copyNumber++;
      } while (File(newPath).existsSync());

      final newFile = await file.copy(newPath);

      await Future.delayed(Duration(milliseconds: 300));

      mediaReloadNotifier.value++;
      await Future.delayed(Duration(milliseconds: 100));
      mediaReloadNotifier.value++;

      Fluttertoast.showToast(msg: "duplicated".tr);
      return newFile;
    } catch (e) {
      debugPrint('❌ Duplication error: $e');
      Fluttertoast.showToast(msg: "duplicationFailed".tr);
      return null;
    }
  }

  static Future<bool> moveFileTo(BuildContext context, File file, String destinationPath) async {
    try {
      if (!await file.exists()) {
        Fluttertoast.showToast(msg: "sourceFileNotFound".tr);
        return false;
      }

      final sourceDir = p.dirname(file.path);
      destinationPath = p.normalize(destinationPath);

      if (sourceDir == destinationPath) {
        Fluttertoast.showToast(msg: "fileInSameFolder".tr);
        return false;
      }

      final newPath = p.join(destinationPath, p.basename(file.path));

      try {
        if (!await Directory(destinationPath).exists()) {
          await Directory(destinationPath).create(recursive: true);
        }
      } catch (e) {
        debugPrint('Directory creation error: $e');
        Fluttertoast.showToast(msg: "cannotCreateDestination".tr);
        return false;
      }

      if (await File(newPath).exists()) {
        final shouldOverwrite = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('fileExists'.tr),
            content: Text('overwriteConfirmation'.tr),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(_, false),
                child: Text('cancel'.tr),
              ),
              TextButton(
                onPressed: () => Navigator.pop(_, true),
                child: Text('overwrite'.tr),
              ),
            ],
          ),
        );
        if (shouldOverwrite != true) return false;
      }

      try {
        await file.rename(newPath);
      } catch (e) {
        debugPrint('Rename failed, trying copy+delete: $e');
        try {
          await file.copy(newPath);
          await file.delete();
        } catch (copyError) {
          debugPrint('Copy failed: $copyError');
          if (await File(newPath).exists()) {
            try {
              await File(newPath).delete();
            } catch (cleanupError) {
              debugPrint('Cleanup failed: $cleanupError');
            }
          }
          rethrow;
        }
      }

      final notePath = p.withoutExtension(file.path) + '.txt';
      if (await File(notePath).exists()) {
        try {
          final newNotePath = p.withoutExtension(newPath) + '.txt';
          await File(notePath).rename(newNotePath);

          final noteContent = mediaNotesNotifier.value[file.path] ?? '';

          mediaNotesNotifier.value = {
            ...mediaNotesNotifier.value,
            newPath: noteContent,
          };
          mediaNotesNotifier.value.remove(file.path);

          IndexManager.instance.updateNoteContent(newPath, noteContent);
        } catch (noteError) {
          debugPrint('Note move failed: $noteError');
        }
      }


      mediaReloadNotifier.value++;
      Fluttertoast.showToast(msg: "fileMoved".tr);

      return true;
    } catch (e) {
      debugPrint('Move error: $e');
      Fluttertoast.showToast(msg: "fileMoveFailed");
      return false;
    }
  }


  static Future<bool> shareFile(BuildContext context, File file) async {
    try {
      if (!file.existsSync()) {
        Fluttertoast.showToast(msg: "fileNotFound".tr);
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${p.basename(file.path)}'; // ✅ Fixed
      final tempFile = await file.copy(tempPath);

      await Share.shareXFiles([XFile(tempFile.path)], text: 'shareMessage'.tr);
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: "shareError ${e.toString()}");
      print("shareError $e");
      return false;
    }
  }


  static void openFullScreen(BuildContext context, File file, List<File> mediaFiles) {
    final initialIndex = mediaFiles.indexOf(file);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenMediaViewer(
          mediaFiles: mediaFiles,
          initialIndex: initialIndex,
        ),
      ),
    );
  }


  static Future<bool> isFolderAccessible(String folderPath) async {
    try {
      if (folderPath.isEmpty) return false;
      final directory = Directory(folderPath);
      return await directory.exists();
    } catch (e) {
      return false;
    }
  }

  static void showFolderMovedSnackBar(BuildContext context, String folderPath) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Folder path "$folderPath" has been moved. Please define a new path.'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'SET PATH',
          onPressed: () {

          },
        ),
      ),
    );
  }
}






