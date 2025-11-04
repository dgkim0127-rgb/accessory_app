// lib/widgets/progress_button.dart
import 'package:flutter/material.dart';

class ProgressButton extends StatelessWidget {
  final String label;
  final double? progress; // null=idle, 0..1=running
  final VoidCallback? onPressed;
  final double height;

  const ProgressButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.progress,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    const line = Color(0xffe6e6e6);
    final isLoading = progress != null;
    final pct = ((progress ?? 0) * 100).clamp(0, 100).toStringAsFixed(0);

    return SizedBox(
      height: height,
      child: Material(
        color: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: line),
        ),
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isLoading)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (progress ?? 0).clamp(0, 1),
                    child: Container(color: Colors.black),
                  ),
                ),
              Center(
                child: Text(
                  isLoading ? '$label $pct%' : label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isLoading ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 앱바용 텍스트 액션 (퍼센트만 붙여서 보여줌)
class ProgressTextAction extends StatelessWidget {
  final String label;
  final double? progress;
  final VoidCallback? onPressed;

  const ProgressTextAction({
    super.key,
    required this.label,
    this.progress,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = progress != null;
    final pct = ((progress ?? 0) * 100).clamp(0, 100).toStringAsFixed(0);
    return TextButton(
      onPressed: isLoading ? null : onPressed,
      child: Text(
        isLoading ? '$label $pct%' : label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
