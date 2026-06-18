import 'package:flutter/material.dart';

/// IBM Carbon Design System tokens for Material 3 theme
/// Reference: https://carbon.ibm.com
class CarbonTokens {
  CarbonTokens._(); // Prevent instantiation

  /// Spacing system (8px base unit)
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  /// Border radius (Carbon uses subtle rounded corners)
  static const double radiusSmall = 4.0;
  static const double radiusMedium = 6.0;
  static const double radiusLarge = 8.0;

  /// Button sizes
  static const double buttonHeightSmall = 32.0;
  static const double buttonHeightDefault = 40.0;
  static const double buttonHeightLarge = 48.0;

  /// Semantic colors (Carbon palette)
  static const Color interactive = Color(0x0F62FE); // IBM Blue
  static const Color success = Color(0x24A148);
  static const Color warning = Color(0xF1C21B);
  static const Color error = Color(0xDA1E28);
  static const Color info = Color(0x0043CE);

  /// Typography scale (Carbon type scale)
  /// These should be used with TextTheme from Material 3
  /// which already provides a scale via GoogleFonts
}

/// Carbon-inspired button widget using Material 3
class CarbonButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final ButtonKind kind;
  final ButtonSize size;

  const CarbonButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.kind = ButtonKind.primary,
    this.size = ButtonSize.medium,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget child = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                kind == ButtonKind.primary
                    ? colorScheme.onPrimary
                    : colorScheme.primary,
              ),
            ),
          )
        : Text(label);

    final padding = _getPadding();
    final backgroundColor = _getBackgroundColor(colorScheme);
    final foregroundColor = _getForegroundColor(colorScheme);

    return switch (kind) {
      ButtonKind.primary => ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            padding: padding,
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CarbonTokens.radiusLarge),
            ),
            elevation: 0,
          ),
          child: child,
        ),
      ButtonKind.secondary => OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            padding: padding,
            side: BorderSide(
              color: colorScheme.primary,
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CarbonTokens.radiusLarge),
            ),
            foregroundColor: colorScheme.primary,
          ),
          child: child,
        ),
      ButtonKind.ghost => TextButton(
          onPressed: isLoading ? null : onPressed,
          style: TextButton.styleFrom(
            padding: padding,
            foregroundColor: colorScheme.primary,
          ),
          child: child,
        ),
      ButtonKind.danger => ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            padding: padding,
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CarbonTokens.radiusLarge),
            ),
            elevation: 0,
          ),
          child: child,
        ),
    };
  }

  EdgeInsets _getPadding() {
    return switch (size) {
      ButtonSize.small => const EdgeInsets.symmetric(
          horizontal: CarbonTokens.md,
          vertical: CarbonTokens.sm,
        ),
      ButtonSize.medium => const EdgeInsets.symmetric(
          horizontal: CarbonTokens.lg,
          vertical: CarbonTokens.md,
        ),
      ButtonSize.large => const EdgeInsets.symmetric(
          horizontal: CarbonTokens.xl,
          vertical: CarbonTokens.lg,
        ),
    };
  }

  Color _getBackgroundColor(ColorScheme colorScheme) {
    return switch (kind) {
      ButtonKind.primary => colorScheme.primary,
      ButtonKind.secondary => Colors.transparent,
      ButtonKind.ghost => Colors.transparent,
      ButtonKind.danger => colorScheme.error,
    };
  }

  Color _getForegroundColor(ColorScheme colorScheme) {
    return switch (kind) {
      ButtonKind.primary => colorScheme.onPrimary,
      ButtonKind.secondary => colorScheme.primary,
      ButtonKind.ghost => colorScheme.primary,
      ButtonKind.danger => colorScheme.onError,
    };
  }
}

enum ButtonKind { primary, secondary, ghost, danger }
enum ButtonSize { small, medium, large }

/// Carbon-inspired text input widget using Material 3
class CarbonTextInput extends StatefulWidget {
  final TextEditingController? controller;
  final String label;
  final String? placeholder;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool obscureText;
  final int? maxLength;
  final String? Function(String?)? validator;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFieldSubmitted;

  const CarbonTextInput({
    Key? key,
    this.controller,
    required this.label,
    this.placeholder,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.obscureText = false,
    this.maxLength,
    this.validator,
    this.errorText,
    this.onChanged,
    this.onFieldSubmitted,
  }) : super(key: key);

  @override
  State<CarbonTextInput> createState() => _CarbonTextInputState();
}

class _CarbonTextInputState extends State<CarbonTextInput> {
  late TextEditingController _controller;
  bool _showError = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorText ?? (widget.validator?.call(_controller.text));
    _showError = error != null;

    return TextFormField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.placeholder,
        errorText: error,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CarbonTokens.radiusLarge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CarbonTokens.radiusLarge),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CarbonTokens.radiusLarge),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CarbonTokens.radiusLarge),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CarbonTokens.radiusLarge),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.error,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: CarbonTokens.md,
          vertical: CarbonTokens.md,
        ),
      ),
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: widget.obscureText,
      maxLength: widget.maxLength,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: (_) => widget.onFieldSubmitted?.call(),
    );
  }
}

/// Carbon-inspired card using Material 3
class CarbonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool outlined;

  const CarbonCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(CarbonTokens.lg),
    this.outlined = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: outlined ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CarbonTokens.radiusLarge),
        side: outlined
            ? BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.2),
              )
            : BorderSide.none,
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
