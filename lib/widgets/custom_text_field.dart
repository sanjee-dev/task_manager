import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.validator,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final String? Function(String?)? validator;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      validator: validator,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}
