import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;

import 'globals.dart';

/// Indexed entry model
class IndexedEntry {
  final String path;
  final String name;
  final String parentPath;
  final bool isFolder;
  final String? noteContent; // 🆕 Add this


  IndexedEntry({
    required this.path,
    required this.name,
    required this.parentPath,
    required this.isFolder,
    this.noteContent,

  });

  IndexedEntry copyWith({
    String? path,
    String? name,
    String? parentPath,
    bool? isFolder,
    String? noteContent,

  }) {
    return IndexedEntry(
      path: path ?? this.path,
      name: name ?? this.name,
      parentPath: parentPath ?? this.parentPath,
      isFolder: isFolder ?? this.isFolder,
      noteContent: noteContent ?? this.noteContent,

    );
  }
}

class IndexManager {
  /// Singleton instance
  static final IndexManager instance = IndexManager._internal();
  IndexManager._internal();

  /// Main in-memory index
  final List<IndexedEntry> _allIndexedEntries = [];

  List<IndexedEntry> get all => List.unmodifiable(_allIndexedEntries);

  /// Whether the index is ready
  bool isIndexing = false;

  /// Indexes everything recursively under rootPath
  Future<void> indexFileSystemRecursively(String rootPath) async {
    _allIndexedEntries.clear();
    isIndexing = true;

    int folderCount = 0;
    int fileCount = 0;

    Future<void> scan(String dirPath) async {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;

      try {
        final entities = dir.listSync();

        for (final entity in entities) {
          final path = entity.path;

          if (_shouldSkipPath(path)) continue;

          final name = p.basename(path);
          final parent = p.dirname(path);
          final isFolder = entity is Directory;
          final notePath = p.withoutExtension(path) + ".txt";
          String? note;
          if (await File(notePath).exists()) {
            note = await File(notePath).readAsString();
          }

          _allIndexedEntries.add(IndexedEntry(
            path: path,
            name: name,
            parentPath: parent,
            isFolder: isFolder,
            noteContent: note,

          ));

          if (isFolder) {
            folderCount++;
            print("📁 Folder [$folderCount]: $path");
            await scan(path);
          } else {
            fileCount++;
            if (fileCount % 100 == 0) {
              print("📄 Indexed $fileCount files so far...");
            }
          }
        }
      } catch (e) {
        print("❌ Skipping inaccessible directory: $dirPath");
        print("   Reason: $e");
      }
    }

    print("🔍 Starting recursive scan at: $rootPath");
    final stopwatch = Stopwatch()..start();
    await scan(rootPath);
    stopwatch.stop();
    isIndexing = false;
    print("✅ Indexing complete. ${_allIndexedEntries.length} entries "
        "($folderCount folders, $fileCount files) in ${stopwatch.elapsed.inSeconds}s.");
    // After indexing complete
    mediaNotesNotifier.value = {
      for (final entry in _allIndexedEntries)
        if (entry.noteContent != null && !entry.isFolder) entry.path: entry.noteContent!
    };

  }

  /// Filters the index for matching entries
  List<IndexedEntry> search(String query) {
    final lower = query.toLowerCase();

    return _allIndexedEntries.where((entry) {
      final isTxt = p.extension(entry.path).toLowerCase() == '.txt';

      // ✅ Allow match by note content but don't return .txt files
      final matches = entry.name.toLowerCase().contains(lower) ||
          (entry.noteContent?.toLowerCase().contains(lower) ?? false);

      return matches && !isTxt;
    }).toList();
  }

  /// Updates index after a rename/move
  // Future<void> updateForRename(String oldPath, String newPath, bool isFolder) async {
  //   oldPath = p.normalize(oldPath);
  //   newPath = p.normalize(newPath);
  //
  //   if (oldPath == newPath) return;
  //
  //   final index = _allIndexedEntries.indexWhere((e) => e.path == oldPath);
  //   if (index == -1) return;
  //
  //   final oldEntry = _allIndexedEntries[index];
  //   final newEntry = oldEntry.copyWith(
  //     path: newPath,
  //     name: p.basename(newPath),
  //     parentPath: p.dirname(newPath),
  //   );
  //   _allIndexedEntries[index] = newEntry;
  //
  //   if (isFolder) {
  //     final children = _allIndexedEntries.where((e) => e.path.startsWith('$oldPath/')).toList();
  //
  //     for (final child in children) {
  //       final relative = child.path.substring(oldPath.length);
  //       final updatedPath = '$newPath$relative';
  //       final i = _allIndexedEntries.indexOf(child);
  //
  //       _allIndexedEntries[i] = child.copyWith(
  //         path: updatedPath,
  //         parentPath: p.dirname(updatedPath),
  //       );
  //     }
  //   }
  // }


  Future<void> updateForRename(String oldPath, String newPath, bool isFolder) async {
    oldPath = p.normalize(oldPath);
    newPath = p.normalize(newPath);

    if (oldPath == newPath) return;

    final index = _allIndexedEntries.indexWhere((e) => e.path == oldPath);
    if (index == -1) return;

    final oldEntry = _allIndexedEntries[index];
    final note = oldEntry.noteContent;

    final newEntry = oldEntry.copyWith(
      path: newPath,
      name: p.basename(newPath),
      parentPath: p.dirname(newPath),
      noteContent: note,
    );
    _allIndexedEntries[index] = newEntry;

    if (mediaNotesNotifier.value.containsKey(oldPath)) {
      mediaNotesNotifier.value = {
        ...mediaNotesNotifier.value,
        newPath: mediaNotesNotifier.value[oldPath]!,
      }..remove(oldPath);
    }

    if (isFolder) {
      final children = _allIndexedEntries.where((e) => e.path.startsWith('$oldPath/')).toList();

      for (final child in children) {
        final relative = child.path.substring(oldPath.length);
        final updatedPath = '$newPath$relative';
        final i = _allIndexedEntries.indexOf(child);

        _allIndexedEntries[i] = child.copyWith(
          path: updatedPath,
          parentPath: p.dirname(updatedPath),
        );

        if (mediaNotesNotifier.value.containsKey(child.path)) {
          mediaNotesNotifier.value = {
            ...mediaNotesNotifier.value,
            updatedPath: mediaNotesNotifier.value[child.path]!,
          }..remove(child.path);
        }
      }
    }
  }


  Future<void> updateForFolderRename(String oldFolderPath, String newFolderPath) async {
    oldFolderPath = p.normalize(oldFolderPath);
    newFolderPath = p.normalize(newFolderPath);

    if (oldFolderPath == newFolderPath) return;

    final oldDir = Directory(oldFolderPath);
    if (!await oldDir.exists()) {
      debugPrint("❌ Folder does not exist on disk: $oldFolderPath");
      return;
    }

    try {
      await oldDir.rename(newFolderPath); // ✅ Physically rename folder
    } catch (e) {
      debugPrint("❌ Failed to rename folder on disk: $e");
      return;
    }

    // Update the renamed folder's own entry
    final index = _allIndexedEntries.indexWhere((e) => e.path == oldFolderPath && e.isFolder);
    if (index != -1) {
      final oldEntry = _allIndexedEntries[index];
      _allIndexedEntries[index] = oldEntry.copyWith(
        path: newFolderPath,
        name: p.basename(newFolderPath),
        parentPath: p.dirname(newFolderPath),
      );
    }

    // Update all children of that folder
    final children = _allIndexedEntries
        .where((e) => e.path.startsWith('$oldFolderPath/'))
        .toList();

    for (final child in children) {
      final relative = child.path.substring(oldFolderPath.length);
      final updatedPath = '$newFolderPath$relative';
      final i = _allIndexedEntries.indexOf(child);

      _allIndexedEntries[i] = child.copyWith(
        path: updatedPath,
        parentPath: p.dirname(updatedPath),
        name: p.basename(updatedPath),
      );
    }

    // ✅ Force a UI update (e.g. reload TreeView or setState)
    mediaReloadNotifier.value++;

  }

  // Future<void> updateForFolderRename(String oldFolderPath, String newFolderPath) async {
  //   oldFolderPath = p.normalize(oldFolderPath);
  //   newFolderPath = p.normalize(newFolderPath);
  //
  //   if (oldFolderPath == newFolderPath) return;
  //
  //   // Update main folder entry
  //   final index = _allIndexedEntries.indexWhere((e) => e.path == oldFolderPath && e.isFolder);
  //   if (index == -1) return;
  //
  //   final oldEntry = _allIndexedEntries[index];
  //   final newEntry = oldEntry.copyWith(
  //     path: newFolderPath,
  //     name: p.basename(newFolderPath),
  //     parentPath: p.dirname(newFolderPath),
  //   );
  //   _allIndexedEntries[index] = newEntry;
  //
  //   // Update notes in notifier for the renamed folder
  //   final Map<String, String> updatedNotes = Map.from(mediaNotesNotifier.value);
  //   if (updatedNotes.containsKey(oldFolderPath)) {
  //     updatedNotes[newFolderPath] = updatedNotes.remove(oldFolderPath)!;
  //   }
  //
  //   // Rename .txt file if exists
  //   final oldNoteFile = File('$oldFolderPath.txt');
  //   if (await oldNoteFile.exists()) {
  //     final newNoteFile = File('$newFolderPath.txt');
  //     try {
  //       await oldNoteFile.rename(newNoteFile.path);
  //     } catch (e) {
  //       debugPrint('Failed to rename folder note: $e');
  //     }
  //   }
  //
  //   // Update all child entries
  //   final children = _allIndexedEntries
  //       .where((e) => e.path.startsWith('$oldFolderPath/'))
  //       .toList();
  //
  //   for (final child in children) {
  //     final relative = child.path.substring(oldFolderPath.length);
  //     final updatedPath = '$newFolderPath$relative';
  //     final i = _allIndexedEntries.indexOf(child);
  //
  //     final updatedChild = child.copyWith(
  //       path: updatedPath,
  //       parentPath: p.dirname(updatedPath),
  //       name: p.basename(updatedPath),
  //     );
  //     _allIndexedEntries[i] = updatedChild;
  //
  //     // Update notes in memory
  //     if (updatedNotes.containsKey(child.path)) {
  //       updatedNotes[updatedPath] = updatedNotes.remove(child.path)!;
  //     }
  //
  //     // Rename .txt files for child files
  //     if (!child.isFolder) {
  //       final childNoteFile = File('${child.path}.txt');
  //       if (await childNoteFile.exists()) {
  //         final newChildNotePath = '$updatedPath.txt';
  //         try {
  //           await childNoteFile.rename(newChildNotePath);
  //         } catch (e) {
  //           debugPrint('Failed to rename note for child file: $e');
  //         }
  //       }
  //     }
  //   }
  //
  //   mediaNotesNotifier.value = updatedNotes;
  // }



  Future<void> updateForNewFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;

    final entry = IndexedEntry(
      path: folderPath,
      name: p.basename(folderPath),
      parentPath: p.dirname(folderPath),
      isFolder: true,
    );

    _allIndexedEntries.add(entry);
  }


  /// Removes index entry for deleted file/folder
  Future<void> updateForDelete(String path) async {
    final normalizedPath = p.normalize(path);
    _allIndexedEntries.removeWhere((entry) =>
    entry.path == normalizedPath || entry.path.startsWith('$normalizedPath/'));
  }


  /// Adds a new duplicated file or folder
  Future<void> updateForDuplicate(String newPath, bool isFolder) async {
    _allIndexedEntries.add(IndexedEntry(
      path: newPath,
      name: p.basename(newPath),
      parentPath: p.dirname(newPath),
      isFolder: isFolder,
    ));

    if (isFolder) {
      final children = await _getAllEntriesFrom(newPath);
      _allIndexedEntries.addAll(children);
    }
  }

  /// Internal helper to scan a folder and return its entries
  Future<List<IndexedEntry>> _getAllEntriesFrom(String root) async {
    final List<IndexedEntry> results = [];
    final dir = Directory(root);
    if (!await dir.exists()) return results;

    final entities = dir.listSync(recursive: true);
    for (final entity in entities) {
      final path = entity.path;
      final isFolder = entity is Directory;
      if (_shouldSkipPath(path)) continue;

      results.add(IndexedEntry(
        path: path,
        name: p.basename(path),
        parentPath: p.dirname(path),
        isFolder: isFolder,
      ));
    }

    return results;
  }


  void removeByPathPrefix(String prefix) {
    prefix = p.normalize(prefix);
    _allIndexedEntries.removeWhere((e) => e.path == prefix || e.path.startsWith('$prefix/'));

    // Optional: remove notes too
    mediaNotesNotifier.value = {
      for (var entry in mediaNotesNotifier.value.entries)
        if (!entry.key.startsWith(prefix)) entry.key: entry.value,
    };
  }



  void updateNoteContent(String filePath, String? newNote) {
    final index = _allIndexedEntries.indexWhere((e) => e.path == filePath);
    if (index != -1) {
      _allIndexedEntries[index] = _allIndexedEntries[index].copyWith(noteContent: newNote);
    }
  }


  /// Folders to skip during indexing
  bool _shouldSkipPath(String path) {
    final lower = path.toLowerCase();
    return lower.contains("/android/data") ||
        lower.contains("/android/obb") ||
        lower.contains("/miui") ||
        lower.contains("/secure") ||
        lower.contains("/.thumbnails");
  }
}
