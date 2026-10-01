import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/balance_pin.dart';

/// Prompts for the numeric PIN that guards the account balances.
///
/// Returns the PIN the user entered, or `null` when the dialog was dismissed
/// without saving - the caller can tell "cancelled" from "typed something".
/// The value only leaves here once [BalancePin.validate] (and, when [confirm]
/// is set, a second identical entry) has accepted it, so a caller never has to
/// re-check the format.
///
/// Shared by Settings - where the PIN is chosen - and the Accounts screen,
/// where it is asked for, so both look and behave identically.
Future<String?> showPinDialog(
  BuildContext context, {
  required String title,
  String message = '',
  bool confirm = false,
  String confirmLabel = 'OK',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PinDialog(
      title: title,
      message: message,
      confirm: confirm,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({
    required this.title,
    required this.message,
    required this.confirm,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final bool confirm;
  final String confirmLabel;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  late final TextEditingController _pin;
  late final TextEditingController _again;
  String? _error;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _pin = TextEditingController();
    _again = TextEditingController();
  }

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _pin.text.trim();
    final format = BalancePin.validate(value);
    if (format != null) {
      setState(() => _error = format);
      return;
    }
    if (widget.confirm && _again.text.trim() != value) {
      setState(() => _error = 'The two PINs do not match.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message.isNotEmpty) ...[
            Text(
              widget.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _field(
            controller: _pin,
            label: 'PIN',
            error: _error,
            onSubmitted: widget.confirm ? null : (_) => _submit(),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 12),
            _field(
              controller: _again,
              label: 'Repeat PIN',
              onSubmitted: (_) => _submit(),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }

  /// One PIN entry line. Digits are forced by the formatter, so the common
  /// mistake - a letter or a space - cannot even be typed; [BalancePin]
  /// still checks the length because a formatter cannot.
  Widget _field({
    required TextEditingController controller,
    required String label,
    required ValueChanged<String>? onSubmitted,
    String? error,
  }) {
    return TextField(
      controller: controller,
      autofocus: true,
      obscureText: !_visible,
      obscuringCharacter: '•',
      keyboardType: TextInputType.number,
      textInputAction: widget.confirm ? TextInputAction.next : TextInputAction.done,
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        hintText: List<String>.filled(BalancePin.minLength, '\u2022').join(),
        errorText: error,
        suffixIcon: IconButton(
          tooltip: _visible ? 'Hide PIN' : 'Show PIN',
          icon: Icon(_visible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
      onSubmitted: onSubmitted,
    );
  }
}
