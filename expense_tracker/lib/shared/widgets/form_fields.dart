import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../repositories/providers.dart';

/// Numeric amount input with the active currency symbol as a prefix.
///
/// Only digits, a decimal separator and grouping characters are accepted, and
/// the value is parsed with [parseMoneyToMinor] so no float ever touches money.
class AmountField extends ConsumerWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.autofocus = false,
    this.onChanged,
    this.errorText,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final symbol = ref.watch(currencySymbolProvider);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        LengthLimitingTextInputFormatter(12),
      ],
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixIcon: const Icon(Icons.currency_rupee_rounded),
        prefixText: '$symbol ',
        prefixStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
        hintText: '0.00',
      ),
    );
  }
}

/// Read-only field that opens the Material date picker.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return _PickerTile(
      icon: Icons.event_rounded,
      label: label,
      value: AppDates.dateLabel(value),
      errorText: errorText,
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(now.year - 30),
          lastDate: DateTime(now.year + 30),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// Read-only field that opens the Material time picker.
class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final String label;

  /// `HH:mm`.
  final String value;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final parts = value.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );

    return _PickerTile(
      icon: Icons.schedule_rounded,
      label: label,
      value: AppDates.timeLabel(value),
      errorText: errorText,
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.4,
            child: child!,
          ),
        );
        if (picked != null) {
          onChanged(
            '${picked.hour.toString().padLeft(2, '0')}:'
            '${picked.minute.toString().padLeft(2, '0')}',
          );
        }
      },
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.errorText,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          prefixIcon: Icon(icon, color: colors.primary),
        ),
        child: Text(value, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}

/// Parses [controller] into minor units, returning `null` when invalid.
int? readMinorAmount(TextEditingController controller) =>
    parseMoneyToMinor(controller.text);
