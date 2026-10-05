// Starts the app (see index.html), but not inside a frame: there another
// site could hide it under its own page, so that a click meant for that
// page lands on the app. GitHub Pages can't send a header that forbids
// framing, and a Content-Security-Policy in a meta tag can't either.
if (window.top === window.self) {
  const script = document.createElement('script');
  script.src = 'flutter_bootstrap.js';
  script.async = true;
  document.body.appendChild(script);
} else {
  document.body.textContent =
    'Time Tracker only runs in its own window or tab.';
}
