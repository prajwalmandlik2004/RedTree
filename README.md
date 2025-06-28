RedTree Changes and Features

[// Try -> When clicked on Close Icon, don't create new controller - just show image frozen = false --- WORKING ]
1. Capture modal madhe “X” and Delete wala icon var click kela ki screen blink hoti te blink nahi zala pahije normal camera ready zala pahije



[// --- WORKING ]
3. File Aspect Notifier not working as expected



[// Done But Need To Check --- WORKING ]--------------------
4. Change language_english ..... etc to English, Spanish, etc



[// Done But Need To Check --- WORKING ]--------------------
5. If Folder in Folder path is moved, show error



[// --- WORKING ]
7. Show Proper Background Color, on Tapped Node. 


[// --- WORKING ]
8. When in MultiSelectMode, while the operation is being performed - Give User a Feedback until operation is over.



[// --- WORKING ]
10. Ani folder and image sathi je rename modal ahe tyamadhe ek “Move” cha option add kar so tithun pan move karta ali pahije RedTree file manager la 



[// --- WORKING ]
6. When MOVE Operation is performed on FIlE, only the Destination Folder is rendered in TreeView. Same Goes For FOLDER MOVE as well.



[// --- WORKING ]
12. While Moving , Not able to select sub-folders.




[ 4 ]
2. Search feature in Redtree file manager

[ 1 ]
9. When MultiSelectMode Operation is over, render Tree Properly.

[ 3 ]
11. Keep the Folders open by default when re-opening the app.




// MOVE -----------

- For FOLDER MOVE , Methods Used : _confirmAndMove , _executeMoveOperation
-  if (isDirectory) {
   await _moveDirectory(Directory(sourcePath), Directory(newPath));
   } else {
   await FileUtils.moveFileTo(context, File(sourcePath), destinationPath);
   }



- For FILE MOVE , Methods Used : _showDestinationConfirmation , 