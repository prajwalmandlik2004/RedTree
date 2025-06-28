import 'package:flutter/material.dart';
import 'package:get/get.dart';

class RectangularDefineButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isEnabled;
  final String textKey;

  const RectangularDefineButton({
    Key? key,
    required this.onPressed,
    required this.isEnabled,
    this.textKey = 'define',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: isEnabled ? onPressed : null,
      style: TextButton.styleFrom(
        backgroundColor: isEnabled ? Colors.black : Colors.grey,
        padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 4.0),
        shape: const RoundedRectangleBorder(),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        textKey.tr,
        style: const TextStyle(
          color: Colors.white,
        ),
      ),
    );
  }
}
