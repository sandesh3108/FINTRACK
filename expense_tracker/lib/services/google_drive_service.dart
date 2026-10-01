import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/errors/app_exception.dart';
import 'google_sheets_service.dart';

/// Read-only Google Drive access, used for exactly one job: finding the
/// spreadsheet this app wrote on another device or before a reinstall.
///
/// The Sheets API can open a spreadsheet by id but cannot list them, so after
/// the app's database is wiped there is nothing left to work out *which* sheet
/// to open - this is the search that answers that question.
///
/// Like [GoogleSheetsService] it only knows how to talk to Google: what a
/// result means belongs to the screen that asked for it. It takes a bearer
/// token from `GoogleAuthService` and never owns one.
class GoogleDriveService {
  /// Creates a client over [accessToken], or a real HTTP client in the app.
  GoogleDriveService({required this.accessToken, http.Client? client})
      : _client = client ?? http.Client();

  final String accessToken;
  final http.Client _client;

  static const String _host = 'www.googleapis.com';
  static const String _root = '/drive/v3';

  /// Mime type of a Google Sheet, which is what narrows the search to the
  /// files this app could ever have written.
  static const String _spreadsheetMime =
      'application/vnd.google-apps.spreadsheet';

  /// Upper bound on results, so a very large Drive cannot stall the screen.
  static const int _pageSize = 25;

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      };

  /// Spreadsheets in this account, newest first.
  ///
  /// [query] is an optional fragment of the title. Leaving it empty lists
  /// everything the token may see, which is the right default for a fresh
  /// install: there is no name to guess when the link left with the phone.
  Future<List<SheetReference>> findSpreadsheets({String query = ''}) async {
    final clauses = <String>[
      "mimeType='$_spreadsheetMime'",
      'trashed = false',
    ];
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) clauses.add("name contains '${_escape(trimmed)}'");

    final body = await _get(
      Uri.https(_host, '$_root/files', <String, String>{
        'q': clauses.join(' and '),
        'fields': 'files(id,name,modifiedTime)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '$_pageSize',
      }),
    );

    final files = body['files'];
    if (files is! List) return const <SheetReference>[];

    return <SheetReference>[
      for (final file in files)
        if (file is Map && file['id'] is String)
          SheetReference.fromId(
            file['id'] as String,
            title:
                file['name'] is String ? file['name'] as String : 'Spreadsheet',
          ),
    ];
  }

  /// Drive's filter syntax treats `'` as a delimiter, so a title containing one
  /// has to escape it rather than silently truncating the query.
  static String _escape(String value) => value.replaceAll("'", r"\'");

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers);
    } on SocketException {
      throw const OfflineException();
    } on http.ClientException {
      throw const OfflineException();
    }

    if (response.statusCode >= 400) {
      throw _failure(response.statusCode, response.body);
    }

    if (response.body.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  /// Turns an HTTP error into the one thing the person has to change.
  ///
  /// A refusal from Drive is almost always one of three things: the token was
  /// minted without the Drive scope, the API is off, or the account is not
  /// allowed to use this app yet - and each has a different fix.
  SheetsException _failure(int status, String body) {
    String? googleMessage;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final message = decoded['error']['message'];
        if (message is String && message.isNotEmpty) googleMessage = message;
      }
    } on FormatException {
      // Not JSON - only the status is usable.
    }

    final technical =
        'HTTP $status${googleMessage == null ? '' : ': $googleMessage'}';
    final lower = (googleMessage ?? '').toLowerCase();

    if (status == 401 ||
        lower.contains('insufficient authentication scopes') ||
        lower.contains('invalid_grant')) {
      return SheetsException(
        'Google has not been given permission to look through this Drive. '
        'In Google Cloud Console → OAuth consent screen → Scopes, add '
        'https://www.googleapis.com/auth/drive.readonly, save, then run '
        '*Find my spreadsheet* again.',
        technical: technical,
      );
    }
    if (status == 403) {
      return SheetsException(
        'Google refused to list this Drive. Enable the Google Drive API under '
        'APIs & Services → Library, and add your address under OAuth consent '
        'screen → Test users.',
        technical: technical,
      );
    }
    if (status == 429) {
      return SheetsException(
        'Google is limiting how often this app may talk to it. Wait a minute '
        'and try again.',
        technical: technical,
      );
    }
    return SheetsException(
      'Google Drive could not be searched.',
      technical: technical,
    );
  }
}
