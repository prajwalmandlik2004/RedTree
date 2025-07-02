import 'package:RedTree/note_utils.dart';
import 'package:RedTree/translations.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:overlay_support/overlay_support.dart';
import 'FileManager.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'Parameters.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'globals.dart';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  final dateFormatNotifier = ValueNotifier<String>('yyyy/mm/dd');
  final timeFormatNotifier = ValueNotifier<String>('24h');


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
  final savedLangCode = prefs.getString('languageCode') ?? 'en';

  languageNotifier.value = savedLangCode;
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
          translations: AppTranslations(),
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
  VideoPlayerController? _videoController;
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  late stt.SpeechToText _speech;
  bool _isListening = false;
  XFile? _videoFile;

  AppLifecycleState? _appLifecycleState;
  bool _isCameraPaused = false;
  bool _isAppInForeground = true;
  bool _needsFullRestart = false;

  bool _isRestarting = false;
  bool _showTempPreview = false;
  File? _lastCapturedImage;

  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _showFrozenImage = false;
  File? _frozenImageFile;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _initCamera();

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
      _needsFullRestart = true;
    } else if (state == AppLifecycleState.resumed) {
      if (_needsFullRestart) {
        restartCamera();
      } else {
        _resumeCamera();
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
        _initCamera();
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
      await _initCamera();
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
      resizeToAvoidBottomInset: false,

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
            final cameraAspectRatio = size.height / size.width;

            return Stack(
              children: [


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
                                final video = await _controller?.stopVideoRecording();
                                setState(() {
                                  _videoFile = video;
                                  _isRecording = false;
                                });

                                _videoController = VideoPlayerController.file(File(video!.path))
                                  ..initialize().then((_) {
                                    setState(() {});
                                    _videoController?.play();
                                  });

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
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    restartCamera();
                                  });
                                }

                              } else {
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
                              await _initializeControllerFuture;
                              await _controller?.setFlashMode(FlashMode.off);


                              final image = await _controller?.takePicture();

                              try {
                                await _audioPlayer.play(AssetSource('sounds/shutter.mp3'));
                              } catch (e) {
                                debugPrint("❌ Failed to play shutter sound: $e");
                              }

                              final imageFile = File(image!.path);

                              setState(() {
                                _capturedImagePath = image.path;
                                _isImageFrozen = true;

                              });


                              if (isRedTreeActivatedNotifier.value) {
                                await Future.delayed(
                                  Duration(milliseconds: (rtBoxDelayNotifier.value * 1000).toInt()),
                                );
                                _showImageSettingsPopup(context, image.path, extension: 'jpg');
                              } else {
                                final now = DateTime.now();
                                final fileName = '${generateFileNamePrefix(now)}.jpg';
                                final cameraDir = Directory('/storage/emulated/0/DCIM');
                                final savePath = '${cameraDir.path}/$fileName';

                                try {

                                  await imageFile.copy(savePath);
                                  Fluttertoast.showToast(msg: "Image saved successfully");

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


  Future<void> restartCamera() async {
    if (!mounted || _isRestarting) return;
    _isRestarting = true;

    try {
      if (_controller?.value.isInitialized == true && _lastCapturedImage != null) {
        setState(() {
          _showFrozenImage = true;
          _frozenImageFile = _lastCapturedImage;
        });
      }

      await _controller?.dispose();
      _isImageFrozen = false;

      _controller = CameraController(
        widget.camera,
        ResolutionPreset.ultraHigh,
        enableAudio: true,
      );

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


    try {

      _isImageFrozen = false;

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera restart error: $e");
    } finally {
      _isRestarting = false;
    }
  }



  Future<void> _showImageSettingsPopup(BuildContext context, String filePath, {required String extension}) async {
    final now = DateTime.now();


    String prefix = generateFileNamePrefix(now);
    String fileName = prefix;
    String selectedFolderPath =
        folderPathNotifier.value;
    final TextEditingController fileNameController =
        TextEditingController(text: fileName);
    ValueNotifier<bool> isOkEnabled = ValueNotifier(false);
    final ValueNotifier<String?> _temporarySelectedFolderPath = ValueNotifier(null); // 🔸


    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero),
              contentPadding: EdgeInsets.zero,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                                          final spokenName = result.recognizedWords.replaceAll(' ', '_');
                                          fileNameController.text = spokenName;
                                          fileName = spokenName;
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

                  Divider(thickness: 1, height: 1),

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
                            File(filePath).copySync(savePath);

                            String oldNotePath = path.withoutExtension(filePath) + ".txt";
                            String newNotePath = path.withoutExtension(savePath) + ".txt";

                            if (File(oldNotePath).existsSync()) {
                              File(oldNotePath).copySync(newNotePath);
                              debugPrint("Note copied from $oldNotePath to $newNotePath");

                              String note = File(newNotePath).readAsStringSync();
                              final updatedNotes = Map<String, String>.from(mediaNotesNotifier.value);
                              updatedNotes[savePath] = note;
                              mediaNotesNotifier.value = updatedNotes;
                            }
                            Fluttertoast.showToast(msg: "Image saved successfully to: $savePath");

                            _isImageFrozen = true;
                            await _restartCameraSmoothly();
                            Navigator.pop(context);

                          } catch (e) {
                            Fluttertoast.showToast(msg:"Save failed: ${e.toString()}");
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
                          selectedFolderPath = selectedFolder;
                          _temporarySelectedFolderPath.value = selectedFolder;

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

      _isImageFrozen = false;

    }

    Future<void> _saveToLDF(BuildContext context, String path, {required String extension}) async {
      final now = DateTime.now();


      String prefix = generateFileNamePrefix(now);
      String fileName = prefix;
      String selectedFolderPath =
          folderPathNotifier.value;

      String savePath = "$selectedFolderPath/$fileName.$extension";
      File(path).copySync(savePath);

      await _restartCameraSmoothly();

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


  Widget _buildIconButton(IconData icon, Color color, VoidCallback onPressed) {
    return IconButton(icon: Icon(icon, color: color), onPressed: onPressed);
  }

  Widget _buildVerticalDivider() {
    return Container(height: 40, width: 1, color: Colors.grey.shade300);
  }

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
