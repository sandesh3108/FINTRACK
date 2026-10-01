import 'dart:convert';

import 'package:expense_tracker/core/errors/app_exception.dart';
import 'package:expense_tracker/services/google_sheets_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _FakeClient extends http.BaseClient {
  _FakeClient(this._reply);

  final Future<http.Response> Function(http.Request request) _reply;

  http.Request? last;
  final List<http.Request> requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final captured = request as http.Request;
    last = captured;
    requests.add(captured);
    final response = await _reply(captured);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
    );
  }
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

/// The grid reply every read and write asks for first.
Object _gridJson({
  int rowCount = 1000,
  int columnCount = 26,
  int sheetId = 0,
}) =>
    <String, Object>{
      'sheets': <Object>[
        <String, Object>{
          'properties': <String, Object>{
            'sheetId': sheetId,
            'gridProperties': <String, Object>{
              'rowCount': rowCount,
              'columnCount': columnCount,
            },
          },
        },
      ],
    };

bool _asksForGrid(http.Request request) =>
    request.url.queryParameters['fields']?.contains('gridProperties') ?? false;

/// Decoded path, so ranges can be compared as a person would read them.
String _pathOf(http.Request request) => Uri.decodeComponent(request.url.path);

void main() {
  /// The connection check asks a question Google is allowed to answer "not
  /// found" with. Anything but an outright refusal proves the device is
  /// online, the token was accepted and the API is switched on - without
  /// writing a single cell.
  test('probe treats a 404 as proof the connection works', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{
          'error': <String, Object>{
            'code': 404,
            'message': 'Requested entity was not found.',
          },
        }, 404));

    await GoogleSheetsService(accessToken: 'token', client: client).probe();

    expect(client.last!.url.host, 'sheets.googleapis.com');
    expect(client.last!.url.path, contains('/v4/spreadsheets/'));
    expect(client.last!.headers['Authorization'], 'Bearer token');
  });

  test('probe passes a healthy reply straight through', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{
          'spreadsheetId': '__connection_probe__',
        }));

    await expectLater(
      GoogleSheetsService(accessToken: 't', client: client).probe(),
      completes,
    );
  });

  test('probe reports an expired session as something to redo', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{
          'error': <String, Object>{
            'code': 401,
            'message': 'Invalid credentials'
          },
        }, 401));

    await expectLater(
      GoogleSheetsService(accessToken: 't', client: client).probe(),
      throwsA(
        isA<SheetsException>()
            .having((error) => error.message, 'message', contains('Sign out'))
            .having(
              (error) => error.technical,
              'technical',
              contains('HTTP 401'),
            ),
      ),
    );
  });

  test('probe reports a disabled API with Google wording kept as detail',
      () async {
    final client = _FakeClient((_) async => _json(<String, Object>{
          'error': <String, Object>{
            'code': 403,
            'message': 'Google Sheets API has not been used in project 123 '
                'or it is disabled.',
          },
        }, 403));

    await expectLater(
      GoogleSheetsService(accessToken: 't', client: client).probe(),
      throwsA(
        isA<SheetsException>().having(
          (error) => error.technical,
          'technical',
          contains('has not been used in project 123'),
        ),
      ),
    );
  });

  /// The reported failure. Google evaluates the token before it looks at the
  /// body of a request, so a 400 still proves the phone is online, the token
  /// was accepted and the API is answering - it means the *question* was bad,
  /// not the connection. Reporting it as a dead connection called a healthy
  /// one broken.
  test('probe treats a 400 as a working connection', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{
          'error': <String, Object>{
            'code': 400,
            'message': 'Invalid spreadsheet ID.',
          },
        }, 400));

    await expectLater(
      GoogleSheetsService(accessToken: 't', client: client).probe(),
      completes,
    );
  });

  /// A brand-new Google Sheet has exactly 1000 rows; the app used to ask for
  /// row 1001 on every read. Google answers an out-of-grid range with 400
  /// instead of trimming it.
  test('read clamps its range to the grid Google reports', () async {
    final client = _FakeClient((request) async => _asksForGrid(request)
        ? _json(_gridJson(rowCount: 1000, columnCount: 26))
        : _json(<String, Object>{
            'values': <Object>[
              <Object>['Date', 'Amount'],
              <Object>['01/01/2026', '100'],
            ],
          }));

    final rows =
        await GoogleSheetsService(accessToken: 't', client: client).read('abc');

    final values =
        client.requests.firstWhere((r) => r.url.path.contains('/values/'));
    expect(_pathOf(values), contains('A1:I1000'));
    expect(
      _pathOf(values),
      isNot(contains('1001')),
      reason: 'row 1001 does not exist on a sheet that ships with 1000',
    );
    expect(rows.first, <String>['Date', 'Amount']);
  });

  /// Growing first is what keeps the write legal: the old code named row 1002
  /// on a 1000-row sheet. When the table itself reaches the new bottom there is
  /// nothing underneath it to erase, so no clear is issued at all - clearing
  /// would only ever risk what was just written.
  test('an export that outgrows the sheet grows it and skips the clear',
      () async {
    final client = _FakeClient((request) async {
      if (_asksForGrid(request)) return _json(_gridJson(sheetId: 7));
      if (_pathOf(request).endsWith(':batchUpdate')) {
        return _json(<String, Object>{'replies': <Object>[]});
      }
      return _json(<String, Object>{});
    });

    final rows = [
      for (var i = 0; i < 1500; i++) <String>['01/01/2026', 'Expense', '100'],
    ];
    final warning = await GoogleSheetsService(accessToken: 't', client: client)
        .writeTable('abc', rows);

    final paths = [for (final r in client.requests) _pathOf(r)];
    expect(
      paths,
      anyElement(contains(':batchUpdate')),
      reason: 'the tab has to be grown before anything is written to it',
    );
    expect(
      paths,
      anyElement(contains('/values/A1:I1501')),
      reason: 'the table itself still has to be written',
    );
    expect(
      paths,
      isNot(anyElement(contains('/clear'))),
      reason: 'nothing lies below the table, so there is nothing to erase',
    );
    expect(warning, isNull);
  });

  /// The stale tail of a longer previous export, and only that: rows below the
  /// table. Clearing from the heading down would be able to undo the write that
  /// has just succeeded.
  test('the stale tail is cleared, and only the rows below the table',
      () async {
    final client = _FakeClient((request) async => _asksForGrid(request)
        ? _json(_gridJson(rowCount: 1000, columnCount: 26))
        : _json(<String, Object>{}));

    final warning = await GoogleSheetsService(accessToken: 't', client: client)
        .writeTable('abc', [
      for (var i = 0; i < 200; i++) <String>['01/01/2026', 'Expense', '100'],
    ]);

    final paths = [for (final r in client.requests) _pathOf(r)];
    expect(
      paths,
      anyElement(contains('/values/A202:I1000/clear')),
      reason: 'row 201 is the last one written, so erasing starts at 202',
    );
    expect(
      client.requests
          .where((r) => r.method == 'PUT')
          .map((r) => _pathOf(r)),
      anyElement(contains('/values/A1:I201')),
      reason: 'header plus 200 rows is 201 rows, written first',
    );
    expect(warning, isNull);
  });

  /// The erase is housekeeping. Turning it into a thrown error would trade a
  /// cosmetic leftover for a backup that never happened.
  test('a refusal to clear the tail is reported instead of thrown', () async {
    final client = _FakeClient((request) async {
      if (_asksForGrid(request)) return _json(_gridJson());
      if (_pathOf(request).endsWith('/clear')) {
        return http.Response(
            '<html><body><h1>400 Bad Request</h1></body></html>', 400);
      }
      return _json(<String, Object>{});
    });

    final warning = await GoogleSheetsService(accessToken: 't', client: client)
        .writeTable('abc', [
      for (var i = 0; i < 200; i++) <String>['01/01/2026', 'Expense', '100'],
    ]);

    expect(warning, isNotNull, reason: 'the export still succeeded');
    expect(warning, contains('written'));
    expect(
      warning,
      contains('HTTP 400'),
      reason: 'and it says exactly what Google refused',
    );
    expect(
      warning,
      contains('400 Bad Request'),
      reason: 'even when the reply was not JSON at all',
    );
    expect(
      client.requests.where((r) => r.method == 'PUT'),
      isNotEmpty,
      reason: 'the table was written before the erase was attempted',
    );
  });

  /// A paste picks up a trailing newline or a leading space easily, Google
  /// decodes the path before validating the id, and the character the clipboard
  /// added then becomes part of the id - reported as a 400 that blames the
  /// spreadsheet.
  test('paste whitespace is stripped from the id before the URL is built',
      () async {
    final client = _FakeClient((_) async => _json(<String, Object>{}));

    await GoogleSheetsService(accessToken: 't', client: client).writeCells(
      ' \n abc\t',
      'A1',
      <List<String>>[
        <String>['Date'],
      ],
    );

    final put = client.last!;
    expect(
      _pathOf(put),
      contains('/spreadsheets/abc/values/'),
      reason: 'the id reaches Google as abc, not as " abc"',
    );
  });

  /// When Google explains itself, keep its words; when it does not, keep what
  /// it actually sent instead of dropping it.
  test('a reply that is not JSON is kept alongside the status', () async {
    final client = _FakeClient((request) async => _asksForGrid(request)
        ? _json(_gridJson())
        : http.Response('<html><body>backend error</body></html>', 502));

    await expectLater(
      GoogleSheetsService(accessToken: 't', client: client).read('abc'),
      throwsA(
        isA<SheetsException>()
            .having(
              (error) => error.technical,
              'technical',
              contains('HTTP 502'),
            )
            .having(
              (error) => error.technical,
              'technical',
              contains('backend error'),
            ),
      ),
    );
  });

  /// The fallback size is a placeholder, never a measurement. Writing it back
  /// as rowCount to a sheet that happens to hold 5000 rows would truncate the
  /// tab to 1000 and take everything below with it - rows this app does not own.
  test('a tab whose size could not be measured is never resized', () async {
    final client = _FakeClient((_) async => _json(<String, Object>{}));

    final warning = await GoogleSheetsService(accessToken: 't', client: client)
        .writeTable('abc', [
      for (var i = 0; i < 10; i++) <String>['01/01/2026', 'Expense', '100'],
    ]);

    final paths = [for (final r in client.requests) _pathOf(r)];
    expect(
      paths,
      isNot(anyElement(contains(':batchUpdate'))),
      reason: 'a guess is not a licence to resize',
    );
    expect(
      paths,
      isNot(anyElement(contains('/clear'))),
      reason: 'nor to erase against it',
    );
    expect(
      client.requests.where((r) => r.method == 'PUT'),
      isNotEmpty,
      reason: 'the table is still written - the write is what matters',
    );
    expect(warning, isNull);
  });

  test('an export that already fits does not touch the grid', () async {
    final client = _FakeClient((request) async => _asksForGrid(request)
        ? _json(_gridJson(rowCount: 5000))
        : _json(<String, Object>{}));

    await GoogleSheetsService(accessToken: 't', client: client)
        .writeTable('abc', [
      <String>['01/01/2026', 'Expense', '100'],
    ]);

    expect(
      [for (final r in client.requests) _pathOf(r)],
      isNot(anyElement(contains(':batchUpdate'))),
      reason: 'no extra round trip when the sheet is already big enough',
    );
  });

  /// Twenty-seven columns used to be rendered by walking 26 letters past Z and
  /// landing on `[`, which Google refuses to parse.
  test('a table wider than Z is spelled out, not walked off the alphabet',
      () async {
    final client = _FakeClient((_) async => _json(<String, Object>{}));

    await GoogleSheetsService(accessToken: 't', client: client)
        .writeCells('abc', 'A1', <List<String>>[List<String>.filled(27, 'x')]);

    final put = client.last!;
    expect(_pathOf(put), contains('values/A1:AA1'));
    expect(
      (jsonDecode(put.body) as Map<String, dynamic>)['range'],
      'A1:AA1',
      reason: 'the body and the URL must name the same range',
    );
  });

  test('a rejected request says which call produced it', () async {
    final client = _FakeClient((request) async => _asksForGrid(request)
        ? _json(_gridJson())
        : _json(<String, Object>{
            'error': <String, Object>{
              'code': 400,
              'message': 'Unable to parse range: A1:I.',
            },
          }, 400));

    await expectLater(
      GoogleSheetsService(accessToken: 't', client: client).read('abc'),
      throwsA(
        isA<SheetsException>()
            .having(
              (error) => error.technical,
              'technical',
              contains('HTTP 400'),
            )
            .having(
              (error) => error.technical,
              'technical',
              contains('/values/'),
            )
            .having(
              (error) => error.technical,
              'technical',
              contains('Unable to parse range'),
            ),
      ),
    );
  });
}
