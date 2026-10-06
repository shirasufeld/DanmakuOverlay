// Polls VLC over Apple Events and streams JSON lines: whole-second position plus state.
// Each sample carries the wall-clock midpoint of the query so the app can stamp it precisely.
function run(argv) {
  ObjC.import('Foundation');
  const stdout = $.NSFileHandle.fileHandleWithStandardOutput;
  const write = (o) => stdout.writeData($(JSON.stringify(o) + '\n').dataUsingEncoding($.NSUTF8StringEncoding));
  const vlc = Application('VLC');
  for (;;) {
    try {
      if (!vlc.running()) {
        write({ running: false });
        delay(1);
        continue;
      }
      const t0 = Date.now();
      const seconds = vlc.currentTime();
      const t1 = Date.now();
      write({
        running: true,
        seconds: seconds,
        playing: vlc.playing(),
        duration: vlc.durationOfCurrentItem(),
        path: vlc.pathOfCurrentItem(),
        name: vlc.nameOfCurrentItem(),
        at: (t0 + t1) / 2000,
        rtt: (t1 - t0) / 1000,
      });
    } catch (e) {
      write({ error: String(e) });
      delay(1);
    }
    delay(0.08 + Math.random() * 0.04);
  }
}
