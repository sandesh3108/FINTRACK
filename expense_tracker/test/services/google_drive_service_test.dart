import 'dart:convert';

import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/services/google_drive_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Captures the request that was actually sent, so the query Google would
/// receive can be asserted on rather than only the parsed answer.
class _FakeClient extends http.BaseClient {
  _FakeClient(this._reply);

  final Future<http.Response> Function(http.Request request) _reply;

  http.Request? last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    last = request as http.Request;
    final response = await _reply(last!);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
    );
  }
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  /// Google only ever sees spreadsheets: the mime type is what stops the
  /// search returning every other file in the account.
  test('asks Drive for spreadsheets only, newest first', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{
          'files': <Object>[
            <String, Object>{'id': 'abc123', 'name': 'FINTRACK'},
            <String, Object>{'id': 'def456', 'name': 'Budget 2024'},
          ],
        }));

    final found = await GoogleDriveService(
      accessToken: 'token-1',
      client: client,
    ).findSpreadsheets();

    expect(found.map((sheet) => sheet.id), <String>['abc123', 'def456']);
    expect(found.first.title, 'FINTRACK');
    expect(
      found.first.url,
      'https://docs.google.com/spreadsheets/d/abc123',
      reason: 'a result must be openable, not just identifiable',
    );

    final request = client.last!;
    expect(request.url.host, 'www.googleapis.com');
    expect(request.url.path, '/drive/v3/files');
    expect(request.headers['Authorization'], 'Bearer token-1');

    final query = request.url.queryParameters['q']!;
    expect(
      query,
      contains("mimeType='application/vnd.google-apps.spreadsheet'"),
    );
    expect(query, contains('trashed = false'));
    expect(
      query,
      isNot(contains('name contains')),
      reason: 'an empty search must not filter by a title nobody supplied',
    );
    expect(request.url.queryParameters['orderBy'], 'modifiedTime desc');
  });

  test('a title fragment narrows the query', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{
          'files': <Object>[],
        }));

    await GoogleDriveService(accessToken: 't', client: client)
        .findSpreadsheets(query: 'Expense');

    expect(
      client.last!.url.queryParameters['q'],
      contains("name contains 'Expense'"),
    );
  });

  test('a quote in the search term cannot break the filter syntax', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{
          'files': <Object>[],
        }));

    await GoogleDriveService(accessToken: 't', client: client)
        .findSpreadsheets(query: "Sandesh's sheet");

    expect(
      client.last!.url.queryParameters['q'],
      contains(
        r"name contains 'Sandesh\'s sheet'",
      ),
      reason: "Drive treats ' as a delimiter, so it has to be escaped",
    );
  });

  test('a reply with no files list is an empty result, not a crash', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{}));

    final found = await GoogleDriveService(
      accessToken: 't',
      client: client,
    ).findSpreadsheets();

    expect(found, isEmpty);
  });

  test('a token without the Drive scope says which scope to add', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{
          'error': <String, Object>{
            'code': 401,
            'message': 'Request had insufficient authentication scopes.',
          },
        }, 401));

    final future = GoogleDriveService(
      accessToken: 't',
      client: client,
    ).findSpreadsheets();

    await expectLater(
      future,
      throwsA(
        isA<SheetsException>().having(
          (error) => error.message,
          'message',
          contains('drive.readonly'),
        ),
      ),
    );
  });

  test('a refused listing points at the API and the test-user list', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{
          'error': <String, Object>{
            'code': 403,
            'message': 'The caller does not have permission',
          },
        }, 403));

    await expectLater(
      GoogleDriveService(accessToken: 't', client: client).findSpreadsheets(),
      throwsA(
        isA<SheetsException>()
            .having((error) => error.message, 'message', contains('Test users'))
            .having(
              (error) => error.technical,
              'technical',
              contains('HTTP 403'),
            ),
      ),
    );
  });
}
