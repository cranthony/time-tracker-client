import '../services/server_errors.dart';

/// Why [e] kept something from being saved, in a few words.
String describeSaveError(Object e) => describeServerError(e).message;
