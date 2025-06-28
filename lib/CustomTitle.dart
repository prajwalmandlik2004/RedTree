import 'package:flutter/material.dart';
import 'CustomDropdown.dart';

class CustomTitleRow extends StatelessWidget {
  final Text title;
  final Text subtitle;
  final List<String> popupOptions;
  final String currentValue;
  final ValueChanged<String> onOptionSelected;
  final bool switchValue;
  final ValueChanged<bool> onSwitchChanged;
  final bool isEnabled;

  const CustomTitleRow({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.popupOptions,
    required this.currentValue,
    required this.onOptionSelected,
    required this.switchValue,
    required this.onSwitchChanged,
    required this.isEnabled,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                flex: 35,
                child: title,
              ),

              // const Spacer(flex: 5),

              Expanded(
                flex: 30,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CustomPopupTextButton(
                    isEnabled: isEnabled,
                    options: popupOptions,
                    onSelected: onOptionSelected,
                  ),
                ),
              ),

              // Spacer
              const Spacer(flex: 5),

              Container(
                width: 1,
                height: 24,
                color: Colors.grey[400],
              ),

              // const Spacer(flex: 5),

              Expanded(
                flex: 25,
                child: Switch(
                  value: switchValue,
                  onChanged: isEnabled ? onSwitchChanged : null,
                  activeColor: Colors.blue,
                  activeTrackColor: Color.fromRGBO(215, 215, 215, 1.0),
                  inactiveTrackColor: Color.fromRGBO(215, 215, 215, 1.0),
                  inactiveThumbColor: Colors.white,
                ),
              ),
            ],
          ),
        ),

        // Subtitle
        Padding(
          padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: subtitle,
          ),
        ),

      ],
    );
  }
}