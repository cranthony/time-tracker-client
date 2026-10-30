import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// See credentialed_http.dart: on the web, a client whose requests carry
/// the browser's cookies for the server's site (`credentials: include`),
/// even cross-origin, and take the cookies its answers set.
http.Client credentialedClient() => BrowserClient()..withCredentials = true;
