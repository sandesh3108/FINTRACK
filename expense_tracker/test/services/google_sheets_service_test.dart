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

  /// Growing first is what keeps the clear below it legal: the old code named
  /// row 1002 on a 1000-row sheet.
  test('an export grows a short sheet before clearing it', () async {
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
    await GoogleSheetsService(accessToken: 't', client: client)
        .writeTable('abc', rows);

    final paths = [for (final r in client.requests) _pathOf(r)];
    expect(
      paths,
      anyElement(contains(':batchUpdate')),
      reason: 'the tab has to be grown before anything is written to it',
    );
    expect(
      paths,
      anyElement(contains('/values/A1:I1501/clear')),
      reason: 'the clear must stop at the new bottom, not at a guessed row',
    );
    expect(
      client.requests.where((r) => r.method == 'PUT'),
      isNotEmpty,
      reason: 'the table itself still has to be written',
    );
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
