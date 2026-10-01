import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../core/errors/app_exception.dart';

/// A spreadsheet as far as this app cares: an id, a title and a link.
class SheetReference {
  const SheetReference({
    required this.id,
    required this.title,
    required this.url,
  });

  final String id;
  final String title;
  final String url;

  /// Builds a reference from a bare id.
  factory SheetReference.fromId(String id, {String title = ''}) =>
      SheetReference(
        id: id,
        title: title,
        url: 'https://docs.google.com/spreadsheets/d/$id',
      );

  /// Extracts the id from a pasted link, or returns `null`.
  ///
  /// Accepts the shapes people actually paste:
  /// `https://docs.google.com/spreadsheets/d/<id>/edit#gid=0`, the same with
  /// `/edit?usp=sharing`, `/gviz/tq?tqx=out:csv`, and a bare id.
  static String? idFrom(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final match = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)').firstMatch(trimmed);
    if (match != null) return match.group(1);

    // A bare id: no scheme, no slashes, Google's usual character set.
    if (!trimmed.contains('/') && !trimmed.contains(' ')) {
      final bare = RegExp(r'^[a-zA-Z0-9-_]+$').firstMatch(trimmed);
      if (bare != null) return trimmed;
    }
    return null;
  }
}

/// Read/write access to Google Sheets over the REST API.
///
/// Deliberately dumb: it knows how to talk to Google and nothing else. Column
/// mapping, duplicate detection and row validation all live one layer up, so
/// this file can be tested by pointing it at a stubbed [http.Client].
///
/// Every call takes a bearer token from [GoogleAuthService] rather than
/// owning one itself.
class GoogleSheetsService {
  GoogleSheetsService({required this.accessToken, http.Client? client})
      : _client = client ?? http.Client();

  final String accessToken;
  final http.Client _client;

  static const String _host = 'sheets.googleapis.com';
  static const String _root = '/v4';

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      };

  /// Range covering the heading and every row an import may read, squeezed
  /// into [grid] first.
  ///
  /// Google answers a range that runs past the grid with HTTP 400 rather than
  /// trimming it, and a brand-new spreadsheet ships with exactly 1000 rows
  /// while `maxImportRows` plus the heading asks for 1001 - one row too many.
  static String? _importRange(_Grid grid) => _range(
        first: AppConfig.sheetHeaderRow,
        last: AppConfig.sheetHeaderRow + AppConfig.maxImportRows,
        columns: AppConfig.sheetColumns.length,
        grid: grid,
      );

  /// `A<first>:<cols><last>` clamped into [grid], or `null` when the grid is
  /// too short to hold even the heading.
  ///
  /// The result is *not* percent-encoded before it is handed to [Uri.https],
  /// which encodes its own path: pre-encoding turned `A1:I1000` into
  /// `A1%3AI1000`, and the second pass turned that into `A1%253AI1000` on the
  /// wire. Google decoded it back to the literal text `A1%3AI1000`, refused to
  /// read it as a range, and answered HTTP 400. A range is only ever `A-Z`,
  /// `0-9` and `:`, every one of which is legal in a path, so it goes through
  /// as written.
  static String? _range({
    required int first,
    required int last,
    required int columns,
    required _Grid grid,
  }) {
    if (grid.rows < 1 || grid.columns < 1) return null;
    final start = first.clamp(1, grid.rows);
    final end = last.clamp(start, grid.rows);
    final width = columns.clamp(1, grid.columns);
    return 'A$start:${_columnLetter(width)}$end';
  }

  /// `1 -> A`, `26 -> Z`, `27 -> AA`.
  ///
  /// Read as a base-26 number rather than a flat offset: the offset form walks
  /// off the end of the alphabet (`27 -> '['`) the moment a sheet outgrows the
  /// columns this app ships with, and Google will not parse the result.
  static String _columnLetter(int oneBased) {
    var remaining = oneBased;
    final letters = <String>[];
    while (remaining > 0) {
      final digit = (remaining - 1) % 26;
      letters.add(String.fromCharCode('A'.codeUnitAt(0) + digit));
      remaining = (remaining - 1) ~/ 26;
    }
    return letters.isEmpty ? 'A' : letters.reversed.join();
  }

  // --------------------------------------------------------------- operations

  /// Creates an empty spreadsheet whose first tab is named
  /// [AppConfig.sheetTabName].
  Future<SheetReference> createSpreadsheet(String title) async {
    final body = await _send(
      _request(
        'POST',
        Uri.https(_host, '$_root/spreadsheets'),
        body: <String, dynamic>{
          'properties': <String, dynamic>{'title': title},
          'sheets': <Map<String, dynamic>>[
            <String, dynamic>{
              'properties': <String, dynamic>{'title': AppConfig.sheetTabName},
            },
          ],
        },
      ),
    );

    final id = body['spreadsheetId'];
    if (id is! String || id.isEmpty) {
      throw const SheetsException(
        'Google did not return an id for the new spreadsheet.',
      );
    }
    final properties = body['properties'];
    final sheetTitle = properties is Map && properties['title'] is String
        ? properties['title'] as String
        : title;
    return SheetReference.fromId(id, title: sheetTitle);
  }

  /// Reads the title of an existing spreadsheet, proving the id is reachable
  /// with the current credentials.
  Future<SheetReference> open(String spreadsheetId) async {
    final body = await _send(
      _request(
        'GET',
        Uri.https(_host, '$_root/spreadsheets/$spreadsheetId',
            <String, String>{'fields': 'properties.title'}),
      ),
    );
    final properties = body['properties'];
    final title = properties is Map && properties['title'] is String
        ? properties['title'] as String
        : 'Spreadsheet';
    return SheetReference.fromId(spreadsheetId, title: title);
  }

  /// Asks Google a question it is allowed to answer "not found".
  ///
  /// Reads a spreadsheet id that cannot exist, so nothing is written. Any
  /// answer - even 404 - proves three things at once: the phone is online, the
  /// access token was accepted and the Sheets API is switched on for this
  /// project. Anything else is turned by [_failure] into the reason it failed.
  Future<void> probe() async {
    final uri = Uri.https(_host, '$_root/spreadsheets/__connection_probe__',
        <String, String>{'fields': 'spreadsheetId'});
    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers);
    } on SocketException {
      throw const OfflineException();
    } on http.ClientException {
      throw const OfflineException();
    }

    // Google rejects a made-up id with 400 or 404 depending on how it parses
    // it. Both mean the same thing to this check: the phone is online, the
    // token was accepted and the Sheets API is answering - auth is always
    // evaluated before the body of a request is. Reporting 400 as a failure
    // therefore called a perfectly healthy connection dead.
    final status = response.statusCode;
    if (status < 400 || status == 400 || status == 404) return;
    throw _failure(status, response.body, where: 'GET ${uri.path}');
  }

  /// Reads a range as rows of strings; missing cells become `''`.
  ///
  /// Trailing empty cells are dropped by Google, so rows are normalised to the
  /// width of the widest row.
  Future<List<List<String>>> read(String spreadsheetId) async {
    final range = _importRange(await _grid(spreadsheetId));
    if (range == null) return const <List<String>>[];

    final body = await _send(
      _request(
        'GET',
        Uri.https(
          _host,
          '$_root/spreadsheets/$spreadsheetId/values/$range',
          <String, String>{'majorDimension': 'ROWS'},
        ),
      ),
    );

    final values = body['values'];
    if (values is! List || values.isEmpty) return const <List<String>>[];

    final rows = <List<String>>[
      for (final row in values)
        if (row is List)
          <String>[for (final cell in row) cell?.toString() ?? '']
        else
          <String>[],
    ];

    // Google omits trailing blanks; pad so column indices line up.
    var width = 0;
    for (final row in rows) {
      if (row.length > width) width = row.length;
    }
    return [
      for (final row in rows)
        <String>[...row, ...List.filled(width - row.length, '')],
    ];
  }

  /// Overwrites the heading row, so an exported sheet is always self-describing.
  ///
  /// Used when a spreadsheet is first linked: it is empty, and the next line
  /// up is nothing to clear.
  Future<void> writeHeader(String spreadsheetId) => writeCells(
        spreadsheetId,
        'A${AppConfig.sheetHeaderRow}',
        <List<String>>[AppConfig.sheetColumns],
      );

  /// Writes the heading and every row in one shot, replacing whatever the
  /// table held before.
  ///
  /// Export overwrites rather than appends for two reasons: exporting twice
  /// must not duplicate the ledger, and a transaction deleted in the app has
  /// to disappear from the sheet too. The caller supplies [rows] already
  /// sorted by date, which is what keeps the sheet readable day by day.
  Future<void> writeTable(
    String spreadsheetId,
    List<List<String>> rows,
  ) async {
    var width = AppConfig.sheetColumns.length;
    for (final row in rows) {
      if (row.length > width) width = row.length;
    }

    // Grow the tab first when the export is longer than the sheet it is going
    // into. The clear below cannot name rows that do not exist yet - Google
    // rejects the whole range with HTTP 400 instead of clipping it - and a
    // brand-new sheet has 1000 rows where a large export needs more.
    final grid = await _ensureGrid(
      spreadsheetId,
      await _grid(spreadsheetId),
      AppConfig.sheetHeaderRow + rows.length,
      width,
    );

    // Blank everything from the heading to the bottom of the tab, so the tail
    // of a longer previous run is erased instead of surviving underneath.
    // Clamped to the grid rather than to a row count this app guessed at.
    final range = _range(
      first: AppConfig.sheetHeaderRow,
      last: grid.rows,
      columns: width,
      grid: grid,
    );

    if (range != null) {
      await _send(
        _request(
          'POST',
          Uri.https(
            _host,
            '$_root/spreadsheets/$spreadsheetId/values/'
            '$range/clear',
          ),
          body: <String, dynamic>{},
        ),
      );
    }

    await writeCells(
      spreadsheetId,
      'A${AppConfig.sheetHeaderRow}',
      <List<String>>[AppConfig.sheetColumns, ...rows],
    );
  }

  /// Overwrites the given top-left anchor with [rows].
  ///
  /// The range is spelled out from the data instead of being left as the bare
  /// anchor: `values/update` carries a range *and* a values array, and when
  /// the two disagree Google answers 400. Deriving both from the same numbers
  /// leaves nothing to disagree about.
  Future<void> writeCells(
    String spreadsheetId,
    String anchor,
    List<List<String>> rows,
  ) async {
    if (rows.isEmpty) return;

    final start = _Cell.parse(anchor);
    var width = 0;
    for (final row in rows) {
      if (row.length > width) width = row.length;
    }
    if (width < 1) width = 1;

    final range =
        '${_columnLetter(start.column)}${start.row}:'
        '${_columnLetter(start.column + width - 1)}'
        '${start.row + rows.length - 1}';

    await _send(
      _request(
        'PUT',
        Uri.https(
          _host,
          '$_root/spreadsheets/$spreadsheetId/values/$range',
          <String, String>{'valueInputOption': 'USER_ENTERED'},
        ),
        body: <String, dynamic>{
          'range': range,
          'majorDimension': 'ROWS',
          'values': rows,
        },
      ),
    );
  }

  // ------------------------------------------------------------------ plumbing

  /// The first tab's real size, so no range can be aimed outside it.
  Future<_Grid> _grid(String spreadsheetId) async {
    final body = await _send(
      _request(
        'GET',
        Uri.https(
          _host,
          '$_root/spreadsheets/$spreadsheetId',
          <String, String>{
            'fields': 'sheets(properties(sheetId,gridProperties))',
          },
        ),
      ),
    );

    final sheets = body['sheets'];
    if (sheets is! List || sheets.isEmpty || sheets.first is! Map) {
      return const _Grid.fallback();
    }
    final properties = (sheets.first as Map)['properties'];
    if (properties is! Map) return const _Grid.fallback();
    final grid = properties['gridProperties'];
    if (grid is! Map) return const _Grid.fallback();

    final rows = grid['rowCount'];
    final columns = grid['columnCount'];
    final sheetId = properties['sheetId'];
    return _Grid(
      sheetId: sheetId is int ? sheetId : 0,
      rows: rows is int && rows > 0 ? rows : _Grid.defaultRows,
      columns: columns is int && columns > 0 ? columns : _Grid.defaultColumns,
    );
  }

  /// Grows the tab so [rows] x [columns] really fit, and returns the grid.
  ///
  /// A no-op when the sheet is already big enough, which is the ordinary case:
  /// an export the shipping size fits needs no extra call at all.
  Future<_Grid> _ensureGrid(
    String spreadsheetId,
    _Grid grid,
    int rows,
    int columns,
  ) async {
    final wantRows = rows.clamp(grid.rows, _Grid.maxRows);
    final wantColumns = columns.clamp(grid.columns, _Grid.maxColumns);
    if (wantRows == grid.rows && wantColumns == grid.columns) return grid;

    await _send(
      _request(
        'POST',
        Uri.https(_host, '$_root/spreadsheets/$spreadsheetId:batchUpdate'),
        body: <String, dynamic>{
          'requests': <Map<String, dynamic>>[
            <String, dynamic>{
              'updateSheetProperties': <String, dynamic>{
                'properties': <String, dynamic>{
                  'sheetId': grid.sheetId,
                  'gridProperties': <String, dynamic>{
                    'rowCount': wantRows,
                    'columnCount': wantColumns,
                  },
                },
                'fields': 'gridProperties.rowCount,gridProperties.columnCount',
              },
            },
          ],
        },
      ),
    );

    return _Grid(sheetId: grid.sheetId, rows: wantRows, columns: wantColumns);
  }

  http.Request _request(String method, Uri uri, {Object? body}) {
    final request = http.Request(method, uri)
      ..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    return request;
  }

  /// Sends [request] and decodes the JSON reply, or throws a [SheetsException]
  /// carrying a message a person can act on.
  Future<Map<String, dynamic>> _send(http.Request request) async {
    final http.Response response;
    try {
      final streamed = await _client.send(request);
      response = await http.Response.fromStream(streamed);
    } on SocketException {
      throw const OfflineException();
    } on http.ClientException {
      throw const OfflineException();
    }

    final body = response.body;
    if (response.statusCode >= 400) {
      throw _failure(
        response.statusCode,
        body,
        where: '${request.method} ${request.url.path}',
      );
    }

    if (body.isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{'value': decoded};
    } on FormatException {
      throw SheetsException(
        'Google returned a reply this app could not read.',
        technical: body,
      );
    }
  }

  /// Turns an HTTP error into a message about *what to do next*.
  ///
  /// Google's own wording is kept as the technical detail - it is useful when
  /// something has to be reported, but it is rarely actionable on its own.
  SheetsException _failure(int status, String body, {String? where}) {
    String? googleMessage;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final message = decoded['error']['message'];
        if (message is String && message.isNotEmpty) googleMessage = message;
      }
    } on FormatException {
      // Not JSON - keep the raw body as the technical detail only.
    }

    final technical = 'HTTP $status'
        '${where == null ? '' : ' $where'}'
        '${googleMessage == null ? '' : ': $googleMessage'}';

    return switch (status) {
      400 => SheetsException(
          'Google would not accept that request as written. The line below is '
          "Google's own reason, together with the call that produced it.",
          technical: technical,
        ),
      401 => SheetsException(
          'Google no longer accepts this session. Sign out and sign in again.',
          technical: technical,
        ),
      403 => SheetsException(
          'Google refused access to that spreadsheet. Make sure it is the '
          'account you signed in with, and that you are allowed to edit it.',
          technical: technical,
        ),
      404 => SheetsException(
          'That spreadsheet could not be found. It may have been deleted, '
          'or the link may be wrong.',
          technical: technical,
        ),
      429 => SheetsException(
          'Google is limiting how often this app may talk to it. Wait a '
          'minute and try again.',
          technical: technical,
        ),
      _ => SheetsException(
          'Google Sheets could not complete the request.',
          technical: technical,
        ),
    };
  }
}

/// Real size of the tab this app reads and writes.
class _Grid {
  /// Records the dimensions Google reported for the first tab.
  const _Grid({
    required this.sheetId,
    required this.rows,
    required this.columns,
  });

  /// Used when a reply did not carry the grid: these are the dimensions every
  /// spreadsheet starts with, and clamping to them can only ever make a range
  /// smaller, never larger.
  const _Grid.fallback()
      : sheetId = 0,
        rows = defaultRows,
        columns = defaultColumns;

  /// A fresh Google Sheet is 1000 rows by 26 columns.
  static const int defaultRows = 1000;
  static const int defaultColumns = 26;

  /// Ceilings this app will never ask to grow past - well inside Google's
  /// 10-million-cell limit once multiplied by the columns it actually uses.
  static const int maxRows = 100000;
  static const int maxColumns = 18278;

  final int sheetId;
  final int rows;
  final int columns;
}

/// A parsed A1 anchor: 1-based column and row.
class _Cell {
  const _Cell(this.column, this.row);

  /// 1-based column index: `A` -> 1.
  final int column;

  /// 1-based row index: `1` -> 1.
  final int row;

  /// `A1` -> (1, 1); anything unparseable lands on A1, which is where every
  /// write this app performs starts anyway.
  static _Cell parse(String anchor) {
    final match = RegExp(r'^([A-Za-z]+)([0-9]+)$').firstMatch(anchor.trim());
    if (match == null) return const _Cell(1, 1);

    var column = 0;
    for (final code in match.group(1)!.toUpperCase().codeUnits) {
      column = column * 26 + (code - 'A'.codeUnitAt(0) + 1);
    }
    return _Cell(column, int.parse(match.group(2)!));
  }
}
