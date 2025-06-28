import 'package:RedTree/note_utils.dart';
import 'package:RedTree/translations.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'FileManager.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'Parameters.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'generated/l10n.dart';
import 'globals.dart'; // Import the global folderPathNotifier
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  // Create the notifiers here
  final dateFormatNotifier = ValueNotifier<String>('yyyy/mm/dd');
  final timeFormatNotifier = ValueNotifier<String>('24h');
  final now = DateTime.now();
  final prefixFormat = fileNamingPrefixNotifier.value;

  final formatParts = prefixFormat.split(' '); // Ex: ['yyyy/mm/dd', '24h']

  await _initLanguage();
  runApp(OverlaySupport.global(
    child: MyApp(
      camera: firstCamera,
      dateFormatNotifier: dateFormatNotifier,
      timeFormatNotifier: timeFormatNotifier,
    ),
  ));
  // createRedTreeFolder();
}

Future<void> _initLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  final savedLangCode = prefs.getString('languageCode') ?? 'en'; // use code

  languageNotifier.value = savedLangCode; // now holds 'fr', 'es', etc.
  Get.updateLocale(Locale(savedLangCode));
}


class MyApp extends StatelessWidget {
  final CameraDescription camera;
  final ValueNotifier<String> dateFormatNotifier;
  final ValueNotifier<String> timeFormatNotifier;

  const MyApp({
    Key? key,
    required this.camera,
    required this.dateFormatNotifier,
    required this.timeFormatNotifier,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: languageNotifier,
      builder: (context, langCode, _) {
        return GetMaterialApp(
          title: 'RedTree',
          theme: ThemeData(primarySwatch: Colors.blue),
          locale: Locale(langCode),
          translations: AppTranslations(), // ✅ Add this
          fallbackLocale: const Locale('en'),
          home: MainScreen(
            camera: camera,
            dateFormatNotifier: dateFormatNotifier,
            timeFormatNotifier: timeFormatNotifier,
          ),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  final CameraDescription camera;
  final ValueNotifier<String> dateFormatNotifier;
  final ValueNotifier<String> timeFormatNotifier;

  const MainScreen(
      {required this.dateFormatNotifier,
      required this.timeFormatNotifier,
      Key? key,
      required this.camera})
      : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  bool _isImageFrozen = false;
  String? _capturedImagePath;
  bool _isRecording = false;
  String? _recordedVideoPath;
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  VideoPlayerController? _videoController;
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  final ValueNotifier<bool> _isRedTreeActivatedNotifier =
      ValueNotifier<bool>(false);
  double _rtBoxDelay = 1.5; // Default delay
  late TextEditingController _delayController;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  XFile? _videoFile;
  // bool _isRecording = false;
  // VideoPlayerController? _videoController;
  AppLifecycleState? _appLifecycleState;
  bool _isCameraPaused = false;
  bool _isAppInForeground = true;
  bool _needsFullRestart = false; // New flag for lock/unlock handling

  bool _isRestarting = false;
  bool _showTempPreview = false; // Add this to your state class
  File? _lastCapturedImage; // Stores the last captured frame


  bool _showFrozenImage = false;
  File? _frozenImageFile;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    // _controller = CameraController(
    //   widget.camera,
    //   ResolutionPreset.ultraHigh,
    // );
    // _initializeControllerFuture = _controller.initialize();
    _speech = stt.SpeechToText();

    _loadRedTreeStates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppInForeground = state == AppLifecycleState.resumed;

    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _pauseCamera();
      _needsFullRestart = true; // Device locked - need full restart
    } else if (state == AppLifecycleState.resumed) {
      if (_needsFullRestart) {
        restartCamera(); // Use full restart after unlock
      } else {
        _resumeCamera(); // Normal resume for other cases
      }
    }
  }


  Future<void> _initCamera() async {
    if (!_isAppInForeground) {
      await Future.delayed(Duration(milliseconds: 300));
      if (!_isAppInForeground) return;
    }

    try {
      if (_controller != null) {
        await _controller!.dispose();
      }

      _controller = CameraController(
        widget.camera,
        ResolutionPreset.ultraHigh,
        enableAudio: true,
      );

      _initializeControllerFuture = _controller!.initialize().then((_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      print("Camera initialization error: $e");
      if (e is CameraException && e.code == 'CameraAccess') {
        await Future.delayed(Duration(seconds: 1));
        _initCamera(); // Retry initialization
      }
    }
  }
  Future<void> _pauseCamera() async {
    if (_isCameraPaused || _controller == null) return;
    try {
      await _controller!.pausePreview();
      _isCameraPaused = true;
      if (mounted) setState(() {});
    } catch (e) {
      print("Error pausing camera: $e");
    }
  }

  Future<void> _resumeCamera() async {
    if (!_isCameraPaused || _controller == null) return;
    try {
      await _controller!.resumePreview();
      _isCameraPaused = false;
      if (mounted) setState(() {});
    } catch (e) {
      print("Error resuming camera: $e");
      await _initCamera(); // Full reinitialization if resume fails
    }
  }



  Future<void> _loadRedTreeStates() async {
    final prefs = await SharedPreferences.getInstance();
    double savedDelay = prefs.getDouble('rtBoxDelay') ?? 1.5;
    final savedPath = prefs.getString('folderPath') ?? "/storage/emulated/0/Download";
    bool isRedTreeActivated = prefs.getBool('redtree') ?? false;
    String savedPrefix     = prefs.getString('fileNamingPrefix')  ?? fileNamingPrefixNotifier.value;

    setState(() {
      isRedTreeActivatedNotifier.value = isRedTreeActivated;
      rtBoxDelayNotifier.value = savedDelay;
      fileNamingPrefixNotifier.value   = savedPrefix;
      folderPathNotifier.value = savedPath;

    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // ✅ Prevents shrinking when keyboard opens

      body: FutureBuilder<void>(

        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              _controller != null &&
              _controller!.value.isInitialized &&
              !_isCameraPaused &&
              _isAppInForeground &&
              _controller!.value.previewSize != null) {

            final size = _controller!.value.previewSize!;
            final cameraAspectRatio = size.height / size.width; // ⬅️ Very important

            return Stack(
              children: [

                // if ((_isRestarting || _showTempPreview) && _lastCapturedImage != null)
                //   Positioned.fill(
                //     child: AspectRatio(
                //       aspectRatio: cameraAspectRatio,
                //       child: Image.file(
                //         _lastCapturedImage!,
                //         fit: BoxFit.cover,
                //       ),
                //     ),
                //   ),



                if (!_isRestarting &&
                    _controller != null &&
                    _controller!.value.isInitialized &&
                    !_isCameraPaused &&
                    _isAppInForeground)
                  Center(
                    child: AspectRatio(
                      aspectRatio: cameraAspectRatio,
                      child: CameraPreview(_controller!),
                    ),
                ),

                if (_recordedVideoPath != null && !_isRecording)
                  Positioned.fill(
                    child: VideoPlayer(_videoController!),
                  ),


                // Frozen Image Overlay with correct aspect ratio
                if (_isImageFrozen && _capturedImagePath != null)
                  Center(
                    child: AspectRatio(
                      aspectRatio: cameraAspectRatio,
                      child: Image.file(
                        File(_capturedImagePath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),


                // Top Bar
                Positioned(
                  top: MediaQuery.of(context).padding.top,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black,
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(width: 48),
                        ValueListenableBuilder<bool>(
                          valueListenable: isRedTreeActivatedNotifier,
                          builder: (context, isRedTreeActivated, child) {
                            return Switch(
                              value: isRedTreeActivated,
                              onChanged: (value) async {
                                isRedTreeActivatedNotifier.value = value;
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setBool('redtree', value);
                                setState(() {
                                  isRedTreeActivatedNotifier.value =
                                      value;
                                }); // Save value persistently
                              },
                              activeColor: Colors.blue,
                              activeTrackColor:
                                  Color.fromRGBO(215, 215, 215, 1.0),
                              inactiveTrackColor:
                                  Color.fromRGBO(215, 215, 215, 1.0),
                              inactiveThumbColor: Colors.white,
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.settings, color: Colors.white),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ParametersScreen(

                                  camera: widget.camera,
                                  onDelayChanged: onDelayChangedGlobal!
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Bar
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black,
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        IconButton(
                          icon: Icon(
                            _isRecording ? Icons.stop : Icons.videocam,
                            color: Colors.white,
                          ),
                          onPressed: () async {
                            try {
                              await _initializeControllerFuture;
                              await _controller?.setFlashMode(FlashMode.off);

                              if (_isRecording) {
                                // Stop recording
                                final video = await _controller?.stopVideoRecording();
                                setState(() {
                                  _videoFile = video;
                                  _isRecording = false;
                                });

                                // Initialize video player
                                _videoController = VideoPlayerController.file(File(video!.path))
                                  ..initialize().then((_) {
                                    setState(() {});
                                    _videoController?.play();
                                  });

                                // Show settings popup after delay
                                if (isRedTreeActivatedNotifier.value) {
                                  Future.delayed(
                                    Duration(milliseconds: (rtBoxDelayNotifier.value * 1000).toInt()),
                                        () {
                                      _showImageSettingsPopup(context, video.path, extension: 'mp4');
                                    },
                                  );
                                } else {
                                  _saveToLDF(context, video.path, extension: 'mp4');
                                  Fluttertoast.showToast(msg: "Video saved successfully to: ${video.path}");
                                  // showCustomSuccessPopup(context, "Video saved successfully to: ${video.path}");
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    restartCamera();
                                  });
                                }

                              } else {
                                // Start recording
                                await _controller?.startVideoRecording();
                                setState(() {
                                  _isRecording = true;
                                });
                              }
                            } catch (e) {
                              print("❌ Error with video recording: $e");
                            }
                          },
                        ),



                        IconButton(

                          icon: Icon(Icons.camera_alt, color: Colors.white),

                          onPressed: () async {
                            try {
                              // 1. Ensure camera is ready
                              await _initializeControllerFuture;
                              await _controller?.setFlashMode(FlashMode.off);

                              // 2. Freeze UI and capture image
                              // setState(() => _isImageFrozen = true);
                              final image = await _controller?.takePicture();
                              final imageFile = File(image!.path);

                              // 3. Immediately show captured image
                              setState(() {
                                // _lastCapturedImage = imageFile;
                                _capturedImagePath = image.path;
                                _isImageFrozen = true;

                              });

                              // 4. Handle RedTree mode or normal save
                              if (isRedTreeActivatedNotifier.value) {
                                // Delay for RedTree processing
                                await Future.delayed(
                                  Duration(milliseconds: (rtBoxDelayNotifier.value * 1000).toInt()),
                                );
                                _showImageSettingsPopup(context, image.path, extension: 'jpg');
                              } else {
                                // 5. Save to gallery with smooth transition
                                final now = DateTime.now();
                                final fileName = '${generateFileNamePrefix(now)}.jpg';
                                final cameraDir = Directory('/storage/emulated/0/DCIM');
                                final savePath = '${cameraDir.path}/$fileName';

                                try {
                                  // Show captured image while saving
                                  // setState(() => _showTempPreview = true);

                                  // Save in background
                                  await imageFile.copy(savePath);
                                  Fluttertoast.showToast(msg: "Image saved successfully");

                                  // Smooth camera restart
                                  await _restartCameraSmoothly();
                                } catch (e) {
                                  debugPrint('❌ Error saving image: $e');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed to save image')),
                                  );
                                } finally {
                                  if (mounted) setState(() => _showTempPreview = false);
                                }
                              }
                            } catch (e) {
                              debugPrint("❌ Error capturing image: $e");
                              // Ensure camera restarts even on error
                              if (mounted) await _restartCameraSmoothly();
                            }
                          },
                        ),



                        IconButton(
                          icon: Icon(Icons.folder, color: Colors.orangeAccent),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    FileManager(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }


  // Future<void> restartCamera() async {
  //   if (!mounted || _isRestarting) return;
  //   _isRestarting = true;
  //
  //   try {
  //     // Show loading state immediately
  //     if (mounted) setState(() {});
  //
  //     // Dispose old controller
  //     await _controller?.dispose();
  //     // await Future.delayed(Duration(milliseconds: 500));
  //     _isImageFrozen = false;
  //     // Create new controller
  //     _controller = CameraController(
  //       widget.camera,
  //       ResolutionPreset.ultraHigh,
  //       enableAudio: true,
  //     );
  //
  //     // Initialize and update state
  //     _initializeControllerFuture = _controller!.initialize();
  //     await _initializeControllerFuture;
  //
  //     _isCameraPaused = false;
  //     _needsFullRestart = false;
  //   } catch (e) {
  //     print("Camera restart error: $e");
  //     // Retry after delay if failed
  //     await Future.delayed(Duration(seconds: 1));
  //     if (mounted) restartCamera();
  //   } finally {
  //     _isRestarting = false;
  //     if (mounted) setState(() {});
  //   }
  // }
  Future<void> restartCamera() async {
    if (!mounted || _isRestarting) return;
    _isRestarting = true;

    try {
      // Freeze current frame if available
      if (_controller?.value.isInitialized == true && _lastCapturedImage != null) {
        setState(() {
          _showFrozenImage = true;
          _frozenImageFile = _lastCapturedImage;
        });
      }

      // Dispose old controller
      await _controller?.dispose();
      _isImageFrozen = false;

      // Create new controller
      _controller = CameraController(
        widget.camera,
        ResolutionPreset.ultraHigh,
        enableAudio: true,
      );

      // Initialize and update state
      await _controller!.initialize();

      _isCameraPaused = false;
      _needsFullRestart = false;
    } catch (e) {
      print("Camera restart error: $e");
      await Future.delayed(Duration(seconds: 1));
      if (mounted) restartCamera();
    } finally {
      if (mounted) {
        setState(() {
          _isRestarting = false;
          _showFrozenImage = false;
        });
      }
    }
  }

  Future<void> _handleClose() async {
    try {
      // Capture current frame before closing
      if (_controller != null && _controller!.value.isInitialized) {
        final XFile? file = await _controller?.takePicture();
        if (file != null) {
          setState(() {
            _lastCapturedImage = File(file.path);
            _showTempPreview = true;
            _showFrozenImage = true;
            _frozenImageFile = _lastCapturedImage;
          });
        }
      }

      Navigator.pop(context);
      await _restartCameraSmoothly();
    } finally {
      if (mounted) {
        setState(() => _showTempPreview = false);
      }
    }
  }

  Future<void> _restartCameraSmoothly() async {
    // if (_isRestarting) return;
    // _isRestarting = true;

    try {
      // Dispose old controller if exists and not disposed
      // if (_controller != null && _controller!.value.isInitialized) {
      //   await _controller!.dispose();
      // }

      // Create new controller
      // _controller = CameraController(
      //   widget.camera,
      //   ResolutionPreset.ultraHigh,
      //   enableAudio: true,
      // );

      _isImageFrozen = false;


      // Initialize with timeout
      // await _controller!.initialize().timeout(
      //   Duration(seconds: 2),
      //   onTimeout: () => debugPrint("Camera init timeout"),
      // );

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera restart error: $e");
      // Add retry logic if needed
    } finally {
      _isRestarting = false;
    }
  }



  // Future<void> restartCamera() async {
  //   if (!mounted) return; // Early exit if widget is already disposed
  //
  //
  //   try {
  //     //
  //     // if (_controller.value.isInitialized) {
  //     //   print("Disposing old camera...");
  //     //   await _controller.dispose();
  //     // }
  //
  //     // Small delay to ensure native threads clean up
  //     await Future.delayed(const Duration(milliseconds: 400));
  //     _isImageFrozen = false;
  //
  //     print("Reinitializing controller...");
  //     _controller = CameraController(
  //       widget.camera,
  //       ResolutionPreset.ultraHigh,
  //       enableAudio: true,
  //     );
  //
  //     if (!mounted) return; // Double-check before setting state
  //     setState(() {
  //       _initializeControllerFuture = _controller?.initialize();
  //     });
  //
  //     await _initializeControllerFuture;
  //
  //     if (mounted) {
  //       print("✅ Camera restarted successfully.");
  //     }
  //   } catch (e, stackTrace) {
  //     print("❌ Failed to restart camera: $e\n$stackTrace");
  //   }
  // }

  // Future<void> restartCamera() async {
  //   if (!mounted) return;
  //   try {
  //     await _controller?.dispose();
  //     await Future.delayed(const Duration(milliseconds: 300));
  //
  //     _controller = CameraController(
  //       widget.camera,
  //       ResolutionPreset.ultraHigh,
  //       enableAudio: true,
  //     );
  //
  //     _initializeControllerFuture = _controller?.initialize();
  //     await _initializeControllerFuture;
  //     if (mounted) setState(() {});
  //   } catch (e) {
  //     print("Camera restart error: $e");
  //   }
  // }

  Future<bool> _checkPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      if (Platform.isAndroid) Permission.accessMediaLocation,
    ].request();

    // Check if all are granted
    return statuses.values.every((status) => status.isGranted);
  }


  Future<void> _showImageSettingsPopup(BuildContext context, String filePath, {required String extension}) async {
    final now = DateTime.now();


    String prefix = generateFileNamePrefix(now);
    String fileName = prefix;
    String selectedFolderPath =
        folderPathNotifier.value; // Store initial folder
    final TextEditingController fileNameController =
        TextEditingController(text: fileName);
    ValueNotifier<bool> isOkEnabled = ValueNotifier(false);
    final ValueNotifier<String?> _temporarySelectedFolderPath = ValueNotifier(null); // 🔸


    await showDialog(
      context: context,
      barrierDismissible: false, // ❌ Prevents closing on outside touch
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white, // ✅ White background
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero), // ✅ No curved borders
              contentPadding: EdgeInsets.zero, // ✅ No extra spaces
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Filename Input with Mic Icon
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: fileNameController,
                            decoration: InputDecoration(
                              hintText: 'Enter file name',
                              border: InputBorder.none, // No extra space
                              suffixIcon: IconButton(
                                icon: Icon(Icons.mic),
                                onPressed: () async {
                                  if (!_isListening) {
                                    bool available = await _speech.initialize(
                                      onStatus: (status) => print('Speech status: $status'),
                                      onError: (error) => print('Speech error: $error'),
                                    );

                                    if (available) {
                                      _isListening = true;
                                      _speech.listen(
                                        onResult: (result) {
                                          // fileNameController.text = result.recognizedWords.replaceAll(' ', '_');
                                          final spokenName = result.recognizedWords.replaceAll(' ', '_');
                                          fileNameController.text = spokenName;
                                          fileName = spokenName; // ✅ Ensures mic input is saved
                                          isOkEnabled.value = (fileName.trim().isNotEmpty || fileName != prefix) ||
                                              (selectedFolderPath != folderPathNotifier.value);
                                        },
                                      );
                                    }
                                  } else {
                                    _speech.stop();
                                    _isListening = false;
                                  }
                                },

                              ),
                            ),
                            onTap: () {
                              // autoCloseTimer
                              //     ?.cancel(); // ❌ Cancel timer when typing
                            },
                            onChanged: (value) {
                              fileName = value;
                              isOkEnabled.value = (fileName.trim().isNotEmpty ||
                                      fileName != prefix) ||
                                  (selectedFolderPath !=
                                      folderPathNotifier.value);
                            },
                          ),
                        ),


                        ValueListenableBuilder<String?>(
                          valueListenable: _temporarySelectedFolderPath,
                          builder: (context, tempPath, _) {
                            final displayPath = tempPath ?? folderPathNotifier.value;
                            return Text(displayPath, style: TextStyle(color: Colors.black));
                          },
                        ),
                      ],
                    ),
                  ),

                  Divider(thickness: 1, height: 1), // ✅ Horizontal Divider

                  // Action Icons Row with Vertical Dividers
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildIconButton(Icons.delete, Colors.red, () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: Colors.white,
                            title: Text("Confirm Delete"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text("Cancel"),
                              ),
                              TextButton(
                                onPressed: () async {
                                  File(filePath).deleteSync();

                                  await _restartCameraSmoothly();
                                  Navigator.pop(context);
                                  Navigator.pop(context);

                                },
                                child: Text("Confirm",
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                      }),
                      _buildVerticalDivider(),
                      _buildIconButton(Icons.close, Colors.black, () async {

                        _isImageFrozen = true;
                        await _restartCameraSmoothly();
                        Navigator.pop(context);

                      }),


                      _buildVerticalDivider(),

                      TextButton(
                        onPressed: () async {
                          final saveFolder = selectedFolderPath.isNotEmpty
                              ? selectedFolderPath
                              : folderPathNotifier.value;
                          final saveName = fileName.isNotEmpty
                              ? fileName
                              : path.basenameWithoutExtension(filePath);
                          final extension = path.extension(filePath);

                          String savePath = "$saveFolder/$saveName$extension";

                          try {
                            // 1. Copy the image
                            File(filePath).copySync(savePath);

                            // 2. Copy the note file if exists
                            String oldNotePath = path.withoutExtension(filePath) + ".txt";
                            String newNotePath = path.withoutExtension(savePath) + ".txt";

                            if (File(oldNotePath).existsSync()) {
                              File(oldNotePath).copySync(newNotePath);
                              debugPrint("Note copied from $oldNotePath to $newNotePath");

                              // 3. Update media notes
                              String note = File(newNotePath).readAsStringSync();
                              final updatedNotes = Map<String, String>.from(mediaNotesNotifier.value);
                              updatedNotes[savePath] = note;
                              mediaNotesNotifier.value = updatedNotes;
                            }
                            Fluttertoast.showToast(msg: "Image saved successfully to: $savePath");
                            // showCustomSuccessPopup(context, "Image saved successfully to: $savePath");

                            _isImageFrozen = true;
                            await _restartCameraSmoothly();
                            Navigator.pop(context);

                          } catch (e) {
                            Fluttertoast.showToast(msg:"Save failed: ${e.toString()}");
                                // showCustomErrorPopup(context, "Save failed: ${e.toString()}");
                          }
                        },
                        child: const Text("OK"),
                      ),

                      _buildVerticalDivider(),

                      _buildIconButton(Icons.folder, Colors.blue, () async {
                        final selectedFolder = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => FileManager(showCancelBtn: true,updateFolderPath: false,)),
                        );

                        if (selectedFolder != null) {
                          selectedFolderPath = selectedFolder; // <-- Store it locally
                          _temporarySelectedFolderPath.value = selectedFolder; // ✅ Update path

                          print("Selected folder (temporary): $selectedFolderPath");
                        }
                      }),

                      _buildVerticalDivider(),

                      _buildIconButton(Icons.article, Colors.orange, () {
                        NoteUtils.showNoteInputModal(context, filePath,
                              (imagePath, noteText) {
                            NoteUtils.addOrUpdateNote(imagePath, noteText, mediaNotesNotifier);
                          },
                        );
                      }),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },

    );
    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    //   await _restartCameraSmoothly();
      _isImageFrozen = false;
    // });
    }

    Future<void> _saveToLDF(BuildContext context, String path, {required String extension}) async {
      final now = DateTime.now();


      String prefix = generateFileNamePrefix(now);
      String fileName = prefix;
      String selectedFolderPath =
          folderPathNotifier.value;

      String savePath = "$selectedFolderPath/$fileName.$extension";
      File(path).copySync(savePath);
      // restartCamera();
      // _isImageFrozen = true;
      await _restartCameraSmoothly();
      // Navigator.pop(context);

      // Navigator.pop(context);

    }

  Future<void> _showNoteInputModal(BuildContext context, String imagePath) async {
    TextEditingController noteController = TextEditingController();
    bool _isListening = false;
    final stt.SpeechToText speech = stt.SpeechToText();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
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
                          icon: Icon(Icons.keyboard),
                          onPressed: () {}, // just visual, already typing
                        ),
                        IconButton(
                          icon: Icon(Icons.mic),
                          onPressed: () async {
                            if (!_isListening) {
                              bool available = await speech.initialize(
                                onStatus: (status) => print('Speech status: $status'),
                                onError: (error) => print('Speech error: $error'),
                              );

                              if (available) {
                                _isListening = true;
                                speech.listen(
                                  onResult: (result) {
                                    setState(() {
                                      noteController.text = result.recognizedWords;
                                    });
                                  },
                                );
                              }
                            } else {
                              speech.stop();
                              setState(() {
                                _isListening = false;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    TextField(
                      controller: noteController,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: 'Type your note here...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(context), child: Text("Cancel")),
                        ElevatedButton(
                          onPressed: () {
                            String note = noteController.text.trim();
                            print("[DEBUG] OK pressed in note modal.");
                            print("[DEBUG] Note text: '$note'");
                            print("[DEBUG] Image path: $imagePath");

                            if (note.isNotEmpty) {
                              String notePath = path.withoutExtension(imagePath) + ".txt";
                              print("[DEBUG] Saving note at: $notePath");
                              File(notePath).writeAsStringSync(note); // No append here

                              addNote(imagePath, note);
                              print("[DEBUG] Note added to mediaNotesNotifier");
                            } else {
                              print("[DEBUG] Empty note. Nothing saved.");
                            }

                            Navigator.pop(context);
                          },

                          child: Text("OK"),
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

  void addNote(String imagePath, String noteText) {
    print("[DEBUG] addNote() called for $imagePath");
    final updatedNotes = Map<String, String>.from(mediaNotesNotifier.value);
    updatedNotes[imagePath] = noteText;
    mediaNotesNotifier.value = updatedNotes;
    print("[DEBUG] mediaNotesNotifier updated with ${updatedNotes.length} entries");
  }

  void saveNoteForImage(String imagePath, String note) {
    String notePath = imagePath.replaceAll(".jpg", ".txt");
    File(notePath).writeAsStringSync(note);
  }


// Helper Function to Build Icon Buttons
  Widget _buildIconButton(IconData icon, Color color, VoidCallback onPressed) {
    return IconButton(icon: Icon(icon, color: color), onPressed: onPressed);
  }

// Helper Function for Vertical Divider
  Widget _buildVerticalDivider() {
    return Container(height: 40, width: 1, color: Colors.grey.shade300);
  }

// Helper method to generate filename prefix
  String generateFileNamePrefix(DateTime now) {
    final String dateFormat = dateFormatNotifier.value;
    final String timeFormat = timeFormatNotifier.value;

    String datePart;
    switch (dateFormat) {
      case 'yyyy/mm/dd':
        datePart = '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}';
        break;
      case 'yy/mm/dd':
        datePart =
            '${now.year.toString().substring(2)}-${_twoDigits(now.month)}-${_twoDigits(now.day)}';
        break;
      case 'dd/mm/yy':
        datePart =
            '${_twoDigits(now.day)}-${_twoDigits(now.month)}-${now.year.toString().substring(2)}';
        break;
      case 'dd/mm/yyyy':
        datePart = '${_twoDigits(now.day)}-${_twoDigits(now.month)}-${now.year}';
        break;
      default:
        datePart = '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}';
    }

    String timePart;
    switch (timeFormat) {
      case '24h':
        timePart =
            '${_twoDigits(now.hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}';
        break;
      case 'am/pm':
        final hour = now.hour > 12 ? now.hour - 12 : now.hour;
        final ampm = now.hour < 12 ? 'am' : 'pm';
        timePart =
            '${_twoDigits(hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}$ampm';
        break;
      default:
        timePart =
            '${_twoDigits(now.hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}';
    }

    return '$datePart${timePart}';
  }

  String _twoDigits(int n) => n >= 10 ? '$n' : '0$n';
}

// Future<void> createRedTreeFolder() async {
//   if (await Permission.storage.request().isGranted) {
//     Directory? baseDir;
//
//     if (Platform.isAndroid) {
//       baseDir =
//           await getExternalStorageDirectory(); // This goes to /storage/emulated/0/Android/data/...
//     } else if (Platform.isIOS) {
//       baseDir = await getApplicationDocumentsDirectory(); // iOS-safe location
//     }
//
//     if (baseDir != null) {
//       final redTreeDir = Directory('${baseDir.path}/RedTree');
//       if (!(await redTreeDir.exists())) {
//         await redTreeDir.create(recursive: true);
//         print('📁 RedTree folder created at ${redTreeDir.path}');
//       } else {
//         print('📁 RedTree folder already exists.');
//       }
//     }
//   } else {
//     print('❌ Storage permission not granted.');
//   }
// }
