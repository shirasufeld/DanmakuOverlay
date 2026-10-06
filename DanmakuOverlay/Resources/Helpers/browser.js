// Polls the largest <video> of a browser tab over Apple Events and streams JSON lines.
// argv: [bundleIdentifier, windowID (Safari: CGWindowID), boundsX, boundsY, boundsW, boundsH]
// Requires the browser's "Allow JavaScript from Apple Events" developer setting.
function run(argv) {
  ObjC.import('Foundation');
  const stdout = $.NSFileHandle.fileHandleWithStandardOutput;
  const write = (o) => stdout.writeData($(JSON.stringify(o) + '\n').dataUsingEncoding($.NSUTF8StringEncoding));
  const bundle = argv[0];
  const windowID = Number(argv[1] || 0);
  const target = argv.length >= 6 ? argv.slice(2, 6).map(Number) : null;
  const app = Application(bundle);
  const isSafari = bundle.indexOf('Safari') >= 0;
  const probe = `(() => {
    const vs = [...document.querySelectorAll('video')].filter(v => v.readyState > 0);
    if (!vs.length) return JSON.stringify(null);
    vs.sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight);
    const v = vs[0], r = v.getBoundingClientRect();
    return JSON.stringify({t: v.currentTime, p: v.paused || v.ended, r: v.playbackRate, d: v.duration,
      href: location.href, title: document.title, x: r.left, y: r.top, w: r.width, h: r.height,
      vw: v.videoWidth, vh: v.videoHeight, iw: innerWidth, ih: innerHeight, ow: outerWidth, oh: outerHeight,
      fs: !!document.fullscreenElement});
  })()`;

  function findWindow() {
    const windows = app.windows();
    if (isSafari && windowID) {
      for (const w of windows) { try { if (w.id() === windowID) return w; } catch (e) {} }
    }
    if (target) {
      for (const w of windows) {
        try {
          const b = w.bounds();
          if (Math.abs(b.x - target[0]) < 4 && Math.abs(b.y - target[1]) < 4 &&
              Math.abs(b.width - target[2]) < 4 && Math.abs(b.height - target[3]) < 4) return w;
        } catch (e) {}
      }
    }
    return windows.length ? windows[0] : null;
  }

  let win = null;
  for (;;) {
    try {
      if (!win) win = findWindow();
      if (!win) { write({ error: 'no window' }); delay(1); continue; }
      const t0 = Date.now();
      const result = isSafari
        ? app.doJavaScript(probe, { in: win.currentTab() })
        : win.activeTab().execute({ javascript: probe });
      const t1 = Date.now();
      write({ video: JSON.parse(result || 'null'), at: (t0 + t1) / 2000, rtt: (t1 - t0) / 1000 });
    } catch (e) {
      win = null;
      write({ error: String(e) });
      delay(1);
    }
    delay(0.25);
  }
}
