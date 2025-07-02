import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'SearchIndex.dart';
import 'globals.dart';


class NoteUtils {
  static Future<void> showNoteInputModal(
      BuildContext context,
      String imagePath,
      Function(String, String) onNoteSubmitted, {
        String initialText = '',
        bool isEditing = false,
      }) async {
    final TextEditingController noteController = TextEditingController(text: initialText);
    final speech = stt.SpeechToText();
    bool _isListening = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (context, setState) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard),
                          tooltip: 'keyboardInput'.tr,
                          onPressed: () {},
                        ),
                        IconButton(
                          icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                          color: _isListening ? Colors.red : null,
                          tooltip: 'voiceInput'.tr,
                          onPressed: () async {
                            if (!_isListening) {
                              final available = await speech.initialize(
                                onStatus: (status) => debugPrint('Speech status: $status'),
                                onError: (error) => debugPrint('Speech error: $error'),
                              );

                              if (available) {
                                setState(() => _isListening = true);
                                speech.listen(
                                  onResult: (result) {
                                    if (result.finalResult) {
                                      noteController.text = result.recognizedWords;
                                    }
                                  },
                                );
                              }
                            } else {
                              speech.stop();
                              setState(() => _isListening = false);
                            }
                          },
                        ),
                        if (_isListening)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              'listening'.tr,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                    TextField(
                      controller: noteController,
                      maxLines: 5,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'typeYourNoteHere'.tr,
                        border: const OutlineInputBorder(),
                        suffixIcon: noteController.text.isNotEmpty
                            ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => noteController.clear(),
                        )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('cancel'.tr),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final note = noteController.text.trim();
                            if (note.isNotEmpty) {
                              onNoteSubmitted(imagePath, note);
                              saveNoteToFile(imagePath, note);
                              Fluttertoast.showToast(
                                msg: isEditing ? 'noteUpdated'.tr : 'noteSaved'.tr,
                                toastLength: Toast.LENGTH_SHORT,
                              );
                            }
                            Navigator.pop(context);
                          },
                          child: Text(isEditing ? 'update'.tr : 'save'.tr),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  static void saveNoteToFile(String imagePath, String note) {
    try {
      final notePath = path.withoutExtension(imagePath) + ".txt";
      File(notePath).writeAsStringSync(note);
      debugPrint('Note saved to: $notePath');
      mediaNotesNotifier.value = {
        ...mediaNotesNotifier.value,
        imagePath: note,
      };
      IndexManager.instance.updateNoteContent(imagePath, note);

    } catch (e) {
      debugPrint('Error saving note: $e');
    }
  }

  static void addOrUpdateNote(
      String imagePath,
      String noteText,
      ValueNotifier<Map<String, String>> mediaNotesNotifier,
      ) {
    mediaNotesNotifier.value = {
      ...mediaNotesNotifier.value,
      imagePath: noteText,
    };
    IndexManager.instance.updateNoteContent(imagePath, noteText);

  }

  static Future<String?> loadNoteFromFile(String imagePath) async {
    try {
      final notePath = path.withoutExtension(imagePath) + ".txt";
      final file = File(notePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint('Error loading note: $e');
    }
    return null;
  }


  static Future<void> loadAllNotes(String rootPath) async {
    Map<String, String> loadedNotes = {};

    final rootDir = Directory(rootPath);

    if (!rootDir.existsSync()) return;

    final List<FileSystemEntity> allFiles = [];

    void safeCollectFiles(Directory dir) {
      try {
        for (var entity in dir.listSync(recursive: false)) {
          if (entity is File) {
            allFiles.add(entity);
          } else if (entity is Directory) {
            safeCollectFiles(entity);
          }
        }
      } catch (e) {
        debugPrint('🚫 Skipped inaccessible folder: ${dir.path} → $e');
      }
    }

    safeCollectFiles(rootDir);

    for (final entity in allFiles) {
      if (entity.path.endsWith('.txt')) {
        try {
          final noteContent = await File(entity.path).readAsString();
          final imagePath = entity.path.replaceAll(RegExp(r'\.txt$'), '');

          loadedNotes[imagePath] = noteContent;
        } catch (e) {
          debugPrint('❌ Failed to read note from ${entity.path}: $e');
        }
      }
    }

    mediaNotesNotifier.value = loadedNotes;
    debugPrint("[DEBUG] Loaded ${loadedNotes.length} notes from disk.");
  }


  static Future<void> showNoteDialog(
      BuildContext context,
      String imagePath,
      ValueNotifier<Map<String, String>> mediaNotesNotifier,
      ) async {
    final currentNote = mediaNotesNotifier.value[imagePath] ?? await loadNoteFromFile(imagePath);
    final hasNote = currentNote != null && currentNote.isNotEmpty;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('note'.tr),
        content: Text(hasNote ? currentNote! : 'noNoteFound'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('close'.tr),
          ),
          if (hasNote)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                showNoteInputModal(
                  context,
                  imagePath,
                      (path, note) => addOrUpdateNote(path, note, mediaNotesNotifier),
                  initialText: currentNote!,
                  isEditing: true,
                );
              },
              child: Text('edit'.tr),
            ),
          TextButton(
            onPressed: () {
              mediaNotesNotifier.value = {...mediaNotesNotifier.value}..remove(imagePath);
              deleteNoteFile(imagePath);
              Fluttertoast.showToast(msg: 'noteDeleted'.tr);
              Navigator.pop(context);
            },
            child: Text(
              'delete'.tr,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  static void deleteNoteFile(String imagePath) {
    try {
      final notePath = path.withoutExtension(imagePath) + ".txt";
      File(notePath).deleteSync();
      IndexManager.instance.updateNoteContent(imagePath, null);

    } catch (e) {
      debugPrint('Error deleting note file: $e');
    }
  }
}

