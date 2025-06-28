import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomPopupTextButton extends StatelessWidget {
  final bool isEnabled;
  final List<String> options;
  final void Function(String) onSelected;
  final String enabledText;
  final String disabledText;
  final Color enabledColor;
  final Color disabledColor;
  final Color textColor;

  const CustomPopupTextButton({
    Key? key,
    required this.isEnabled,
    required this.options,
    required this.onSelected,
    this.enabledText = 'define',
    this.disabledText = 'define',
    this.enabledColor = Colors.black,
    this.disabledColor = Colors.grey,
    this.textColor = Colors.white,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: isEnabled ? enabledColor : disabledColor,
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
        shape: const RoundedRectangleBorder(),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: isEnabled
          ? () {
        final RenderBox button = context.findRenderObject() as RenderBox;
        final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;

        showMenu<String>(
          context: context,
          position: RelativeRect.fromRect(
            Rect.fromPoints(
              button.localToGlobal(Offset.zero, ancestor: overlay),
              button.localToGlobal(button.size.bottomRight(Offset.zero),
                  ancestor: overlay),
            ),
            Offset.zero & overlay.size,
          ),
          items: options.map((option) {
            return PopupMenuItem<String>(
              value: option,
              child: Text(option.tr),
            );
          }).toList(),
        ).then((value) {
          if (value != null) {
            onSelected(value);
          }
        });
      }
          : null,
      child: Text(
        isEnabled ? enabledText.tr : disabledText.tr,
        style: TextStyle(color: textColor),
      ),
    );
  }
}
