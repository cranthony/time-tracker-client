// Relays web/callback.html's URL to the app's tab; see callback.html.
if (new URLSearchParams(location.search).has('error')) {
  document.getElementById('heading').textContent = 'Sign-in failed';
}
// Must match WebRedirectReceiver.channelName.
const channel = new BroadcastChannel('time_tracker_oauth');
channel.postMessage(location.href);
channel.close();
window.close();
