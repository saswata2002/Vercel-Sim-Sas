// Open in Vercel Sim: a vercel.app page opened in Safari (a link tapped in WhatsApp, Mail,
// Messages, Notes…) is handed to the app with its full URL. Once per tab, so choosing
// Cancel on Safari's "Open in Vercel Sim?" prompt just stays on the page.
(() => {
  if (window.top !== window) return;
  try {
    const key = '__vercelSimBounced:' + location.href;
    if (sessionStorage.getItem(key)) return;
    sessionStorage.setItem(key, '1');
  } catch (_) {}
  location.href = 'vercelsim://open?url=' + encodeURIComponent(location.href);
})();
