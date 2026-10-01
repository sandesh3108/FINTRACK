import '../../core/config/app_config.dart';

/// Build-time contact channels for the Contact and About screens.
///
/// [AppConfig] carries the support e-mail address; the phone number and the
/// privacy policy document are supplied with `--dart-define` in exactly the
/// same way (see `AppConfig` for why secrets never go here). A channel the
/// build does not configure stays empty - and the screen hides it rather than
/// offering a dead link.
class ContactChannels {
  const ContactChannels._();

  /// Phone number in international format, e.g. `+911234567890`.
  ///
  /// Empty by default: the card is only offered when the build configured one.
  static const String phone = String.fromEnvironment('CONTACT_PHONE');

  /// Published privacy policy document. Empty means "not published yet".
  static const String privacyPolicyUrl =
      String.fromEnvironment('PRIVACY_POLICY_URL');

  /// Support / contact e-mail address.
  static String get email => AppConfig.supportEmail;

  /// True when at least one channel can be offered to the user.
  static bool get hasAnyChannel => email.isNotEmpty || phone.isNotEmpty;

  /// WhatsApp chat derived from [phone], or `null` when no number is set.
  ///
  /// `wa.me` accepts the digits of the international number only, so every
  /// separator is stripped before the link is built.
  static String? get whatsappUrl {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return 'https://wa.me/$digits';
  }
}
