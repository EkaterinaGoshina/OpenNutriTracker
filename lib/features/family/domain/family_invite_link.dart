/// Invite links look like `https://app.example.com/?join=K7QM2XPA`. The code
/// rides in the query rather than in a route so it does not depend on the
/// router's URL strategy and survives the sign-in redirect.
abstract final class FamilyInviteLink {
  static const queryParameter = 'join';

  /// Same alphabet and length as the database's codes: no I, O, 0 or 1.
  static final _code = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');

  /// Uppercases and drops spaces and dashes, so a code typed from a message
  /// ("k7qm-2xpa") matches. Returns null when what is left cannot be a code.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final code = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    return _code.hasMatch(code) ? code : null;
  }

  /// The code in [uri]'s `?join=`, or null.
  static String? codeFrom(Uri uri) =>
      normalize(uri.queryParameters[queryParameter]);

  /// [base] with `?join=` set to [code], keeping its other parameters and
  /// dropping the in-app route (the fragment), so the link opens the start
  /// screen.
  static Uri build(Uri base, String code) => _with(base, {
    ...base.queryParameters,
    queryParameter: code,
  }, fragment: null);

  /// [uri] without its `?join=`, for the address bar once the code is used.
  /// Keeps the fragment: the web build routes with it.
  static Uri strip(Uri uri) => _with(
    uri,
    Map.of(uri.queryParameters)..remove(queryParameter),
    fragment: uri.hasFragment ? uri.fragment : null,
  );

  // Uri.replace treats a null query as "keep the old one", so an emptied
  // query needs a fresh Uri.
  static Uri _with(
    Uri uri,
    Map<String, String> query, {
    required String? fragment,
  }) => Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    queryParameters: query.isEmpty ? null : query,
    fragment: fragment,
  );
}
