import 'dart:async';
import 'dart:io';
import 'package:RedTree/Parameters.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_treeview/flutter_treeview.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get_utils/get_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'ProgressDialog.dart';
import 'SearchIndex.dart';
import 'file_utils.dart';
import 'globals.dart';
import 'package:path/path.dart' as p;
import 'image_crop.dart';
import 'main.dart';
import 'note_utils.dart';

class FileManager extends StatefulWidget {
  final bool showCancelBtn;
  final bool updateFolderPath; // NEW
  final List<String> selectedPaths; // Files/folders to move
  final bool enableFolderSelection;
  final VoidCallback? onFilesMoved; // Add this
  final bool isDestinationSelection; // Add this

  final void Function(String folderPath)? onFolderSelected;

  const FileManager({super.key, this.showCancelBtn = false,  this.updateFolderPath = false, this.enableFolderSelection = false, this.onFolderSelected,  this.selectedPaths = const [], this.onFilesMoved,     this.isDestinationSelection = false,
  });

  @override
  State<FileManager> createState() => _FileManagerState();
}

class _FileManagerState extends State<FileManager> {
  TreeViewController? _treeViewController = TreeViewController(children: []);
  bool _isFolderSelectionMode = false; // When true, user is selecting destination
  String? _destinationFolderPath; // The folder to which files will be moved


  late final CameraDescription camera;
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');

  bool _isSearching = false; // To toggle search interface
  final TextEditingController _searchController = TextEditingController();
  List<Node> _originalNodes = []; // Store the original full list
  late Key _treeKey = UniqueKey();
  bool _isMoveMode = false;
  String? _moveSourcePath;
  List<String> _selectedForMove = [];
   String rootPath = "/storage/emulated/0"; // Or whichever base dir is correct

  List<IndexedEntry> _allIndexedEntries = [];

  List<String> expandedFolders = [];
  bool _expandedFoldersLoaded = false;

  bool isLoading = true;
  final Set<String> loadedFolders = {};
  String?
      _targetMediaFolderPath;
  bool _okPressed = false; // Add this to your state
  final String defaultFolderPath = folderPathNotifier.value; // Save default once on init
  final Map<String, List<Node>> folderContentsCache = {};

  final ScrollController _scrollController = ScrollController();
  List<Node<dynamic>> _filteredNodes = [];
  List<Node> _fullTreeNodes = []; // Store preloaded tree here for global search
  bool _isMultiSelectMode = false;
  Set<String> _selectedFilePaths = {};
  File? _selectedFile;

  bool isAwaitingMultiFileMove = false;

  final ValueNotifier<bool> isIndexing = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is List<String>) {
      _selectedForMove = args;
      _isMoveMode = true;
    }
    if (widget.selectedPaths.isNotEmpty) {
      _enterMoveMode(widget.selectedPaths);
    }


    WidgetsBinding.instance.addPostFrameCallback((_) {
      validateFolderPath(context);
    });
    refreshTreeView();
    _initializeTree(folderPathNotifier.value);

    availableCameras().then((cameras) {
      setState(() {
        camera = cameras.first;
      });
    });
    folderPathNotifier.addListener(_handleFolderPathChange);
    _searchQuery.addListener(_handleSearchChange);

    IndexManager.instance.indexFileSystemRecursively("/storage/emulated/0").then((_) {
      print("✅ Index ready.");
      isIndexing.value = false;
      _handleSearchChange();
    });
    // final rootPath = "/storage/emulated/0";
    // NoteUtils.loadAllNotes(rootPath);
  }

  @override
  void dispose() {
    _searchQuery.removeListener(_handleSearchChange);
    _searchController.dispose();
    super.dispose();
  }


  /// NO USE ----------------- NO USE -------------------- NO USE -----------------------
  Future<void> indexFileSystemRecursively(String rootPath) async {
    _allIndexedEntries.clear();

    int folderCount = 0;
    int fileCount = 0;

    Future<void> scan(String dirPath) async {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;

      try {
        final entities = dir.listSync();

        for (final entity in entities) {
          final path = entity.path;
          final name = p.basename(path);
          final isFolder = entity is Directory;

          // ✅ Skip restricted or unwanted paths
          if (_shouldSkipPath(path)) continue;

          _allIndexedEntries.add(IndexedEntry(
            path: path,
            name: name,
            parentPath: dirPath,
            isFolder: isFolder,
          ));

          if (isFolder) {
            print("📁 Folder [${_allIndexedEntries.length}]: $path");
            await scan(path);
          }
        }
      } catch (e) {
        print("❌ Skipped inaccessible directory: $dirPath");
        print("   Reason: $e");
      }
    }

    print("🔍 Starting recursive scan at: $rootPath");
    final stopwatch = Stopwatch()..start();
    await scan(rootPath);
    stopwatch.stop();
    print("✅ Indexing complete. ${_allIndexedEntries.length} total entries "
        "(${folderCount} folders, ${fileCount} files) in ${stopwatch.elapsed.inSeconds}s.");
  }
  /// NO USE ----------------- NO USE -------------------- NO USE -----------------------
  bool _shouldSkipPath(String path) {
    final lower = path.toLowerCase();

    return lower.contains("/android/data") ||
        lower.contains("/android/obb") ||
        lower.contains("/miui") ||
        lower.contains("/secure") ||
        lower.contains("/data/user") ||
        lower.contains("/.thumbnails");
  }
  /// NO USE ----------------- NO USE -------------------- NO USE -----------------------
  List<Node<dynamic>> _buildTreeForMatches(String query) {
    final matches = _allIndexedEntries
        .where((e) => e.name.toLowerCase().contains(query.toLowerCase()))
        .toList();

    final Map<String, Node<dynamic>> nodeMap = {};
    final Set<String> requiredPaths = {};

    // Collect all parent paths of matches
    for (final match in matches) {
      String? currentPath = match.path;
      while (currentPath!.isNotEmpty) {
        requiredPaths.add(currentPath);
        final parent = _allIndexedEntries
            .firstWhere((e) => e.path == currentPath,
            orElse: () => IndexedEntry(
                path: '', name: '', parentPath: '', isFolder: true))
            .parentPath;
        currentPath = parent.isNotEmpty ? parent : '';
      }
    }

    // Build Node map
    for (final entry in _allIndexedEntries
        .where((e) => requiredPaths.contains(e.path))) {
      nodeMap[entry.path] = Node(
        key: entry.path,
        label: entry.name,
        data: {'isFile': !entry.isFolder},
        children: [],
        expanded: true,
      );
    }

    // Attach children to their parents
    for (final entry in _allIndexedEntries
        .where((e) => requiredPaths.contains(e.path))) {
      final node = nodeMap[entry.path]!;
      final parent = nodeMap[entry.parentPath];
      if (parent != null) {
        parent.children!.add(node);
      }
    }

    // Return top-level nodes
    // final roots = nodeMap.values
    //     .where((n) => !_allIndexedEntries.any(
    //         (e) => e.path == n.key && requiredPaths.contains(e.parentPath)))
    //     .toList();
    final roots = nodeMap.values
        .where((n) => !_allIndexedEntries.any((e) => e.path == n.key && nodeMap.containsKey(e.parentPath)))
        .toList();

    return roots;
  }


  // Future<void> _loadExpandedFolders() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final storedList = prefs.getStringList('expandedFolders');
  //   if (storedList != null) {
  //     expandedFolders = storedList.toSet();
  //   }
  // }


  Future<List<String>> loadExpandedFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('expandedFolders') ?? [];
  }







  void _handleSearchChange() {
    final query = _searchQuery.value.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredNodes = _treeViewController!.children);
      return;
    }

    final matches = IndexManager.instance.search(query);

    // You must convert these IndexedEntry → Node tree
    setState(() {
      _filteredNodes = buildSearchTree(matches);
    });
  }

  List<Node> buildSearchTree(List<IndexedEntry> matches) {
    const basePath = '/storage/emulated/0';
    final Map<String, Node> nodeMap = {};

    for (final entry in matches) {
      // Get relative path
      final relativePath = entry.path.replaceFirst(basePath, '').replaceAll(RegExp(r'^/'), '');
      final parts = p.split(relativePath); // use path segments without root
      String currentPath = basePath;
      Node? parent;

      for (final part in parts) {
        currentPath = p.join(currentPath, part);

        if (!nodeMap.containsKey(currentPath)) {
          final newNode = Node(
            key: currentPath,
            label: part, // 🟢 Show only part, not full path
            children: [],
            expanded: true,
            data: {'isFile': !entry.isFolder},
          );
          nodeMap[currentPath] = newNode;

          if (parent != null) {
            parent.children!.add(newNode);
          }
        }

        parent = nodeMap[currentPath];
      }
    }

    // Return only root-level nodes
    return nodeMap.values
        .where((node) => !nodeMap.values.any((n) => n.children!.contains(node)))
        .toList();
  }


  Future<void> validateFolderPath(BuildContext context) async {
    final currentPath = folderPathNotifier.value;

    if (!await FileUtils.isFolderAccessible(currentPath)) {
      if (context.mounted) {
        FileUtils.showFolderMovedSnackBar(context, currentPath);
        folderPathNotifier.value = '';
      }
    }
  }



  void _handleFolderPathChange() {
    if (folderPathNotifier.value.isNotEmpty) {
      _refreshTree(folderPathNotifier.value).then((_) {
        Navigator.pop(context);
      });
    }
  }


  Future<void> _initializeTree(String fullPath) async {
    setState(() => isLoading = true);
    await requestStoragePermission();
    _targetMediaFolderPath = fullPath; // Set the target media folder

    if (!_expandedFoldersLoaded) {
      List<String> savedExpanded = await loadExpandedFolders();
      expandedFolders.clear();
      expandedFolders.addAll(savedExpanded);
      _expandedFoldersLoaded = true;
    }

    await _refreshTree(fullPath);
    // _preloadFullTree();

  }

  Future<void> _preloadFullTree() async {
    final rootDir = Directory("/storage/emulated/0");
    final allNodes = await _loadFolderTreeRecursively(rootDir.path);
    if (!mounted) return;
    _filteredNodes = allNodes; // Save for search use
  }


  Future<List<Node>> _loadFolderTreeRecursively(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) return [];

    List<FileSystemEntity> entities;
    try {
      entities = directory.listSync();
    } catch (e) {
      // Permission denied or other IO exceptions
      debugPrint('⚠️ Skipping inaccessible folder: $path, error: $e');
      return []; // skip this folder
    }

    final List<Node> children = [];

    for (var entity in entities) {
      if (p.basename(entity.path).startsWith('.')) continue;

      if (entity is Directory) {
        final subChildren = await _loadFolderTreeRecursively(entity.path);
        children.add(Node(
          key: entity.path,
          label: p.basename(entity.path),
          children: subChildren,
          expanded: false,
          data: {'loaded': true},
        ));
      } else if (entity is File) {
        children.add(Node(
          key: entity.path,
          label: p.basename(entity.path),
          data: {'isFile': true},
        ));
      }
    }

    return children;
  }



  Future<void> _refreshTree(String path) async {
    if (!mounted) return;

    // Clear and rebuild expanded folders
    if (!_expandedFoldersLoaded) {
      expandedFolders.clear();
      List<String> parts = path.split('/');
      String currentPath = '';

      for (int i = 1; i < parts.length; i++) {
        currentPath += '/' + parts[i];
        expandedFolders.add(currentPath);
      }
    }

    setState(() => isLoading = true);
    final rootDir = Directory("/storage/emulated/0");
    List<Node> nodes = await _buildFileTree(rootDir);

    if (mounted) {
      setState(() {

        _treeViewController = TreeViewController(
          children: nodes,
          selectedKey: path,
        );
        _originalNodes = List<Node>.from(nodes);

        isLoading = false;
      });
    }
  }


  Future<void> moveItem(String sourcePath) async {
    setState(() {
      _isMoveMode = true;
      _moveSourcePath = sourcePath;
      _selectedForMove = [sourcePath]; // Support single item move
    });

    Fluttertoast.showToast(msg: "selectDestinationFromTree".tr);
  }


  void  _enterMoveMode(List<String> pathsToMove) {
    setState(() {
      _isMoveMode = true;
      _selectedForMove = List.from(pathsToMove);
    });
  }


  Future<void> _confirmAndMove(String destinationPath) async {
    // Clear any existing snackbars
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // Show persistent snackbar with confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("confirmMove".tr),
            SizedBox(height: 4),
            Text(
              destinationPath,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 4),
            // Text(
            //   "This operation cannot be undone".tr,
            //   style: TextStyle(fontSize: 12),
            // ),
          ],
        ),
        duration: Duration(minutes: 3), // Persistent until dismissed
        action: SnackBarAction(
          label: 'moveFolder'.tr,
          onPressed: () async {
            await _executeMoveOperation(destinationPath);
            // if (widget.onFilesMoved != null) {
            //   widget.onFilesMoved!();
            // }
            //
            // Navigator.of(context).pop(true);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
        actionOverflowThreshold: 1,
      ),
    );

  }

  Future<void> _executeMoveOperation(String destinationPath) async {
    setState(() => isLoading = true);

    try {
      // Track affected paths for refresh
      final affectedPaths = <String>{
        p.dirname(_selectedForMove.first), // Source parent
        destinationPath                    // Destination
      };

      // Perform moves
      for (var sourcePath in _selectedForMove) {
        final isDirectory = Directory(sourcePath).existsSync();
        final isFile = File(sourcePath).existsSync();

        if (!isDirectory && !isFile) continue;

        final itemName = p.basename(sourcePath);
        final newPath = p.join(destinationPath, itemName);

        // Ensure destination exists
        await Directory(destinationPath).create(recursive: true);

        if (isDirectory) {
          await _moveDirectory(Directory(sourcePath), Directory(newPath));
        } else {
          await FileUtils.moveFileTo(context, File(sourcePath), destinationPath);
        }
      }

      // Wait for filesystem changes
      await Future.delayed(Duration(milliseconds: 500));

      // Refresh affected paths
      // for (var path in affectedPaths) {
      //   if (await Directory(path).exists()) {
      //     await refreshTreeView();
      //   }
      // }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MainScreen(
            dateFormatNotifier: dateFormatNotifier,
            timeFormatNotifier: timeFormatNotifier,
            camera: camera,
          ),
        ),
      );

      if (widget.onFilesMoved != null) {
        widget.onFilesMoved!();
      }

      // Navigator.of(context).pop(true); // Return succes
      Fluttertoast.showToast(msg: "itemsMovedSuccess".tr);
    } catch (e) {
      debugPrint('Move error: $e');
      Fluttertoast.showToast(msg: "Move failed: ${e.toString()}".tr);
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          _isMoveMode = false;
          _selectedForMove.clear();
        });
      }
    }
  }


  void _cancelMoveMode() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (mounted) {
      setState(() {
        _isMoveMode = false;
        _selectedForMove.clear();
      });
    }
    Fluttertoast.showToast(msg: "moveCancelled".tr);
  }

  Future<void> _moveDirectory(Directory source, Directory destination) async {
    try {
      // First try simple rename (fastest if on same filesystem)
      await source.rename(destination.path);
      debugPrint('Directory renamed successfully');
    } catch (e) {
      debugPrint('Rename failed, trying copy+delete: $e');
      // Fallback to copy-then-delete if rename fails
      await _copyDirectory(source, destination);

      // Verify all files were copied before deleting source
      final copiedFiles = await Directory(destination.path).list().toList();
      if (copiedFiles.isEmpty) {
        throw Exception('No files were copied to destination');
      }

      // Delete source only after successful copy
      await source.delete(recursive: true);
      debugPrint('Directory moved via copy+delete');
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    try {
      if (!await destination.exists()) {
        await destination.create(recursive: true);
      }

      await for (var entity in source.list(recursive: false)) {
        final newPath = p.join(destination.path, p.basename(entity.path));

        if (entity is Directory) {
          await _copyDirectory(entity, Directory(newPath));
        } else if (entity is File) {
          await entity.copy(newPath);
        }
      }
    } catch (e) {
      debugPrint('Copy directory error: $e');
      // Clean up partially copied directory
      if (await destination.exists()) {
        await destination.delete(recursive: true);
      }
      rethrow;
    }
  }


  Future<void> refreshTreeView({String? targetPath}) async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      final path = targetPath ?? folderPathNotifier.value;
      final rootDir = Directory(path);

      // Preserve currently expanded folders that still exist
      // final preservedExpanded = expandedFolders.where((path) => Directory(path).existsSync()).toList();
      // expandedFolders.clear();
      // expandedFolders.addAll(preservedExpanded);

      // Rebuild tree with proper loading states
      final List<Node<dynamic>> nodes = await _buildFileTree(Directory(path));

      if (mounted) {
        setState(() {
          _treeViewController = TreeViewController(
            children: nodes,
            selectedKey: path,
          );
          isLoading = false;
        });
        // Force rebuild with new UniqueKey if needed
        _treeKey = UniqueKey();
      }
    } catch (e) {
      debugPrint('Refresh error: $e');
      if (mounted) {
        setState(() => isLoading = false);
        Fluttertoast.showToast(msg: "refreshFailed".tr);
      }
    }
  }



  Future<List<Node<dynamic>>> _buildFileTree(Directory directory) async {
    List<Node<dynamic>> nodes = [];

    try {
      final entities = await directory.list().toList();

      // Process directories first
      final folders = entities.whereType<Directory>()
          .where((d) => !d.path.startsWith('.'));

      for (var folder in folders) {
        final shouldExpand = expandedFolders.contains(folder.path);
        final List<Node<dynamic>> children = shouldExpand
            ? await _buildFileTree(folder)
            : <Node<dynamic>>[];  // Explicitly typed empty list

        nodes.add(Node<dynamic>(
          key: folder.path,
          label: p.basename(folder.path),
          expanded: shouldExpand,
          children: children,  // Now properly typed
          icon: _isMoveMode && !_selectedForMove.contains(folder.path)
              ? Icons.folder_special
              : Icons.folder,
          data: {
            'loaded': shouldExpand,
            'isMoveTarget': _isMoveMode && !_selectedForMove.contains(folder.path),
            'isExpanded': shouldExpand,
          },
        ));
      }

      // Process files
      final files = entities.where((e) => !e.path.startsWith('.') && _isMediaFile(e.path));
      for (var file in files) {
        nodes.add(Node<dynamic>(
          key: file.path,
          label: p.basename(file.path),
          data: {'isFile': true},
        ));
      }

      // Sort folders first, then files
      nodes.sort((a, b) {
        final aIsFolder = a.children != null;
        final bIsFolder = b.children != null;
        if (aIsFolder && !bIsFolder) return -1;
        if (!aIsFolder && bIsFolder) return 1;
        return a.label.compareTo(b.label);
      });

    } catch (e) {
      debugPrint('Error building tree: ${directory.path} - $e');
    }

    return nodes;
  }



  // Future<List<Node>> _loadFolderContents(String folderPath) async {
  //   if (loadedFolders.contains(folderPath)) return [];
  //   loadedFolders.add(folderPath);
  //
  //   final dir = Directory(folderPath);
  //   List<Node> nodes = [];
  //
  //   final stopwatch = Stopwatch()..start();
  //   bool toastShown = false;
  //
  //   try {
  //     final entities = dir.listSync();
  //     final mediaFiles = <FileSystemEntity>[];
  //     final folders = <FileSystemEntity>[];
  //
  //     for (var entity in entities) {
  //       if (entity is Directory) {
  //         folders.add(entity);
  //       } else if (_isMediaFile(entity.path)) {
  //         mediaFiles.add(entity);
  //       }
  //     }
  //
  //     // Add folders first
  //     for (var folder in folders) {
  //       nodes.add(Node(
  //         key: folder.path,
  //         label: folder.path.split('/').last,
  //         // Don't add empty children!
  //         expanded: false,
  //         data: {'loaded': false},
  //       ));
  //     }
  //
  //
  //     // Show temporary "Loading..." indicator
  //     if (mediaFiles.isNotEmpty) {
  //       nodes.add(Node(
  //         key: '$folderPath/__loading__',
  //         label: 'Loading...',
  //         data: {'isLoading': true},
  //       ));
  //     }
  //
  //
  //     // Update UI immediately to show folders and loading message
  //     setState(() {
  //       _treeViewController = _treeViewController!.copyWith(
  //         children: _updateNodeChildren(_treeViewController!.children, folderPath, nodes),
  //       );
  //     });
  //
  //     // Show toast after 1.5 seconds only if still loading
  //     Future.delayed(Duration(milliseconds: 1500), () {
  //       if (stopwatch.isRunning && !toastShown) {
  //         toastShown = true;
  //         Fluttertoast.showToast(msg: "Opening folder, please wait...");
  //       }
  //     });
  //
  //     // Load media in batches and update the tree node incrementally
  //     const batchSize = 20;
  //     List<Node> mediaNodes = [];
  //
  //     for (int i = 0; i < mediaFiles.length; i += batchSize) {
  //       final batch = mediaFiles.skip(i).take(batchSize);
  //
  //       for (var file in batch) {
  //         mediaNodes.add(Node(
  //           key: file.path,
  //           label: file.path.split('/').last,
  //           data: {'isFile': true},
  //         ));
  //       }
  //
  //       // Replace the current children with folders + loaded media files + "Loading..." (if not last batch)
  //       List<Node> updatedChildren = [
  //         ...nodes.where((n) => !(n.data?['isLoading'] == true)),
  //         ...mediaNodes,
  //       ];
  //
  //       if (i + batchSize < mediaFiles.length) {
  //         updatedChildren.add(Node(
  //           key: '$folderPath/__loading__',
  //           label: 'Loading...',
  //           data: {'isLoading': true},
  //         ));
  //       }
  //
  //       setState(() {
  //         _treeViewController = _treeViewController!.copyWith(
  //           children: _updateNodeChildren(
  //             _treeViewController!.children,
  //             folderPath,
  //             updatedChildren,
  //             isLoaded: false, // still loading
  //           ),
  //         );
  //       });
  //
  //       await Future.delayed(Duration(milliseconds: 100));
  //     }
  //
  //   } catch (e) {
  //     print("Error loading folder $folderPath: $e");
  //   } finally {
  //     stopwatch.stop();
  //
  //     // Final update to remove loading node and mark as loaded
  //     List<Node> finalChildren = [
  //       ...nodes.where((n) => !(n.data?['isLoading'] == true)),
  //     ];
  //
  //     setState(() {
  //       _treeViewController = _treeViewController!.copyWith(
  //         children: _updateNodeChildren(
  //           _treeViewController!.children,
  //           folderPath,
  //           finalChildren,
  //           isLoaded: true,
  //         ),
  //       );
  //     });
  //   }
  //
  //   return [];
  // }

  // ─────────────────────────────────────────────────────────────────────────────
// 2) _loadFolderContents: returns “List<Node>” (folders first, then media files)
// ─────────────────────────────────────────────────────────────────────────────

  // Future<List<Node>> _loadFolderContents(String folderPath) async {
  //   // If we've already loaded once, return the cached copy (to avoid re-scanning):
  //   if (folderContentsCache.containsKey(folderPath)) {
  //     return folderContentsCache[folderPath]!;
  //   }
  //
  //   final dir = Directory(folderPath);
  //   final children = <Node>[];
  //
  //   try {
  //     // 1) List directories and media files
  //     final entities = dir.listSync();
  //
  //     // First, collect subfolders
  //     for (final entity in entities) {
  //       if (entity is Directory) {
  //         children.add(Node(
  //           key: entity.path,
  //           label: entity.path.split('/').last,
  //           expanded: false,
  //           children: <Node>[],
  //           data: {'loaded': false},
  //         ));
  //       }
  //     }
  //
  //     // Next, collect media files (jpg, png, mp4, etc.)
  //     for (final entity in entities) {
  //       if (entity is File && _isMediaFile(entity.path)) {
  //         children.add(Node(
  //           key: entity.path,
  //           label: entity.path.split('/').last,
  //           children: <Node>[], // leaf nodes have no children
  //           data: {'isFile': true},
  //         ));
  //       }
  //     }
  //   } catch (e) {
  //     print("Error loading folder contents for $folderPath: $e");
  //   }
  //
  //   // Cache them so we don’t rescan next time:
  //   folderContentsCache[folderPath] = children;
  //   return children;
  // }


  Future<List<Node>> _loadFolderContents(String path) async {
    final dir = Directory(path);
    final List<Node> children = [];
        final mediaFiles = <FileSystemEntity>[];

    try {
      final entities = dir.listSync();

      if (entities.isEmpty) {
        Fluttertoast.showToast(msg: "folderIsEmpty".tr);
        return []; // prevents expansion and down-arrow
      }


      for (final entity in entities) {
        final entityPath = entity.path;

        /// for loading... node    for loading... node    for loading... node    for loading... node    for loading... node    for loading... node    for loading... node    for loading... node

        if (mediaFiles.isNotEmpty) {
          children.add(Node(
            key: '$entityPath/__loading__',
            label: 'Loading...',
            data: {'isLoading': true},
          ));
        }



        if (entity is Directory) {
          children.add(Node(
            key: entityPath,
            label: entityPath.split('/').last,
            children: [],
            expanded: false,
            data: {'loaded': false},
          ));
        } else if (_isMediaFile(entityPath)) {
          children.add(Node(
            key: entityPath,
            label: entityPath.split('/').last,
            data: {'isFile': true},
          ));
        }
      }

      // Also check again if the parsed `children` list is empty (e.g., only non-media files present)
      if (children.isEmpty) {
        Fluttertoast.showToast(msg: "folderIsEmpty".tr);
      }

    } catch (e) {
      print('❌ Error loading contents for $path: $e');
      Fluttertoast.showToast(msg: "failedToReadFolder".tr);
    }

    return children;
  }

  //before empty folder toast
  // Future<List<Node>> _loadFolderContents(String path) async {
  //   final dir = Directory(path);
  //   final List<Node> children = [];
  //
  //   try {
  //     final entities = dir.listSync();
  //
  //     for (final entity in entities) {
  //       final entityPath = entity.path;
  //
  //       if (entity is Directory) {
  //         children.add(Node(
  //           key: entityPath,
  //           label: entityPath.split('/').last,
  //           children: [],
  //           expanded: false,
  //           data: {'loaded': false},
  //         ));
  //       } else if (_isMediaFile(entityPath)) {
  //         children.add(Node(
  //           key: entityPath,
  //           label: entityPath.split('/').last,
  //           data: {'isFile': true},
  //         ));
  //       }
  //     }
  //   } catch (e) {
  //     print('❌ Error loading contents for $path: $e');
  //   }
  //
  //   return children;
  // }


  // Future<List<Node>> _loadFolderContents(String folderPath) async {
  //   // ✅ Return cached contents if already loaded
  //   if (folderContentsCache.containsKey(folderPath)) {
  //     print("📦 Using cached contents for: $folderPath");
  //     return folderContentsCache[folderPath]!;
  //   }
  //
  //   // ✅ Mark folder as loaded
  //   loadedFolders.add(folderPath);
  //   final dir = Directory(folderPath);
  //   List<Node> nodes = [];
  //
  //   try {
  //     final entities = dir.listSync();
  //
  //     for (var entity in entities) {
  //       if (entity is Directory) {
  //         nodes.add(Node(
  //           key: entity.path,
  //           label: entity.path.split('/').last,
  //           children: [],
  //           data: {'loaded': false},
  //         ));
  //       } else if (_isMediaFile(entity.path)) {
  //         nodes.add(Node(
  //           key: entity.path,
  //           label: entity.path.split('/').last,
  //           data: {'isFile': true},
  //         ));
  //       }
  //     }
  //
  //     // ✅ Cache the loaded nodes
  //     folderContentsCache[folderPath] = nodes;
  //   } catch (e) {
  //     print("❌ Error loading folder $folderPath: $e");
  //   }
  //
  //   return nodes;
  // }

  // 5 june 2025 - before last requirements
  // Future<List<Node>> _loadFolderContents(String folderPath) async {
  //   if (loadedFolders.contains(folderPath)) return [];
  //   loadedFolders.add(folderPath);
  //
  //   final dir = Directory(folderPath);
  //   List<Node> nodes = [];
  //   final isTargetFolder = folderPath == _targetMediaFolderPath;
  //
  //   try {
  //     final entities = dir.listSync();
  //
  //     for (var entity in entities) {
  //       if (entity is Directory) {
  //         nodes.add(Node(
  //           key: entity.path,
  //           label: entity.path.split('/').last,
  //           children: [],
  //           data: {'loaded': false},
  //         ));
  //       } else if (isTargetFolder && _isMediaFile(entity.path)) {
  //         // ONLY add media files if this is the exact target folder
  //         nodes.add(Node(
  //           key: entity.path,
  //           label: entity.path.split('/').last,
  //           data: {'isFile': true},
  //         ));
  //       }
  //     }
  //   } catch (e) {
  //     print("Error loading folder $folderPath: $e");
  //   }
  //
  //   return nodes;
  // }



//22/06/2025 - after languge trans
//   Widget _nodeBuilder(BuildContext context, Node node) {
//     final isFolder = Directory(node.key).existsSync();
//     final data = node.data;
//
//     if (node.data is Map && (node.data as Map)['isLoading'] == true) {
//
//       return Padding(
//         padding: const EdgeInsets.only(left: 36.0),
//         child: Row(
//           children:  [
//             SizedBox(
//               width: 16,
//               height: 16,
//               child: CircularProgressIndicator(strokeWidth: 2),
//             ),
//             SizedBox(width: 8),
//             Text("loading".tr),
//           ],
//         ),
//       );
//     }
//     final isFile = data is Map && data['isFile'] == true;
//     final isSelected = _treeViewController!.selectedKey == node.key;
//
//     return GestureDetector(
//       behavior: HitTestBehavior.opaque,
//
//         onTap: () {
//           if (isFile) {
//             if (_isMultiSelectMode) {
//               setState(() {
//                 if (_selectedFilePaths.contains(node.key)) {
//                   _selectedFilePaths.remove(node.key);
//                 } else {
//                   _selectedFilePaths.add(node.key);
//                 }
//               });
//             } else {
//               FileUtils.showPopupMenu(
//                 context,
//                 File(node.key),
//                 camera,
//                 null,
//                 onFileChanged: () => _reloadFileParent(node.key),
//                 onEnterMultiSelectMode: () {
//                   setState(() {
//                     _isMultiSelectMode = true;
//                     _selectedFilePaths.add(node.key);
//                   });
//                 },
//               );
//             }
//           } else {
//             // Folder tap logic
//             _handleNodeTap(node.key);
//             setState(() {
//               selectedFolderPathNotifier.value = node.key;
//               _treeViewController = _treeViewController!.copyWith(
//                 selectedKey: node.key,
//               );
//             });
//           }
//         },
//         onLongPress: () {
//         if (isFolder) _showFolderOptions(node.key);
//       },
//       onDoubleTap: () => _handleNodeDoubleTap(node),
//       child: Container(
//         padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
//         color: isSelected ? Colors.blueGrey.shade100 : null,
//         decoration: BoxDecoration(
//           color: isSelected ? Colors.blueGrey.shade100 : null,
//           // borderRadius: BorderRadius.circular(4),
//         ),
//         child: Row(
//           children: [
//             if (isFolder)
//               Icon(
//                 node.expanded ? Icons.arrow_drop_down : Icons.arrow_right,
//                 size: 24,
//                 color: Colors.grey,
//               )
//             else
//               const SizedBox(width: 24),
//
//             const SizedBox(width: 4),
//             Icon(
//               isFolder ? Icons.folder : Icons.insert_drive_file,
//               color: isFolder ? Colors.amber : Colors.grey,
//             ),
//             const SizedBox(width: 8),
//             Expanded(
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   Text(
//                     node.label,
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                   if (!isFolder)
//                     ValueListenableBuilder<Map<String, String>>(
//                       valueListenable: mediaNotesNotifier,
//                       builder: (context, mediaNotes, _) {
//                         final hasNote = mediaNotes.containsKey(node.key);
//                         return hasNote
//                             ? Icon(Icons.article, color: Colors.orange)
//                             : const SizedBox.shrink();
//                       },
//                     ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }


  Widget _nodeBuilder(BuildContext context, Node node) {
    final isFolder = Directory(node.key).existsSync();
    final data = node.data;

    if (node.data is Map && (node.data as Map)['isLoading'] == true) {
      return Padding(
        padding: const EdgeInsets.only(left: 36.0),
        child: Row(
          children:  [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text("loading".tr),
          ],
        ),
      );
    }


    final isFile = data is Map && data['isFile'] == true;
    final isSelected = _treeViewController!.selectedKey == node.key ||
        (isFile && _selectedFilePaths.contains(node.key));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isFile) {
          if (_isMultiSelectMode) {
            setState(() {
              if (_selectedFilePaths.contains(node.key)) {
                _selectedFilePaths.remove(node.key);
              } else {
                _selectedFilePaths.add(node.key);
              }
              _treeViewController = _treeViewController!.copyWith(selectedKey: node.key);
            });
          } else {
            setState(() {
              _treeViewController = _treeViewController!.copyWith(selectedKey: node.key);
            });

            FileUtils.showPopupMenu(
              context,
              File(node.key),
              camera,
              null,
              onFileChanged: () => _reloadFileParent(node.key),
              onFilesMoved: () => _initializeTree(folderPathNotifier.value),
              onEnterMultiSelectMode: () {
                setState(() {
                  _isMultiSelectMode = true;
                  _selectedFilePaths.add(node.key);
                  _treeViewController = _treeViewController!.copyWith(selectedKey: node.key);
                });
              },
            );
          }
        } else {
          // Folder tap logic
          _handleNodeTap(node.key);
          setState(() {
            selectedFolderPathNotifier.value = node.key;
            _treeViewController = _treeViewController!.copyWith(
              selectedKey: node.key,
            );
          });
        }
      },

      onLongPress: () {
        if (isFolder) _showFolderOptions(node.key, node);
      },
      onDoubleTap: () => _handleNodeDoubleTap(node),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueGrey.shade100 : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            if (isFolder)
              Icon(
                node.expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                size: 24,
                color: Colors.grey,
              )
            else
              const SizedBox(width: 24),
            const SizedBox(width: 4),
            Icon(
              isFolder ? Icons.folder : Icons.insert_drive_file,
              color: isFolder ? Colors.amber : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    node.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isFolder)
                    ValueListenableBuilder<Map<String, String>>(
                      valueListenable: mediaNotesNotifier,
                      builder: (context, mediaNotes, _) {
                        final hasNote = mediaNotes.containsKey(node.key);
                        return hasNote
                                                  ? IconButton(
                                                icon: Icon(
                                                    Icons.article, color: Colors.orange),
                                                onPressed: () =>
                                                    showNoteDialog(context, node.key),
                                              )
                            : const SizedBox.shrink();

                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }





  void _handleNodeDoubleTap(Node node) {
    final isFile = node.data is Map && node.data['isFile'] == true;

    if (isFile) {
      final file = File(node.key);
      final parentDir = file.parent;
      final mediaFiles = parentDir
          .listSync()
          .whereType<File>()
          .where((f) => _isMediaFile(f.path) && !p.basename(f.path).startsWith('.'))
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
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FolderMediaViewer(folderPath: node.key, camera: camera),
        ),
      );
    }
  }



  bool _isMediaFile(String path) {
    return path.endsWith(".jpg") ||
        path.endsWith(".jpeg") ||
        path.endsWith(".png") ||
        path.endsWith(".mp4") ||
        path.endsWith(".mov");
  }


  List<Node> _updateNodeChildren(
      List<Node> nodes,
      String parentKey,
      List<Node> newChildren, {
        bool isLoaded = false,
        bool forceExpand = false,
      }) {
    return nodes.map((node) {
      if (node.key == parentKey) {
        final shouldExpand = forceExpand || newChildren.isNotEmpty;
        print("🔵 inserting loading node for ${node.key}");

        return node.copyWith(
          children: [...newChildren], // Replace children with new list
          expanded: shouldExpand,
          data: {
            ...(node.data is Map ? node.data as Map : {}),
            'loaded': isLoaded,
          },
        );
      } else if (node.children.isNotEmpty) {
        return node.copyWith(
          children: _updateNodeChildren(
            node.children,
            parentKey,
            newChildren,
            isLoaded: isLoaded,
            forceExpand: forceExpand,
          ),
        );
      }
      return node;
    }).toList();
  }




  Future<void> _handleNodeTap(String key, {bool isDoubleTap = false}) async {
    print('🟢 Node tapped: $key');
    selectedFolderPathNotifier.value = key;

    final tappedNode = _findNode(_treeViewController!.children, key);
    if (tappedNode == null) return;

    final isFolder = Directory(key).existsSync();
    final data = tappedNode.data;
    if (_isMoveMode && isFolder) {
      if (isFolder) {
        await _expandFolderForMove(key);

        _confirmAndMove(key);

      }
      return;
    }
    if (_isMultiSelectMode && isAwaitingMultiFileMove && isFolder) {
      await _expandFolderForMove(key); // If you want to auto-expand

      ProgressDialog.show(context, _selectedFilePaths.length);

      try {
        int completed = 0;
        for (final path in _selectedFilePaths.toList()) {
          await FileUtils.moveFileTo(context, File(path), key);

          completed++;
          ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
        }

        // Fluttertoast.showToast(msg: "Moved ${_selectedFilePaths.length} files".tr);

        mediaReloadNotifier.value++;

      } catch (e) {
        Fluttertoast.showToast(msg: "Error moving files: ${e.toString()}".tr);
      } finally {
        ProgressDialog.dismiss();
        mediaReloadNotifier.value++;
        setState(() {
          isAwaitingMultiFileMove = false;
        });
        _exitMultiSelectMode();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MainScreen(
              dateFormatNotifier: dateFormatNotifier,
              timeFormatNotifier: timeFormatNotifier,
              camera: camera,
            ),
          ),
        );

        return;
      }
    }

    if (widget.enableFolderSelection && isFolder) {
      if (widget.onFolderSelected != null) {
        widget.onFolderSelected!(key);
      } else {
        Navigator.of(context).pop(widget.isDestinationSelection ? true : key);
      }
      return;
    }

    // ✅ Double-tap → open FolderMediaViewer directly
    if (isDoubleTap && isFolder) {
      _openFolderMediaViewer(key);
      return;
    }

    final isCurrentlyExpanded = expandedFolders.contains(key);

    // // 🔽 Collapse
    // if (isCurrentlyExpanded) {
    //   double? scrollOffset;
    //   if (_scrollController.hasClients) {
    //     scrollOffset = _scrollController.offset;
    //   }
    //
    //
    //   final loadingNode = Node(
    //     key: '$key/__loading__',
    //     label: 'Loading...',
    //     data: {'isLoading': true},
    //   );
    //
    //
    //   setState(() {
    //     _treeViewController = _treeViewController!.copyWith(
    //       children: _updateNodeChildren(
    //         _treeViewController!.children,
    //         key,
    //         [loadingNode],
    //         isLoaded: false,
    //         forceExpand: true,
    //       ),
    //       selectedKey: key,
    //     );
    //   });
    //   expandedFolders.add(key);
    //
    //   await saveExpandedFolders(expandedFolders);
    //   return;
    // }
    //
    // // 🔼 Expand
    //
    //
    // // expandedFolders.add(key);
    //
    //
    //
    // // ✅ Save scroll position safely if attached
    // double? scrollOffset;
    // if (_scrollController.hasClients) {
    //   scrollOffset = _scrollController.offset;
    // }
    //
    //   // 🌀 Show loading placeholder if needed
    //
    //
    //   _treeKey = UniqueKey();
    // _handleExpansionToggle(key);
    //
    // // setState(() {
    //
    //
    //     // _treeViewController = _treeViewController!.copyWith(
    //     //   children: _updateNodeChildren(
    //     //     _treeViewController!.children,
    //     //     key,
    //     //     [loadingNode],
    //     //     isLoaded: false,
    //     //     forceExpand: true,
    //     //   ),
    //     //   selectedKey: key,
    //     // );
    //
    //
    //   // });
    //
    //
    // // ✅ Restore scroll offset after short delay
    // await Future.delayed(const Duration(milliseconds: 20));
    // if (_scrollController.hasClients && scrollOffset != null) {
    //   _scrollController.jumpTo(scrollOffset);
    // }
    //
    // final children = await _loadFolderContents(key);
    //
    // if (widget.showCancelBtn) {
    //   ScaffoldMessenger.of(context).hideCurrentSnackBar();
    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(
    //       content: Text('selectedFolder $key'.tr),
    //       duration: const Duration(days: 1),
    //       action: SnackBarAction(
    //         label: 'ok'.tr,
    //         onPressed: () => _onOkPressed(key),
    //       ),
    //     ),
    //   );
    // }
    // final isCurrentlyExpanded = expandedFolders.contains(key);

    // 🔽 Collapse
    if (isCurrentlyExpanded) {


      setState(() {
        expandedFolders.remove(key);
        _treeViewController = _treeViewController!.copyWith(
          children: _toggleNodeExpansion(_treeViewController!.children, key),
          selectedKey: key,
        );
      });
      await saveExpandedFolders(expandedFolders);
      return;
    }

    // 🔼 Expand


    // expandedFolders.add(key);



    // ✅ Save scroll position safely if attached
    double? scrollOffset;
    if (_scrollController.hasClients) {
      scrollOffset = _scrollController.offset;
    }

    // 🌀 Show loading placeholder if needed
    final loadingNode = Node(
      key: '$key/__loading__',
      label: 'Loading...',
      data: {'isLoading': true},
    );
    _treeKey = UniqueKey();
    _handleExpansionToggle(key);

    // setState(() {


    // _treeViewController = _treeViewController!.copyWith(
    //   children: _updateNodeChildren(
    //     _treeViewController!.children,
    //     key,
    //     [loadingNode],
    //     isLoaded: false,
    //     forceExpand: true,
    //   ),
    //   selectedKey: key,
    // );


    // });


    // ✅ Restore scroll offset after short delay
    await Future.delayed(const Duration(milliseconds: 20));
    if (_scrollController.hasClients && scrollOffset != null) {
      _scrollController.jumpTo(scrollOffset);
    }

    final children = await _loadFolderContents(key);

    if (widget.showCancelBtn) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('selectedFolder $key'.tr),
          duration: const Duration(days: 1),
          action: SnackBarAction(
            label: 'ok'.tr,
            onPressed: () => _onOkPressed(key),
          ),
        ),
      );
    }

    if (children.isEmpty) {
      setState(() {
        _treeViewController = _treeViewController!.copyWith(
          children: _updateNodeChildren(
            _treeViewController!.children,
            key,
            [],
            isLoaded: true,
            forceExpand: false,
          ),
          selectedKey: key,
        );
      });
      expandedFolders.remove(key);
      await saveExpandedFolders(expandedFolders);

      return;
    }

    // ✅ Replace loading with real content
    setState(() {
      _treeViewController = _treeViewController!.copyWith(
        children: _updateNodeChildren(
          _treeViewController!.children,
          key,
          children,
          isLoaded: true,
          forceExpand: true,
        ),
        selectedKey: key,
      );
    });

    // 🔁 Restore scroll again if needed
    await Future.delayed(const Duration(milliseconds: 10));
    if (_scrollController.hasClients && scrollOffset != null) {
      _scrollController.jumpTo(scrollOffset);
    }
  }

  Future<void> _expandFolderForMove(String path) async {
    if (expandedFolders.contains(path)) return; // Already expanded

    // expandedFolders.add(path);
    // await saveExpandedFolders();

    // Show loading state
    setState(() {
      _treeViewController = _treeViewController!.copyWith(
          children: _updateNodeChildren(
          _treeViewController!.children,
          path,
          [Node(key: '$path/__loading__', label: 'Loading...')],
      isLoaded: false,
      forceExpand: true,
      ));
    });

    // Load actual contents
    final children = await _loadFolderContents(path);

    setState(() {
      _treeViewController = _treeViewController!.copyWith(
        children: _updateNodeChildren(
          _treeViewController!.children,
          path,
          children,
          isLoaded: true,
          forceExpand: true,
        ),
      );
    });
    await saveExpandedFolders(expandedFolders);

  }




  void _onOkPressed(String? key) {
    _okPressed = true;

    final chosenPath = key ?? defaultFolderPath;

    if (widget.updateFolderPath) {
      folderPathNotifier.value = chosenPath;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.pop(context, chosenPath);

    selectedFolderPathNotifier.value = null;

    Fluttertoast.showToast(
      msg: 'storingAt $chosenPath'.tr,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  void _handleSnackBarOnBack() {
    if (!_okPressed && widget.showCancelBtn) {
      // User pressed back without confirming,
      // so keep the default path instead of selected one.
      _onOkPressed(defaultFolderPath);
    }
  }



  void _openFolderMediaViewer(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderMediaViewer(folderPath: path, camera: camera),
      ),
    );
  }


  Node? _findNode(List<Node> nodes, String key) {
    for (final node in nodes) {
      if (node.key == key) return node;
      if (node.children.isNotEmpty) {
        final found = _findNode(node.children, key);
        if (found != null) return found;
      }
    }
    return null;
  }


  loadFileStructure(String path) async {
    setState(() {
      isLoading = true;
    });
    Directory rootDir = Directory(path);
    List<Node> nodes = await _buildFileTree(rootDir);

    setState(() {
      _treeViewController = TreeViewController(
        children: nodes,
        selectedKey: path,
      );
      isLoading = false;
    });
  }



  void _showFolderOptions(String folderPath, Node node) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.add),
            title: Text("newFolder".tr),
            onTap: () async {
              Navigator.pop(context);
              final newPath = await _createNewFolder(folderPath);
              if (newPath != null) {
                await IndexManager.instance.updateForNewFolder(newPath);
              }
            },
          ),

          ListTile(
            leading: Icon(Icons.add),
            title: Text("open".tr),
            onTap: () async {

              // Navigator.pop(context);
              // final newPath = await _createNewFolder(folderPath);
              // if (newPath != null) {
              //   await IndexManager.instance.updateForNewFolder(newPath);
              // }
              Navigator.pop(context); // Close the bottom sheet if shown
              _handleNodeDoubleTap(node);             },
          ),
          ListTile(
            leading: Icon(Icons.edit),
            title: Text("rename".tr),
              onTap: () async {
                Navigator.pop(context);
                final newPath =  await _renameFolder(folderPath);
                if (newPath != null && newPath != folderPath) {
                  await IndexManager.instance.updateForFolderRename(folderPath, newPath);
                }
              }

          ),
          ListTile(
            leading: Icon(Icons.drive_file_move),
            title: Text("moveFolder".tr),
            onTap: () async {
              Navigator.pop(context);
              moveItem(folderPath);

            },
          ),
          ListTile(
            leading: Icon(Icons.delete),
            title: Text("suppress".tr),
            onTap: () async {
              Navigator.pop(context);
              final deleted = await _deleteFolder(folderPath);
              if (deleted) {
                await IndexManager.instance.updateForDelete(folderPath);
              }
            },
          ),
        ],
      ),
    );
  }



  Future<String?> _createNewFolder(String parentFolderPath) async {
    final TextEditingController _folderNameController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('createNewFolder'.tr),
        content: TextField(
          controller: _folderNameController,
          autofocus: true,
          decoration: InputDecoration(hintText: 'enterFolderName'.tr),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              final folderName = _folderNameController.text.trim();
              if (folderName.isNotEmpty) {
                Navigator.pop(context, folderName);
              }
            },
            child: Text('createFolder'.tr),
          ),
        ],
      ),
    );

    if (result != null) {
      final newFolderPath = p.join(parentFolderPath, result);
      final newFolder = Directory(newFolderPath);

      if (!newFolder.existsSync()) {
        try {
          newFolder.createSync(recursive: true);
          loadedFolders.remove(parentFolderPath); // force reload

          // ✅ Reload UI with new folder
          List<Node> updatedChildren = await _loadFolderContents(parentFolderPath);
          List<Node> updatedNodes = _updateNodeChildren(
            _treeViewController!.children,
            parentFolderPath,
            updatedChildren,
            isLoaded: true,
          ).map((node) {
            return node.key == parentFolderPath
                ? node.copyWith(
              expanded: true,
              data: {'loaded': true},
            )
                : node;
          }).toList();

          setState(() {
            _treeViewController = _treeViewController!.copyWith(
              children: updatedNodes,
              selectedKey: _treeViewController?.selectedKey,
            );
          });

          Fluttertoast.showToast(msg: "Folder '$result' created");
          return newFolderPath;
        } catch (e) {
          Fluttertoast.showToast(msg: "Failed to create folder: $e");
        }
      } else {
        Fluttertoast.showToast(msg: "folderExists".tr);
      }
    }

    return null; // If cancelled or error
  }




  Future<void> _suppressSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    final confirmed = await _showBatchConfirmationDialog(
      context,
      title: "Delete ${_selectedFilePaths.length} files?".tr,
      message: "This action cannot be undone".tr,
      confirmText: "Delete All".tr,
    );

    if (!confirmed) return;

    ProgressDialog.show(context, _selectedFilePaths.length);

    try {
      int completed = 0;
      for (final path in _selectedFilePaths.toList()) {
        await FileUtils.deleteFile(context, File(path));
        completed++;
        ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
      }

      // Fluttertoast.showToast(msg: "Deleted ${_selectedFilePaths.length} files".tr);
      mediaReloadNotifier.value++; // Force tree refresh

    } catch (e) {
      Fluttertoast.showToast(msg: "Error deleting files".tr);
    } finally {
      ProgressDialog.dismiss();
      mediaReloadNotifier.value++; // Force tree refresh
      _exitMultiSelectMode();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FileManager(
            selectedPaths: [],
            enableFolderSelection: false,
          ),
        ),
      );
      setState(() {});
    }
  }


  Future<void> _duplicateSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    final confirmed = await _showBatchConfirmationDialog(
      context,
      title: "Duplicate ${_selectedFilePaths.length} files?".tr,
      message: "duplicateWarning".tr,
      confirmText: "duplicateAll".tr,
    );

    if (!confirmed) return;

    ProgressDialog.show(context, _selectedFilePaths.length);

    try {
      int completed = 0;
      for (final path in _selectedFilePaths.toList()) {
        await FileUtils.duplicateFile(context, File(path));
        completed++;
        ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
      }

      // Fluttertoast.showToast(msg: "Duplicated ${_selectedFilePaths.length} files".tr);
      mediaReloadNotifier.value++; // Force tree refresh

    } catch (e) {
      Fluttertoast.showToast(msg: "Error duplicating files".tr);
    } finally {
      ProgressDialog.dismiss();
      mediaReloadNotifier.value++; // Force tree refresh

      _exitMultiSelectMode();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => FileManager(
            selectedPaths: [],
            enableFolderSelection: false,
          ),
        ),
      );
      setState(() {});
    }
  }


  Future<void> _moveSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    Fluttertoast.showToast(
      msg: "Tap a folder to move ${_selectedFilePaths.length} files".tr,
      toastLength: Toast.LENGTH_LONG,
    );

    setState(() {
      isAwaitingMultiFileMove = true;
    });
  }


  Future<bool> _showBatchConfirmationDialog(
      BuildContext context, {
        required String title,
        required String message,
        required String confirmText,
      }) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("cancel".tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    ) ?? false;
  }



  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedFilePaths.clear();
      isAwaitingMultiFileMove = false;

    });
  }


  Future<void> saveExpandedFolders(List<String> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('expandedFolders', folders);
  }




  Future<String?> _renameFolder(String folderPath) async {
    final parentDir = Directory(folderPath).parent.path;
    final oldName = p.basename(folderPath);

    final controller = TextEditingController(text: oldName);

    final newPath = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('renameFolder'.tr),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: "newFolderName".tr),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // for 'move' — optional feature
                moveItem(folderPath);
              },
              child: Text('move'.tr),
            ),
            TextButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != oldName) {
                  final renamedPath = '$parentDir/$newName';
                  try {
                    Directory(folderPath).renameSync(renamedPath);
                    Fluttertoast.showToast(msg: "folderRenameSuccess".tr);
                    Navigator.pop(context, renamedPath); // ✅ return renamed path
                  } catch (e) {
                    Fluttertoast.showToast(msg: "renameFailed".tr);
                    Navigator.pop(context); // just close
                  }
                }
              },
              child: Text('rename'.tr),
            ),
          ],
        );
      },
    );

    if (newPath != null && newPath != folderPath) {
      // ✅ Update UI like _createNewFolder does
      loadedFolders.remove(parentDir); // force reload

      final updatedChildren = await _loadFolderContents(parentDir);
      final updatedNodes = _updateNodeChildren(
        _treeViewController!.children,
        parentDir,
        updatedChildren,
        isLoaded: true,
      ).map((node) {
        return node.key == parentDir
            ? node.copyWith(expanded: true, data: {'loaded': true})
            : node;
      }).toList();

      setState(() {
        _treeViewController = _treeViewController!.copyWith(
          children: updatedNodes,
          selectedKey: _treeViewController?.selectedKey,
        );
      });
    }

    return newPath;
  }



  Future<bool> _deleteFolder(String folderPath) async {
    final deletedFolderName = p.basename(folderPath);
    final parentPath = Directory(folderPath).parent.path;

    try {
      final normalizedPath = p.normalize(folderPath);

      // ✅ Physically delete the folder
      final folder = Directory(normalizedPath);
      if (!folder.existsSync()) {
        Fluttertoast.showToast(msg: "folderNotFound".tr);
        return false;
      }

      folder.deleteSync(recursive: true);

      // ✅ Remove from loaded cache if used
      loadedFolders.remove(parentPath);

      // ✅ Refresh parent folder
      final updatedChildren = await _loadFolderContents(parentPath);

      final updatedNodes = _updateNodeChildren(
        _treeViewController!.children,
        parentPath,
        updatedChildren,
        isLoaded: true,
      ).map((node) {
        return node.key == parentPath
            ? node.copyWith(expanded: true, data: {'loaded': true})
            : node;
      }).toList();

      setState(() {
        _treeViewController = _treeViewController!.copyWith(
          children: updatedNodes,
          selectedKey: _treeViewController?.selectedKey,
        );
      });

      // ✅ Optionally remove from index
      IndexManager.instance.removeByPathPrefix(normalizedPath);

      Fluttertoast.showToast(msg: "folderDeleteSuccess".tr);
      return true;
    } catch (e) {
      Fluttertoast.showToast(msg: "folderDeleteFailed".tr + ": $e");
      return false;
    }
  }




  Future<void> requestStoragePermission() async {
    if (!Platform.isAndroid) return;

    if (await Permission.manageExternalStorage.isGranted ||
        await Permission.storage.isGranted) {
      print("✅ Storage permission already granted.");
      loadFileStructure(folderPathNotifier.value);

      return;
    }

    if (await Permission.manageExternalStorage.isDenied ||
        await Permission.manageExternalStorage.isRestricted) {
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) {
        print("✅ Manage External Storage granted.");
        loadFileStructure(folderPathNotifier.value);

        return;
      } else if (status.isPermanentlyDenied) {
        print("⚠️ Permission permanently denied.");

        await openAppSettings();
        return;
      }
    }

    final fallbackStatus = await Permission.storage.request();
    if (fallbackStatus.isGranted) {
      print("✅ Storage permission granted.");
      loadFileStructure(folderPathNotifier.value);
    } else {
      print("❌ Storage permission denied.");
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_treeViewController == null) {
      return const Center(child: CircularProgressIndicator()); // or a loader placeholder
    }

    print('TreeView children: ${_treeViewController!.children}'); // Debug output

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mediaNotesNotifier.value.isEmpty) {
        loadNotesFromFolder(folderPathNotifier.value);
      }
    });

    return WillPopScope(
      onWillPop: () async {
        if (_isMoveMode) {
          _cancelMoveMode();
          return false;
        }
        _handleSnackBarOnBack();
        return true; // allow back navigation
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          shadowColor: Colors.grey,
          title: _isSearching
              ? TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'searchPlaceholder'.tr,
              border: InputBorder.none,
              hintStyle: TextStyle(color: Colors.black54),
            ),
            style: TextStyle(color: Colors.black),
            onChanged: (value) => _searchQuery.value = value.toLowerCase(),
          )
              : Text('fileManager'.tr),

            actions: [
              ValueListenableBuilder<bool>(
                valueListenable: isIndexing,
                builder: (context, indexing, _) {
                  return indexing
                      ? Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                      : IconButton(
                    icon: Icon(_isSearching ? Icons.close : Icons.search),
                    onPressed: () {
                      setState(() {
                        _isSearching = !_isSearching;
                        if (!_isSearching) {
                          _searchController.clear();
                          _searchQuery.value = '';
                        }
                      });
                    },
                  );
                },
              ),
            ]


        ),
        bottomNavigationBar: _isMultiSelectMode
            ? BottomAppBar(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              TextButton.icon(
                onPressed: _selectedFilePaths.isEmpty ? null : _suppressSelectedFiles,
                icon: Icon(Icons.delete),
                label: Text("suppress".tr),
              ),
              TextButton.icon(
                onPressed: _selectedFilePaths.isEmpty ? null : _moveSelectedFiles,
                icon: Icon(Icons.drive_file_move),
                label: Text("move".tr),
              ),
              TextButton.icon(
                onPressed: _selectedFilePaths.isEmpty ? null : _duplicateSelectedFiles,
                icon: Icon(Icons.copy),
                label: Text("duplicate".tr),
              ),
              IconButton(
                icon: Icon(Icons.close),
                onPressed: _exitMultiSelectMode,
              )
            ],
          ),
        )
            : null,


        backgroundColor: Colors.white,
        body: isLoading || _treeViewController == null
            ? Center(child: CircularProgressIndicator())
            : ValueListenableBuilder<String>(
            valueListenable: _searchQuery,
            builder: (context, query, _) {
              final nodesToDisplay = query.isEmpty
                  ? _treeViewController?.children
                  : _filteredNodes;


              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.vertical,

                      child: TreeView(

                        key: _treeKey,
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,

                        controller: _treeViewController!.copyWith(
                          children: nodesToDisplay,
                        ),
                        allowParentSelect: true,
                        theme: TreeViewTheme(
                          expanderTheme: ExpanderThemeData(
                            type: ExpanderType.none,
                            modifier: ExpanderModifier.none,
                            position: ExpanderPosition.start,
                            size: 20,
                            color: Colors.grey,
                          ),
                          labelStyle: TextStyle(fontSize: 16),
                          parentLabelStyle:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          // iconTheme: IconThemeData(size: 20, color: Colors.grey),
                          colorScheme: ColorScheme.light().copyWith(
                            primary: Colors.blueGrey.shade100,
                          ),
                        ),



                        onNodeTap: (key) {

                          final node = _findNode(_treeViewController!.children, key);
                          if (node != null) {

                            if (_isMoveMode) {
                              print("move mode enabled");
                              final isFolder = Directory(key).existsSync();
                              if (isFolder) {
                                _showDestinationConfirmation(key);
                              } else {
                                Fluttertoast.showToast(msg: "Please select a folder".tr);
                              }
                            } else {
                              _handleNodeTap(node.key);
                            }

                            setState(() {
                              selectedFolderPathNotifier.value = node.key;
                              _treeViewController = _treeViewController!.copyWith(selectedKey: node.key);
                            });
                          }
                        }



                        ,
                          onNodeDoubleTap: (key) {
                          final node = _findNode(_treeViewController!.children, key);
                          if (node != null) _handleNodeDoubleTap(node);
                        },

                        nodeBuilder: (context, node) =>


                            _nodeBuilder(context, node),

                      ),
                    ),
                  ),
                ],
              );
            }),)
    );
  }


  Future<void> _performMoveToDestination(String destinationPath) async {
    if (_selectedForMove.isEmpty || !mounted) return;

    setState(() => isLoading = true);

    try {
      // Store parent paths that need refreshing
      final pathsToRefresh = _selectedForMove.map((p) => p.split('/').sublist(0, p.split('/').length-1).join('/')).toSet();
      pathsToRefresh.add(destinationPath);

      // Perform moves
      for (var path in _selectedForMove) {
        try {
          final isDir = Directory(path).existsSync();
          final dest = isDir
              ? Directory('$destinationPath/${p.basename(path)}')
              : File('$destinationPath/${p.basename(path)}');

          if (isDir) {
            await _moveDirectory(Directory(path), dest as Directory);
          } else {
            await FileUtils.moveFileTo(context, File(path), destinationPath);
          }
        } catch (e) {
          debugPrint('Move error for $path: $e');
        }
      }

      // Wait for filesystem
      await Future.delayed(Duration(milliseconds: 500));

      // Refresh affected paths
      for (var path in pathsToRefresh) {
        if (Directory(path).existsSync()) {
          await refreshTreeView(targetPath: path);
        }
      }

      Fluttertoast.showToast(msg: "moveCompleted".tr);
    } catch (e) {
      debugPrint('Move operation failed: $e');
      Fluttertoast.showToast(msg: "Move failed".tr);
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          _isMoveMode = false;
          _selectedForMove.clear();
        });
      }
    }
  }



  void _showDestinationConfirmation(String destinationPath) {
    // Clear any existing snackbar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // Show new snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moving to: $destinationPath'),
        duration: Duration(days: 1), // Persistent until dismissed
        action: SnackBarAction(
          label: 'ok'.tr,
          onPressed: () async {
            await _performMoveToDestination(destinationPath);
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );

    // Show toast to guide user
    Fluttertoast.showToast(
      msg: "tapToConfirmOrSelectAnother".tr,
      toastLength: Toast.LENGTH_LONG,
    );
  }



  Future<void> loadNotesFromFolder(String folderPath) async {
    final Map<String, String> notes = {};

    void collectNotes(Directory dir) {
      try {
        final entries = dir.listSync();

        for (final entity in entries) {
          if (entity is File && entity.path.endsWith('.txt')) {
            try {
              final noteContent = entity.readAsStringSync();
              final imagePath = entity.path.replaceAll(RegExp(r'\.txt$'), '.jpg');
              notes[imagePath] = noteContent;
            } catch (e) {
              debugPrint("[ERROR] Failed to read note: ${entity.path}");
            }
          } else if (entity is Directory) {
            collectNotes(entity); // 🔁 Recurse into subfolder
          }
        }
      } catch (e) {
        debugPrint("🚫 Skipping inaccessible folder: ${dir.path}");
      }
    }

    collectNotes(Directory(folderPath));

    mediaNotesNotifier.value = notes;
    debugPrint("[DEBUG] Loaded ${notes.length} notes recursively.");
  }



  void showNoteDialog(BuildContext context, String imagePath) {
    final note = mediaNotesNotifier.value[imagePath] ?? "noNoteFound".tr;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("note".tr),
        content: Text(note),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("ok".tr),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close the dialog first
              NoteUtils.showNoteInputModal(
                context,
                imagePath,
                    (path, note) => NoteUtils.addOrUpdateNote(path, note, mediaNotesNotifier),
                initialText: note,
                isEditing: true,
              );

            },
            child: Text("edit".tr),
          ),
          TextButton(
            onPressed: () {
              mediaNotesNotifier.value = {...mediaNotesNotifier.value}
                ..remove(imagePath);


              Fluttertoast.showToast(msg: "noteDeleteSuccess".tr);
              Navigator.pop(context);
            },
            child: Text("delete".tr, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }


  List<Node> _toggleNodeExpansion(List<Node> nodes, String key) {
    return nodes.map((node) {
      if (node.key == key) {
        bool newState = !(node.expanded ?? false);
        return node.copyWith(expanded: newState);
      } else if (node.children.isNotEmpty) {
        return node.copyWith(
          children: _toggleNodeExpansion(node.children, key),
        );
      } else {
        return node;
      }
    }).toList();
  }

  void _handleExpansionToggle(String key) async {
    setState(() {
      if (expandedFolders.contains(key)) {
        expandedFolders.remove(key);
      } else {
        expandedFolders.add(key);
      }
      _treeViewController = _treeViewController!.copyWith(
        children: _toggleNodeExpansion(_treeViewController!.children, key),
      );
    });

    await saveExpandedFolders(expandedFolders);
  }


  Future<void> _reloadFileParent(String filePath) async {
    // Keep this for operations where partial refresh is sufficient
    final parentPath = p.dirname(filePath);
    if (!mounted) return;

    loadedFolders.remove(parentPath);
    final updatedChildren = await _loadFolderContents(parentPath);

    setState(() {
      _treeViewController = _treeViewController!.copyWith(
        children: _updateNodeChildren(
          _treeViewController!.children,
          parentPath,
          updatedChildren,
          isLoaded: true,
        ),
      );
    });
  }

  /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER /// CLASS OVER
}


class FolderMediaViewer extends StatefulWidget {
  final String folderPath;

  final CameraDescription camera;
  FolderMediaViewer({required this.folderPath, super.key, required this.camera});

  @override
  State<FolderMediaViewer> createState() => _FolderMediaViewerState();
}

class _FolderMediaViewerState extends State<FolderMediaViewer> {
  final TextEditingController _searchController = TextEditingController();

  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  bool _isMultiSelectMode = false;
  Set<String> _selectedFilePaths = {};
  File? _selectedFile;
 // Add this line to track selected file
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mediaNotesNotifier.value.isEmpty) {
        loadNotesFromFolder(widget.folderPath);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'searchNoteHint'.tr,
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.black),
          ),
          style: TextStyle(color: Colors.black),
          onChanged: (value) => _searchQuery.value = value,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _searchQuery.value = '';
            },
          ),
        ],
      ),

      bottomNavigationBar: _isMultiSelectMode
          ? BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            TextButton.icon(
              onPressed: _selectedFilePaths.isEmpty ? null : _suppressSelectedFiles,
              icon: Icon(Icons.delete),
              label: Text("suppress".tr),
            ),
            TextButton.icon(
              onPressed: _selectedFilePaths.isEmpty ? null : _moveSelectedFiles,
              icon: Icon(Icons.drive_file_move),
              label: Text("move".tr),
            ),
            TextButton.icon(
              onPressed: _selectedFilePaths.isEmpty ? null : _duplicateSelectedFiles,
              icon: Icon(Icons.copy),
              label: Text("duplicate".tr),
            ),
            IconButton(
              icon: Icon(Icons.close),
              onPressed: _exitMultiSelectMode,
            )
          ],
        ),
      )
          : null,



      body: ValueListenableBuilder<int>(
        valueListenable: mediaReloadNotifier,
        builder: (context, _, __) {
          return ValueListenableBuilder<String>(
            valueListenable: _searchQuery,
            builder: (context, query, _) {
              final mediaFiles = _getMediaFiles(filter: query);

              return ValueListenableBuilder<String>(
                valueListenable: fileAspectNotifier,
                builder: (context, aspect, _) {
                  debugPrint('Current file aspect: $aspect'); // Add debug print

                  // Use a key that changes with aspect to force widget recreation
                  return KeyedSubtree(
                    key: ValueKey<String>(aspect),
                    child: aspect == "smallImage"
                        ? _buildListView(mediaFiles, mediaNotesNotifier.value)
                        : _buildGridView(mediaFiles, mediaNotesNotifier.value, aspect),
                  );
                },
              );
            },
          );
        },
      ),

    );
  }

  List<File> _getMediaFiles({String? filter}) {
    final allFiles = Directory(widget.folderPath)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
    file.path.endsWith(".jpg") ||
        file.path.endsWith(".jpeg") ||
        file.path.endsWith(".png") ||
        file.path.endsWith(".mp4"))
        .toList();

    if (filter == null || filter.isEmpty) return allFiles;

    final query = filter.toLowerCase();

    return allFiles.where((file) {
      final nameMatch = p.basename(file.path).toLowerCase().contains(query);
      final noteMatch = mediaNotesNotifier.value[file.path]
          ?.toLowerCase()
          .contains(query) ??
          false;
      return nameMatch || noteMatch;
    }).toList();
  }



  Widget _buildListView(List<File> mediaFiles, Map<String, String> mediaNotes) {
    return ListView.builder(
      key: PageStorageKey<String>('list_view'), // Add key
      itemCount: mediaFiles.length,
      itemBuilder: (context, index) {
        final file = mediaFiles[index];
        final isSelected = _isMultiSelectMode
            ? _selectedFilePaths.contains(file.path)
            : _selectedFile?.path == file.path;

        return GestureDetector(
          onDoubleTap: () => FileUtils.openFullScreen(context, file, mediaFiles),

          onTap: () {
            setState(() {
              if (_isMultiSelectMode) {
                if (_selectedFilePaths.contains(file.path)) {
                  _selectedFilePaths.remove(file.path);
                } else {
                  _selectedFilePaths.add(file.path);
                }
              } else {
                _selectedFile = file;
                FileUtils.showPopupMenu(
                  context,
                  file,
                  widget.camera,
                  null,
                  onEnterMultiSelectMode: () {
                    setState(() {
                      _isMultiSelectMode = true;
                      _selectedFilePaths.add(file.path);
                    });
                  },
                );
              }
            });
          },

          child: Container(

            decoration: BoxDecoration(
              color: isSelected ? Colors.blueGrey.shade100 : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),


            child: ListTile(
              leading: file.path.endsWith(".mp4")
                  ? Icon(Icons.videocam)
                  : Icon(Icons.image),
              title: Text(file.path.split('/').last),
              trailing: _hasNote(file.path, mediaNotes)
                  ? IconButton(
                icon: Icon(Icons.article, color: Colors.orange),
                onPressed: () => showNoteDialog(context, file.path),
              )
                  : null,
            ),
          ),
        );
      },
    );
  }



  Widget _buildGridView(List<File> mediaFiles, Map<String, String> mediaNotes, String aspect) {
    final crossAxisCount = aspect == "midImage" ? 3 : 2; // Use raw keys

    return GridView.builder(
      key: PageStorageKey<String>('grid_view_$aspect'), // Unique key per aspect
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: mediaFiles.length, // Add this line to limit the number of items

      itemBuilder: (context, index) {
        final file = mediaFiles[index];
        final isSelected = _isMultiSelectMode
            ? _selectedFilePaths.contains(file.path)
            : _selectedFile?.path == file.path;

        return GestureDetector(


          onTap: () {
            setState(() {
              if (_isMultiSelectMode) {
                if (_selectedFilePaths.contains(file.path)) {
                  _selectedFilePaths.remove(file.path);
                } else {
                  _selectedFilePaths.add(file.path);
                }
              } else {
                _selectedFile = file;
                FileUtils.showPopupMenu(
                  context,
                  file,
                  widget.camera,
                  null,
                  onEnterMultiSelectMode: () {
                    setState(() {
                      _isMultiSelectMode = true;
                      _selectedFilePaths.add(file.path);
                    });
                  },
                );
              }
            });
          },

          onDoubleTap: () =>FileUtils.openFullScreen(context, file, mediaFiles),
          child: Container(

            decoration: BoxDecoration(
              color: isSelected ? Colors.blueGrey.shade100 : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: file.path.endsWith(".mp4")
                          ? Icon(Icons.videocam, size: 50)
                          : Image.file(File(file.path)),
                    ),
                    SizedBox(height: 4),
                    Text(
                      file.path.split('/').last,
                      style: TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (_hasNote(file.path, mediaNotes))
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => showNoteDialog(context, file.path),
                      child: Icon(Icons.article, color: Colors.amber),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _hasNote(String path, Map<String, String> mediaNotes) {
    return mediaNotes.containsKey(path) && mediaNotes[path]!.isNotEmpty;
  }




  void showNoteDialog(BuildContext context, String imagePath) {
    final note = mediaNotesNotifier.value[imagePath] ?? "No note found.";

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("note".tr),
        content: Text(note),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("ok".tr),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close the dialog first
              NoteUtils.showNoteInputModal(
                context,
                imagePath,
                    (path, note) => NoteUtils.addOrUpdateNote(path, note, mediaNotesNotifier),
                initialText: note,
                isEditing: true,
              );

            },
            child: Text("edit".tr),
          ),
          TextButton(
            onPressed: () {
              mediaNotesNotifier.value = {...mediaNotesNotifier.value}
                ..remove(imagePath);
              Fluttertoast.showToast(msg: "Note deleted successfully!");
              Navigator.pop(context);
            },
            child: Text("delete".tr, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }


  Future<void> _suppressSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    final confirmed = await _showBatchConfirmationDialog(
      context,
      title: "Delete ${_selectedFilePaths.length} files?".tr,
      message: "This action cannot be undone".tr,
      confirmText: "Delete All".tr,
    );

    if (!confirmed) return;

    ProgressDialog.show(context, _selectedFilePaths.length);

    try {
      int completed = 0;
      for (final path in _selectedFilePaths.toList()) {
        await FileUtils.deleteFile(context, File(path));
        completed++;
        ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
      }

      Fluttertoast.showToast(msg: "Deleted ${_selectedFilePaths.length} files".tr);
    } catch (e) {
      Fluttertoast.showToast(msg: "Error deleting files".tr);
    } finally {
      ProgressDialog.dismiss();
      _exitMultiSelectMode();
      setState(() {});
    }
  }


  Future<void> _duplicateSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    final confirmed = await _showBatchConfirmationDialog(
      context,
      title: "Duplicate ${_selectedFilePaths.length} files?".tr,
      message: "duplicateWarning".tr,
      confirmText: "duplicateAll".tr,
    );

    if (!confirmed) return;

    ProgressDialog.show(context, _selectedFilePaths.length);

    try {
      int completed = 0;
      for (final path in _selectedFilePaths.toList()) {
        await FileUtils.duplicateFile(context, File(path));
        completed++;
        ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
      }

      Fluttertoast.showToast(msg: "Duplicated ${_selectedFilePaths.length} files".tr);

    } catch (e) {
      Fluttertoast.showToast(msg: "Error duplicating files".tr);
    } finally {
      ProgressDialog.dismiss();
      _exitMultiSelectMode();
      setState(() {});
    }
  }



  Future<bool> _showBatchConfirmationDialog(
      BuildContext context, {
        required String title,
        required String message,
        required String confirmText,
      }) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    ) ?? false;
  }



  Future<void> _moveSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;

    Fluttertoast.showToast(
      msg: "Select destination folder for ${_selectedFilePaths.length} files".tr,
      toastLength: Toast.LENGTH_LONG,
    );

    final success = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FileManager(
          selectedPaths: _selectedFilePaths.toList(),
          enableFolderSelection: true,
        ),
      ),
    );

    if (success == true) {
      ProgressDialog.show(context, _selectedFilePaths.length);

      try {
        int completed = 0;
        // Implement your actual move logic here
        for (final path in _selectedFilePaths.toList()) {
          // await moveFileToDestination(path);
          completed++;
          ProgressDialog.updateProgress(completed, _selectedFilePaths.length);
        }

        Fluttertoast.showToast(msg: "Moved ${_selectedFilePaths.length} files".tr);
      } catch (e) {
        Fluttertoast.showToast(msg: "Error moving files".tr);
      } finally {
        ProgressDialog.dismiss();
        _exitMultiSelectMode();
        setState(() {});
      }
    }
  }


  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedFilePaths.clear();
    });
  }


  Future<void> loadNotesFromFolder(String folderPath) async {
    final dir = Directory(folderPath);
    final noteFiles = dir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith(".txt"))
        .toList();

    final Map<String, String> notes = {};

    for (var noteFile in noteFiles) {
      try {
        String noteContent = await noteFile.readAsString();
        String imagePath = noteFile.path.replaceAll(".txt", ".jpg");
        notes[imagePath] = noteContent;
      } catch (e) {
        print("[ERROR] Failed to read note file: ${noteFile.path}");
      }
    }

    mediaNotesNotifier.value = notes;
    print("[DEBUG] Loaded ${notes.length} notes from disk.");
  }

}

class FullScreenMediaViewer extends StatefulWidget {
  final List<File> mediaFiles;
  final int initialIndex;
  final CameraDescription? camera;

  const FullScreenMediaViewer({
    required this.mediaFiles,
    required this.initialIndex,
    this.camera,
    Key? key,
  }) : super(key: key);


  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {


  late PageController _pageController;
  late int _currentIndex;
  VideoPlayerController? _videoController;
  bool _isVideoInitializing = false;
  Map<String, double> _rotationAngles = {}; // Stores angle per file path

  double _scale = 1.0;
  double _previousScale = 1.0;
  TransformationController _transformationController = TransformationController();
  double _rotationAngle = 0.0;
  bool _isZoomed = false;


  late final CameraDescription camera;
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _initializeCurrentMedia();
    _rotationAngle = 0.0; // reset rotation when changing media
    _transformationController.value = Matrix4.identity();
    availableCameras().then((cameras) {
      setState(() {
        camera = cameras.first;
      });
    });
    final rootPath = "/storage/emulated/0"; // Or your base directory
    NoteUtils.loadAllNotes(rootPath);

  }

  @override
  void dispose() {
    _pageController.dispose();
    _disposeVideoController();
    _transformationController.dispose();

    super.dispose();
  }

  void _disposeVideoController() {
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
  }

  void _initializeCurrentMedia() {
    final file = widget.mediaFiles[_currentIndex];
    if (file.path.endsWith('.mp4')) {
      _isVideoInitializing = true;
      _disposeVideoController();
      _videoController = VideoPlayerController.file(file)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isVideoInitializing = false;
              _videoController?.play();
            });
          }
        }).catchError((e) {
          if (mounted) {
            setState(() {
              _isVideoInitializing = false;
            });
          }
        });
    }
  }
  void _handleMenuSelection(String value) async {
    final file = widget.mediaFiles[_currentIndex];

    switch (value) {
      case 'rename':
        // final success = await FileUtils.showRenameDialog(context, file);
        final renamed = await FileUtils.showRenameDialog(
          context,
          file,
          onMoveRequested: () async {
            // Show folder selection guidance
            Fluttertoast.showToast(
              msg: "Select destination folder".tr,
              toastLength: Toast.LENGTH_LONG,
            );

            final success = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (context) => FileManager(
                  selectedPaths: [file.path],
                  enableFolderSelection: true,
                ),
              ),
            );

            // if (success == true) {
            //   onFileChanged?.call();
            //   onFilesMoved?.call();
            // }
          },
        );
        // if (success == true) {
        //   Navigator.pop(context); // Go back after renaming
        // }
        break;

      case 'annotate':
        NoteUtils.showNoteInputModal(
          context,
          file.path,
              (imagePath, noteText) {
            NoteUtils.addOrUpdateNote(imagePath, noteText, mediaNotesNotifier);
            Navigator.pop(context); // Go back after saving note
          },
        );
        break;

      case 'duplicate':
        final success = await FileUtils.duplicateFile(context, file);
        if (success == true) {
          Navigator.pop(context);
        }
        break;

      case 'new':
        Navigator.pop(context); // Close popup
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MainScreen(
              dateFormatNotifier: dateFormatNotifier,
              timeFormatNotifier: timeFormatNotifier,
              camera: camera,
            ),
          ),
        );
        break;

      case 'move':
        final success = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => FileManager(
              selectedPaths: [file.path], // Pass the file to be moved
              enableFolderSelection: true,
            ),
          ),
        );

        if (success == true) {
          Navigator.pop(context); // Close the current viewer if move was successful
          // if (widget.onFilesMoved != null) {
          //   widget.onFilesMoved!(); // Notify parent about the move
          // }
        }
        break;

      case 'share':
        final success = await FileUtils.shareFile(context, file);
        if (success == true) {
          Navigator.pop(context);
        }
        break;

      case 'suppress':
        final success = await FileUtils.deleteFile(context, file);
        if (success != null) {
          Navigator.pop(context);
        }
        break;

      case 'rotate':
        final filePath = file.path;
        setState(() {
          final currentAngle = _rotationAngles[filePath] ?? 0.0;
          _rotationAngles[filePath] = (currentAngle - 90.0) % 360;
        });
        break;

      case 'crop':
        if (!file.path.endsWith('.jpg') &&
            !file.path.endsWith('.jpeg') &&
            !file.path.endsWith('.png')) {
          Fluttertoast.showToast(msg: "Only images can be cropped");
          return;
        }

        final success = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ImageCropScreen(imageFile: file),
          ),
        );

        if (success == true) {
          setState(() {}); // refresh image
          Fluttertoast.showToast(msg: "Image cropped successfully");
        }
        break;


    }
  }



  @override
  Widget build(BuildContext context) {
    final currentFile = widget.mediaFiles[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(p.basename(currentFile.path)),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert),
            onSelected: _handleMenuSelection,
            itemBuilder: (context) =>  [
              PopupMenuItem(value: 'annotate', height: 36, child: Text('annotate'.tr)),
              PopupMenuItem(value: 'rename', height: 36, child: Text('rename'.tr)),
              PopupMenuItem(value: 'duplicate', height: 36, child: Text('duplicate'.tr)),
              PopupMenuItem(value: 'new', height: 36, child: Text('new'.tr)),
              PopupMenuItem(value: 'move', height: 36, child: Text('moveTo'.tr)),
              PopupMenuItem(value: 'share', height: 36, child: Text('share'.tr)),
              PopupMenuItem(value: 'suppress', height: 36, child: Text('suppress'.tr)),
              PopupMenuItem(value: 'rotate', height: 36, child: Text('rotate'.tr)),
              PopupMenuItem(value: 'crop', height: 36, child: Text('crop'.tr)),

            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            // controller: _pageController,
            // itemCount: widget.mediaFiles.length,
            // onPageChanged: (index) {
            //   setState(() {
            //     _currentIndex = index;
            //     _initializeCurrentMedia();
            //     _transformationController.value = Matrix4.identity(); // reset zoom
            //   });
            // },

            controller: _pageController,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            itemCount: widget.mediaFiles.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _initializeCurrentMedia();
                _transformationController.value = Matrix4.identity();
                _isZoomed = false;
              });
            },

            itemBuilder: (context, index) {
              final file = widget.mediaFiles[index];
              if (file.path.endsWith('.mp4')) {
                return _buildVideoPlayer();
              } else {

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return
                    //   GestureDetector(
                    //   behavior: HitTestBehavior.opaque,
                    //   onDoubleTap: () {
                    //     if (_transformationController.value != Matrix4.identity()) {
                    //       _transformationController.value = Matrix4.identity();
                    //     } else {
                    //       _transformationController.value = Matrix4.identity()..scale(2.0);
                    //     }
                    //   },
                    //   child: InteractiveViewer(
                    //     transformationController: _transformationController,
                    //     panEnabled: true,
                    //     scaleEnabled: true,
                    //     minScale: 1.0,
                    //     maxScale: 4.0,
                    //
                    //     child: Center(
                    //       child: Transform.rotate(
                    //         angle: (_rotationAngles[file.path] ?? 0) * 3.1415926535 / 180, // convert to radians
                    //         child: Image.file(file),
                    //       ),
                    //     ),
                    //
                    //   ),
                    // );
                      GestureDetector(
                        onDoubleTapDown: (details) {
                          final tapPosition = details.localPosition;
                          final scale = _transformationController.value.getMaxScaleOnAxis();
                          if (scale > 1.0) {
                            _transformationController.value = Matrix4.identity();
                            _isZoomed = false;
                          } else {
                            final zoom = 2.5;
                            final x = -tapPosition.dx * (zoom - 1);
                            final y = -tapPosition.dy * (zoom - 1);
                            _transformationController.value = Matrix4.identity()
                              ..translate(x, y)
                              ..scale(zoom);
                            _isZoomed = true;
                          }
                          setState(() {});
                        },
                        onScaleStart: (_) {
                          _previousScale = _scale;
                        },
                        onScaleUpdate: (details) {
                          _scale = _previousScale * details.scale;
                          if (_scale > 1.0) {
                            _isZoomed = true;
                          } else {
                            _isZoomed = false;
                          }
                          setState(() {});
                        },
                        child: InteractiveViewer(
                          transformationController: _transformationController,
                          panEnabled: true,
                          scaleEnabled: true,
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: FutureBuilder(
                            future: _refreshImage(file.path),
                            builder: (context, snapshot) {
                              return Transform.rotate(
                                angle: (_rotationAngles[file.path] ?? 0) * 3.1415926535 / 180,
                                child: Image(
                                  image: FileImage(File(file.path)),
                                  key: ValueKey(file.path), // refreshes on file path
                                ),
                              );
                            },
                          ),
                        ),
                      );

                  },
                );

              }
            },
          ),

          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Text(
              "${_currentIndex + 1}/${widget.mediaFiles.length}",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          if (_isVideoInitializing)
            Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Future<void> _refreshImage(String filePath) async {
    final provider = FileImage(File(filePath));
    await provider.evict(); // 🔥 clear from Flutter image cache
  }


  Widget _buildVideoPlayer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container();
    }
    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: Stack(
        children: [
          VideoPlayer(_videoController!),
          if (!_videoController!.value.isPlaying)
            Center(
              child: IconButton(
                icon: Icon(Icons.play_arrow, size: 50, color: Colors.white),
                onPressed: () {
                  _videoController?.play();
                  setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }
}


