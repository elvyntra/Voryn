import 'package:flutter/material.dart';

import '../../core/theme/voryn_theme.dart';

class VorynTextInput extends StatelessWidget {
  const VorynTextInput({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.isLoading = false,
    this.obscureText = false,
    this.errorText,
    this.textInputAction,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final bool isLoading;
  final bool obscureText;
  final String? errorText;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.vorynColors;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled && !isLoading,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: colors.accent,
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        errorText: errorText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: isLoading
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : suffixIcon,
      ),
    );
  }
}
