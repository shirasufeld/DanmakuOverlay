// Streams the system Now Playing state as JSON lines on stdout.
// Run with Apple's /usr/bin/osascript -l JavaScript: MediaRemote only answers Apple-signed processes.
ObjC.import('Foundation');

$.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
const Request = $.NSClassFromString('MRNowPlayingRequest');
const stdout = $.NSFileHandle.fileHandleWithStandardOutput;

function num(info, key) {
  const v = info.objectForKey(key);
  return v.isNil() ? null : v.doubleValue;
}
function str(info, key) {
  const v = info.objectForKey(key);
  return v.isNil() ? null : ObjC.unwrap(v.description);
}

function snapshot() {
  const out = { playing: Request.localIsPlaying };
  const path = Request.localNowPlayingPlayerPath;
  if (!path.isNil() && !path.client.isNil()) {
    out.bundle = ObjC.unwrap(path.client.bundleIdentifier);
    out.pid = path.client.processIdentifier;
  }
  const item = Request.localNowPlayingItem;
  const info = item.isNil() ? null : item.nowPlayingInfo;
  if (info && !info.isNil()) {
    out.elapsed = num(info, 'kMRMediaRemoteNowPlayingInfoElapsedTime');
    out.rate = num(info, 'kMRMediaRemoteNowPlayingInfoPlaybackRate');
    out.duration = num(info, 'kMRMediaRemoteNowPlayingInfoDuration');
    out.title = str(info, 'kMRMediaRemoteNowPlayingInfoTitle');
    out.url = str(info, 'kMRMediaRemoteNowPlayingInfoAssetURL');
    const ts = info.objectForKey('kMRMediaRemoteNowPlayingInfoTimestamp');
    out.timestamp = ts.isNil() ? null : ts.timeIntervalSince1970;
  }
  return out;
}

let last = '';
let lastWrite = 0;
for (;;) {
  const s = snapshot();
  const key = JSON.stringify(s);
  const now = Date.now();
  if (key !== last || now - lastWrite > 2000) {
    s.now = now / 1000;
    stdout.writeData($(JSON.stringify(s) + '\n').dataUsingEncoding($.NSUTF8StringEncoding));
    last = key;
    lastWrite = now;
  }
  delay(0.2);
}
