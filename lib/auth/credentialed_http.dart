import 'package:http/http.dart' as http;

/// An HTTP client that sends the browser's cookies with every request, and
/// takes the cookies answers set: how the web app stays signed in with the
/// server's session cookie (see [AuthSession.cookieSession]). Off the web
/// there are no cookies to send, so this is a plain client.
http.Client credentialedClient() => http.Client();
