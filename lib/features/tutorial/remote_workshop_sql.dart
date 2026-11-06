/// Downloaded lessons can run a single bounded SELECT against the practice
/// database. Check before SQLite prepares any SQL, including on resume.
bool isDownloadedWorkshopQuery(String sql) {
  if (sql.length > 4096 || sql.contains('\u0000')) return false;

  var offset = 0;
  var previous = '';
  var inFrom = false;
  var joins = 0;
  while (offset < sql.length) {
    final match = _token.matchAsPrefix(sql, offset);
    if (match == null) return false;
    offset = match.end;
    final token = match[0]!.trim().toUpperCase();
    if (token.isEmpty) continue;
    if (previous.isEmpty) {
      if (token != 'SELECT') return false;
    } else if (_forbiddenWords.contains(token)) {
      return false;
    }
    if (token == ';') return sql.substring(offset).trim().isEmpty;
    if (token == 'FROM') inFrom = true;
    if (_endOfFrom.contains(token)) inFrom = false;
    if (token == 'JOIN' && ++joins > 3) return false;
    if (inFrom && token == ',') return false;
    if (token == '(' && !_allowedBeforeParen.contains(previous)) {
      return false;
    }
    previous = token;
  }
  return previous.isNotEmpty;
}

final _token = RegExp(
  r"""[ \t\r\n]+|'(?:[^']|'')*'|"[A-Za-z_][A-Za-z0-9_]*"|[A-Za-z_][A-Za-z0-9_]*|[0-9]+|[(),.;*=<>!+%]|/(?!\*)|-(?!-)""",
);

// Quoted literals are single tokens. The token pattern rejects comment
// openers outside a literal so SQLite and this check see the same tokens.
const _forbiddenWords = {
  'SELECT',
  'UNION',
  'INTERSECT',
  'EXCEPT',
  'WITH',
  'VALUES',
};
const _endOfFrom = {'WHERE', 'GROUP', 'HAVING', 'ORDER', 'LIMIT'};
const _allowedBeforeParen = {
  'SELECT',
  'DISTINCT',
  'WHERE',
  'AND',
  'OR',
  'NOT',
  'IN',
  'ON',
  'HAVING',
  'BY',
  '(',
  ',',
  '=',
  '<',
  '>',
  '+',
  '-',
  '*',
  '/',
  '%',
  'COUNT',
  'SUM',
  'AVG',
  'MIN',
  'MAX',
};
