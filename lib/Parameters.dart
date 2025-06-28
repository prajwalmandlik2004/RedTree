import 'package:RedTree/FileManager.dart';
import 'package:RedTree/FileManager.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'CustomDropdown.dart';
import 'CustomTitle.dart';
import 'DirectoryButton.dart';
import 'globals.dart';

class ParametersScreen extends StatefulWidget {

  final Function(double) onDelayChanged;

  final CameraDescription camera;

  ParametersScreen({
    required this.onDelayChanged, required this.camera,
  });

  @override
  _ParametersScreenState createState() => _ParametersScreenState();
}

class _ParametersScreenState extends State<ParametersScreen> {

  late TextEditingController _delayController;

  final ValueNotifier<String> _languageNotifier = ValueNotifier('English');

  final ValueNotifier<bool> _formatPreferencesEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _folderPathEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _fileNamingEnabled = ValueNotifier<bool>(false);
  bool _isPrefixLoaded = true;


  bool _isSearching = false; // To toggle search interface
  final TextEditingController _searchController = TextEditingController();

  List<String> _items = [
    'activateRedTree',
    'rtBoxDelay',
    'fileNaming',
    'folderPath',
    'fileAspect',
    'formatPreferences',
  ];

  List<String> _filteredItems = [];


  final Map<String, Widget> _itemWidgets = {};

  @override
  void initState() {
    super.initState();
    fileNamingPrefixNotifier.addListener(_savePrefixToPrefs);
    folderPathNotifier.addListener(_saveFolderPathToPrefs);
    fileAspectNotifier.addListener(() async {
      await _saveFileAspectToPrefs(fileAspectNotifier.value);
    });

    fileAspectEnabledNotifier.addListener(() async {
      await _saveFileAspectEnabledToPrefs(fileAspectEnabledNotifier.value);
    });
    _loadPrefix();
    _loadSavedFolderPath();
    _loadSavedFileAspect();// Load previously saved preferences
    _loadSavedPreferences();

    // Listen to changes in languageNotifier and save to SharedPreferences
    _languageNotifier.addListener(() async {
      await _saveLanguageToPrefs(_languageNotifier.value);
    });

    // Listen to changes in dateFormatNotifier and save to SharedPreferences
    dateFormatNotifier.addListener(() async {
      await _saveDateFormatToPrefs(dateFormatNotifier.value);
    });

    // Listen to changes in timeFormatNotifier and save to SharedPreferences
    timeFormatNotifier.addListener(() async {
      await _saveTimeFormatToPrefs(timeFormatNotifier.value);
    });

    _delayController = TextEditingController(text: rtBoxDelayNotifier.value.toString());
    _filteredItems = _items;
    fileNamingPrefixNotifier.value = _generatePrefixFromDateFormat(dateFormatNotifier.value);

    // Initialize the map with items and their corresponding widgets
    _itemWidgets['activateRedTree'] = ValueListenableBuilder<bool>(
      valueListenable: isRedTreeActivatedNotifier,
      builder: (context, isRedTreeActivated, child) {
        return ListTile(
          title: Text('activateRedTree'.tr,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 18,
                color: isRedTreeActivated ? Colors.black : Colors.grey,
              )),
          subtitle: Text(
            isRedTreeActivated
                ? 'redTreeDefaultSettings'.tr
                : 'redTreeDefaultSettings'.tr, // you may differentiate if needed
            style: TextStyle(
              fontSize: 12,
              color: isRedTreeActivated ? Colors.black : Colors.grey,
            ),
          ),
          trailing: Switch(
            value: isRedTreeActivated,
            onChanged: (value) async {
              isRedTreeActivatedNotifier.value = value;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('redtree', value);
              setState(() {
                isRedTreeActivatedNotifier.value = value;
              });
            },
            activeColor: Colors.blue,
            activeTrackColor: const Color.fromRGBO(215, 215, 215, 1.0),
            inactiveTrackColor: const Color.fromRGBO(215, 215, 215, 1.0),
            inactiveThumbColor: Colors.white,
          ),
        );
      },
    );


    _itemWidgets['rtBoxDelay'] = ValueListenableBuilder<bool>(
      valueListenable: isRedTreeActivatedNotifier,
      builder: (context, isRedTreeActivated, child) {
        return ValueListenableBuilder(
          valueListenable: rtBoxDelayNotifier,
          builder: (context, rtBoxDelay, _) {
            _delayController.text = rtBoxDelay.toString();
            return ListTile(
              title: Text('rtBoxDelay'.tr,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                    color: isRedTreeActivated ? Colors.black : Colors.grey,
                  )),
              subtitle: Text(
                'timeBeforeOpeningRTbox'.tr,
                style: TextStyle(
                  color: isRedTreeActivated ? Colors.blue : Colors.grey,
                ),
              ),
              trailing: SizedBox(
                width: 100,
                child: TextField(
                  style: TextStyle(
                    color: isRedTreeActivated ? Colors.blue : Colors.grey,
                  ),
                  controller: _delayController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    suffixText: "(sec)",
                    suffixStyle: const TextStyle(fontSize: 14),
                    enabled: isRedTreeActivated,
                  ),
                  onChanged: null,
                  onEditingComplete: isRedTreeActivated
                      ? () async {
                    final value = double.tryParse(_delayController.text);
                    final prefs = await SharedPreferences.getInstance();
                    if (value != null) {
                      rtBoxDelayNotifier.value = value;
                      await prefs.setDouble('rtBoxDelay', value);
                      widget.onDelayChanged(value);
                    } else {
                      rtBoxDelayNotifier.value = 1.5;
                      await prefs.setDouble('rtBoxDelay', 1.5);
                      _delayController.text = "1.5";
                    }
                  }
                      : null,
                ),
              ),
            );
          },
        );
      },
    );


    _itemWidgets['fileNaming'] = ValueListenableBuilder<bool>(
      valueListenable: isRedTreeActivatedNotifier,
      builder: (context, isRedTreeActive, _) {
        return ValueListenableBuilder<String>(
          valueListenable: fileNamingPrefixNotifier,
          builder: (context, prefix, _) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 35,
                        child: Text(
                          "fileNaming".tr,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 18,
                            color: isRedTreeActive ? Colors.black : Colors.grey,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 25,
                        child: RectangularDefineButton(
                          onPressed: isRedTreeActive
                              ? () => _showPrefixDialog(context)
                              : null,
                          isEnabled: isRedTreeActive,
                        ),
                      ),
                      const Spacer(flex: 5),
                      Container(
                        width: 1,
                        height: 24,
                        color: Colors.grey[400],
                      ),
                      Expanded(
                        flex: 25,
                        child: ValueListenableBuilder(
                          valueListenable: _fileNamingEnabled,
                          builder: (context, isFileNamingEnabled, _) {
                            return Switch(
                              value: isFileNamingEnabled,
                              onChanged: isRedTreeActive
                                  ? (value) => _fileNamingEnabled.value = value
                                  : null,
                              activeColor: Colors.blue,
                              activeTrackColor: const Color.fromRGBO(215, 215, 215, 1.0),
                              inactiveTrackColor: const Color.fromRGBO(215, 215, 215, 1.0),
                              inactiveThumbColor: Colors.white,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "yourPresentPrefix".tr,
                      style: TextStyle(
                        fontSize: 14,
                        color: isRedTreeActive ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      prefix.tr,
                      style: TextStyle(
                        fontSize: 14,
                        color: isRedTreeActive ? Colors.blue : Colors.grey,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );


    _itemWidgets['folderPath'] = ValueListenableBuilder<bool>(
      valueListenable: isRedTreeActivatedNotifier,
      builder: (context, isRedTreeActive, _) {
        return ValueListenableBuilder<String>(
          valueListenable: folderPathNotifier,
          builder: (context, folderPath, _) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 35,
                        child: Text(
                          "folderPath".tr,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 18,
                            color: isRedTreeActive ? Colors.black : Colors.grey,
                          ),
                        ),
                      ),
                      // const Spacer(flex: 5),
                      Expanded(
                        flex: 25,
                        child: RectangularDefineButton(
                          onPressed: isRedTreeActive
                              ? () async {
                            final selectedFolder = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FileManager(
                                  showCancelBtn: true,
                                  updateFolderPath: true,
                                ),
                              ),
                            );
                            if (selectedFolder != null) {
                              folderPathNotifier.value = selectedFolder;
                              print("Selected folder updated: $selectedFolder");
                            }
                          }
                              : null,
                          isEnabled: isRedTreeActive,
                        ),
                      ),
                      const Spacer(flex: 5),
                      Container(
                        width: 1,
                        height: 24,
                        color: Colors.grey[400],
                      ),
                      // const Spacer(flex: 5),
                      Expanded(
                        flex: 25,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _folderPathEnabled,
                          builder: (context, isFolderPathEnabled, _) {
                            return Switch(
                              value: isFolderPathEnabled,
                              onChanged: isRedTreeActive
                                  ? (value) => _folderPathEnabled.value = value
                                  : null,
                              activeColor: Colors.blue,
                              activeTrackColor: const Color.fromRGBO(215, 215, 215, 1.0),
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: const Color.fromRGBO(215, 215, 215, 1.0),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "yourPresentDesignatedFolder".tr,
                      style: TextStyle(
                        fontSize: 14,
                        color: isRedTreeActive ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      folderPath,
                      style: TextStyle(
                        fontSize: 14,
                        color: isRedTreeActive ? Colors.blue : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );


    _itemWidgets['fileAspect'] = ValueListenableBuilder<bool>(
      valueListenable: isRedTreeActivatedNotifier,
      builder: (context, isRedTreeActive, _) {
        return ValueListenableBuilder<String>(
          valueListenable: fileAspectNotifier, // this will now be a key like 'smallImage'
          builder: (context, fileAspectKey, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: fileAspectEnabledNotifier,
              builder: (context, isAspectEnabled, _) {
                return CustomTitleRow(
                  title: Text(
                    'fileAspect'.tr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: isRedTreeActive ? Colors.black : Colors.grey,
                    ),
                  ),
                  subtitle: Text(
                    '${'yourPresentDesignatedFile'.tr}: ${fileAspectKey.tr}', // apply tr here
                    style: TextStyle(
                      fontSize: 14,
                      color: isRedTreeActive ? Colors.black : Colors.grey,
                    ),
                  ),
                  popupOptions: [
                    'smallImage'.tr,
                    'midImage'.tr,
                    'largeImage'.tr,
                  ],
                  currentValue: fileAspectKey.tr,

                  onOptionSelected: (selectedTranslatedValue) async {
                    // Create a bidirectional map for translations
                    final aspectMap = {
                      'smallImage': 'smallImage'.tr,
                      'midImage': 'midImage'.tr,
                      'largeImage': 'largeImage'.tr,
                    };

                    final rawKey = aspectMap.entries
                        .firstWhere(
                          (entry) => entry.value == selectedTranslatedValue,
                      orElse: () => MapEntry('smallImage', 'smallImage'.tr),
                    )
                        .key;

                    // Update and persist the value
                    fileAspectNotifier.value = rawKey;
                    await _saveFileAspectToPrefs(rawKey);

                    // Force a media reload
                    mediaReloadNotifier.value++;
                  },
                  switchValue: isAspectEnabled,
                  onSwitchChanged: (value) => fileAspectEnabledNotifier.value = value,
                  isEnabled: isRedTreeActive,
                );
              },
            );
          },
        );
      },
    );



    _itemWidgets['formatPreferences'] = ValueListenableBuilder<bool>(
      valueListenable: isRedTreeActivatedNotifier,
      builder: (context, isRedTreeActivated, child) {
        return Column(
          children: [
            ListTile(
              title: Text('formatPreferences'.tr,
                  style: TextStyle(
                      color: isRedTreeActivated ? Colors.black : Colors.grey,
                      fontWeight: FontWeight.w500,
                      fontSize: 18)),
              trailing: ValueListenableBuilder<bool>(
                valueListenable: _formatPreferencesEnabled,
                builder: (context, isFormatPreferencesEnabled, _) {
                  return Switch(
                    value: isFormatPreferencesEnabled,
                    onChanged: isRedTreeActivated
                        ? (value) => _formatPreferencesEnabled.value = value
                        : null,
                    activeColor: Colors.blue,
                    activeTrackColor: const Color.fromRGBO(215, 215, 215, 1.0),
                    inactiveTrackColor: const Color.fromRGBO(215, 215, 215, 1.0),
                    inactiveThumbColor: Colors.white,
                  );
                },
              ),
            ),
            ListTile(
              subtitle: Column(
                children: [

                  ValueListenableBuilder<String>(
                    valueListenable: languageNotifier,
                    builder: (context, currentLangCode, _) {
                      // Map language codes to their display names
                      final langDisplayMap = {
                        'en': 'english'.tr,  // Will show "English"
                        'fr': 'french'.tr,   // Will show "French"
                        'de': 'german'.tr,   // Will show "German"
                        'es': 'spanish'.tr,  // Will show "Spanish"
                        'hi': 'hindi'.tr,    // Will show "Hindi"
                      };

                      // Create list of available language display names
                      final languageOptions = ['english'.tr, 'french'.tr, 'german'.tr, 'spanish'.tr, 'hindi'.tr];

                      return _buildPreferenceRow(
                        context,
                        label: 'language'.tr,
                        value: langDisplayMap[currentLangCode] ?? 'english'.tr,
                        isEnabled: isRedTreeActivated,
                        options: languageOptions,
                        onSelected: (selectedDisplayName) async {
                          // Create reverse mapping from display name to language code
                          final displayToLangCodeMap = {
                            'english'.tr: 'en',
                            'french'.tr: 'fr',
                            'german'.tr: 'de',
                            'spanish'.tr: 'es',
                            'hindi'.tr: 'hi',
                          };

                          final selectedLangCode = displayToLangCodeMap[selectedDisplayName] ?? 'en';

                          languageNotifier.value = selectedLangCode;
                          await _saveLanguageToPrefs(selectedLangCode);
                          Get.updateLocale(Locale(selectedLangCode));
                        },
                      );
                    },
                  ),

                  // Date Format Row
                  ValueListenableBuilder<String>(
                    valueListenable: dateFormatNotifier,
                    builder: (context, currentDateFormat, _) {
                      return _buildPreferenceRow(
                        context,
                        label: 'date'.tr,
                        value: currentDateFormat.tr,
                        isEnabled: isRedTreeActivated,
                        options: [
                          'format_yyyy_mm_dd',
                          'format_yy_mm_dd',
                          'format_dd_mm_yy',
                          'format_dd_mm_yyyy'
                        ].map((key) => key.tr).toList(),
                        onSelected: (selectedTrValue) {
                          final rawValue = {
                            'format_yyyy_mm_dd': 'yyyy/mm/dd',
                            'format_yy_mm_dd': 'yy/mm/dd',
                            'format_dd_mm_yy': 'dd/mm/yy',
                            'format_dd_mm_yyyy': 'dd/mm/yyyy'
                          }.entries.firstWhere(
                                (entry) => entry.key.tr == selectedTrValue,
                            orElse: () => const MapEntry('format_yyyy_mm_dd', 'yyyy/mm/dd'),
                          ).value;

                          dateFormatNotifier.value = rawValue;
                          _saveDateFormatToPrefs(rawValue);
                          fileNamingPrefixNotifier.value = _generatePrefixFromDateFormat(rawValue);
                        },
                      );
                    },
                  ),

                  // Time Format Row
                  ValueListenableBuilder<String>(
                    valueListenable: timeFormatNotifier,
                    builder: (context, currentTimeFormat, _) {
                      return _buildPreferenceRow(
                        context,
                        label: 'time'.tr,
                        value: currentTimeFormat.tr,
                        isEnabled: isRedTreeActivated,
                        options: ['format24h', 'formatAMPM'].map((k) => k.tr).toList(),
                        onSelected: (selectedTrValue) {
                          final rawValue = selectedTrValue == 'formatAMPM'.tr ? 'am/pm' : '24h';
                          timeFormatNotifier.value = rawValue;
                          _saveTimeFormatToPrefs(rawValue);
                        },
                      );
                    },
                  ),
                ],
              ),
            )
          ],
        );
      },
    );

  }

  @override
  void dispose() {
    _delayController.dispose(); // Dispose the controller
    _searchController.dispose(); // Dispose the search controller
    _languageNotifier.dispose();
    fileNamingPrefixNotifier.removeListener(_savePrefixToPrefs);
    folderPathNotifier.removeListener(_saveFolderPathToPrefs);

    super.dispose();
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // Load saved language
    String? savedLanguage = prefs.getString('language');
    if (savedLanguage != null) {
      _languageNotifier.value = savedLanguage;
    }

    // Load saved date format
    String? savedDateFormat = prefs.getString('dateFormat');
    if (savedDateFormat != null) {
      dateFormatNotifier.value = savedDateFormat;
    }

    // Load saved time format
    String? savedTimeFormat = prefs.getString('timeFormat');
    if (savedTimeFormat != null) {
      timeFormatNotifier.value = savedTimeFormat;
    }
  }

  // Method to save selected language to SharedPreferences
  Future<void> _saveLanguageToPrefs(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', languageCode);
  }

// Method to save selected date format to SharedPreferences
  Future<void> _saveDateFormatToPrefs(String dateFormat) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dateFormat', dateFormat);
    print('Auto-saved new date format: $dateFormat');
  }

// Method to save selected time format to SharedPreferences
  Future<void> _saveTimeFormatToPrefs(String timeFormat) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('timeFormat', timeFormat);
    print('Auto-saved new time format: $timeFormat');
  }

  Future<void> _saveFileAspectToPrefs(String fileAspectKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fileAspect', fileAspectKey); // Don't use `.tr` here
    print('Auto-saved new file aspect key: $fileAspectKey');
  }


// Method to save file aspect enabled status to SharedPreferences
  Future<void> _saveFileAspectEnabledToPrefs(bool isEnabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('fileAspectEnabled', isEnabled);
    print('Auto-saved new file aspect enabled status: $isEnabled');
  }

  Future<void> _loadSavedFileAspect() async {
    final prefs = await SharedPreferences.getInstance();

    String? savedKey = prefs.getString('fileAspect');
    if (savedKey != null) {
      fileAspectNotifier.value = savedKey; // Use raw key, not translated
    }

    bool? savedFileAspectEnabled = prefs.getBool('fileAspectEnabled');
    if (savedFileAspectEnabled != null) {
      fileAspectEnabledNotifier.value = savedFileAspectEnabled;
    }
  }


  Future<void> _saveFolderPathToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('folderPath', folderPathNotifier.value);
    print('Auto-saved new folder path: ${folderPathNotifier.value}');
  }

// Optional: Load saved folder path if it exists
  Future<void> _loadSavedFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedFolderPath = prefs.getString('folderPath');
    if (savedFolderPath != null) {
      folderPathNotifier.value = savedFolderPath;
    }
  }
  Future<void> _loadPrefix() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPrefix = prefs.getString('fileNamingPrefix');

    if (savedPrefix != null && savedPrefix.isNotEmpty) {
      fileNamingPrefixNotifier.value = savedPrefix;
    }

    setState(() {
      _isPrefixLoaded = true;
    });
  }

  void _savePrefixToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fileNamingPrefix', fileNamingPrefixNotifier.value);
    print('Auto-saved prefix: ${fileNamingPrefixNotifier.value}');
  }
  void _filterItems(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredItems = _items;
      });
    } else {
      final lowerQuery = query.toLowerCase();
      setState(() {
        _filteredItems = _items.where((itemKey) {
          final translated = itemKey.tr.toLowerCase();
          return translated.contains(lowerQuery);
        }).toList();
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        shadowColor: Colors.grey,
        title: _isSearching
            ? TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'searchHint'.tr, // Translated
            border: InputBorder.none,
            hintStyle: const TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.black),
          onChanged: _filterItems,
        )
            : Text('parameters'.tr), // Translated
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _filterItems('');
                }
              });
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _filteredItems.map((itemKey) {
          return Column(
            children: [
              _itemWidgets[itemKey]!,
              const Divider(),
            ],
          );
        }).toList(),
      ),
    );
  }



  Future<String?> _showPrefixDialog(BuildContext context) async {
    final controller = TextEditingController(text: fileNamingPrefixNotifier.value);

    final newPrefix = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('setFileNamingPrefix'.tr),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'prefix'.tr,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('save'.tr),
          ),
        ],
      ),
    );

    if (newPrefix != null && newPrefix.isNotEmpty) {
      fileNamingPrefixNotifier.value = newPrefix;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fileNamingPrefix', newPrefix);
    }

    return newPrefix;
  }

}

String _generatePrefixFromDateFormat(String dateFormat) {
  switch (dateFormat) {
    case 'yyyy/mm/dd':
      return 'yyyy/mm/ddhhmmss';
    case 'yy/mm/dd':
      return 'yy/mm/ddhhmmss';
    case 'dd/mm/yy':
      return 'dd/mm/yyhhmmss';
    case 'dd/mm/yyyy':
      return 'dd/mm/yyyyhhmmss';
    default:
      return 'yyyy/mm/dd';
  }
}

Widget _buildPreferenceRow(
    BuildContext context, {
      required String label,
      required String value,
      required bool isEnabled,
      required List<String> options,
      required Function(String) onSelected,
    }) {
  // return Padding(
  //   padding: const EdgeInsets.only(bottom: 2),
  //   child: Row(
  //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
  //     children: [
  //       SizedBox(
  //         width: 90,
  //         child: Text(
  //           label.tr, // Translate label
  //           style: TextStyle(
  //             fontWeight: FontWeight.bold,
  //             color: isEnabled ? Colors.black : Colors.grey,
  //           ),
  //         ),
  //       ),
  //       Row(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Text(
  //             value.tr, // Translate current value
  //             style: TextStyle(color: isEnabled ? Colors.black : Colors.grey),
  //           ),
  //         ],
  //       ),
  //       Padding(
  //         padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
  //         child: CustomPopupTextButton(
  //           isEnabled: isEnabled,
  //           options: options.map((e) => e.tr).toList(), // Translate each option
  //           onSelected: onSelected,
  //           enabledText: 'define'.tr,
  //           disabledText: 'modify'.tr,
  //         ),
  //       )
  //     ],
  //   ),
  // );
  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      children: [
        // Label (25%)
        Expanded(
          flex: 25,
          child: Text(
            label.tr,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isEnabled ? Colors.black : Colors.grey,
            ),
          ),
        ),

        const SizedBox(width: 8), // spacing

        // Value (25%)
        Expanded(
          flex: 25,
          child: Text(
            value.tr,
            style: TextStyle(color: isEnabled ? Colors.black : Colors.grey),
          ),
        ),

        const SizedBox(width: 8), // spacing

        // Button (30%)
        Expanded(
          flex: 25,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
            child: CustomPopupTextButton(
              isEnabled: isEnabled,
              options: options.map((e) => e.tr).toList(),
              onSelected: onSelected,
              enabledText: 'define'.tr,
              disabledText: 'modify'.tr,
            ),
          ),
        ),
      ],
    ),
  );

}

