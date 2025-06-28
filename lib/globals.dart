import 'package:RedTree/SearchIndex.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

final ValueNotifier<String> folderPathNotifier = ValueNotifier<String>('');
final ValueNotifier<String> fileNamingPrefixNotifier = ValueNotifier<String>('');
final ValueNotifier<String> dateFormatNotifier = ValueNotifier<String>('yyyy/mm/dd');
final ValueNotifier<String> timeFormatNotifier = ValueNotifier<String>('24h');
final ValueNotifier<bool> fileAspectEnabledNotifier = ValueNotifier<bool>(false);
final ValueNotifier<String> fileAspectNotifier = ValueNotifier('');
final ValueNotifier<double> rtBoxDelayNotifier = ValueNotifier(1.5);
final ValueNotifier<bool> isRedTreeActivatedNotifier = ValueNotifier(false);
void Function(double)? onDelayChangedGlobal = (newDelay) {
  rtBoxDelayNotifier.value = newDelay;
};

final ValueNotifier<Map<String, String>> mediaNotesNotifier = ValueNotifier({});
ValueNotifier<int> mediaReloadNotifier = ValueNotifier<int>(0);


ValueNotifier<String?> selectedFolderPathNotifier = ValueNotifier<String?>(null);
ValueNotifier<String> destinationFolderPathNotifier = ValueNotifier('');
ValueNotifier<String> languageNotifier = ValueNotifier('');
final ValueNotifier<String?> destinationFolderNotifier = ValueNotifier(null);
ValueNotifier<List<IndexedEntry>> searchableEntriesNotifier = ValueNotifier([]);
