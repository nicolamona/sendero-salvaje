const CACHE = "sendero-salvaje-v44";
const FILES = ["./", "./index.html", "./manifest.json", "./icon.svg"];
self.addEventListener("install", e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting())));
self.addEventListener("activate", e => e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  const url = new URL(e.request.url);
  const isPage = e.request.mode === "navigate" || url.pathname.endsWith("/index.html") || url.pathname.endsWith("/sendero-salvaje/");
  if (isPage) {
    e.respondWith(fetch(e.request, {cache:"no-store"}).then(response => {
      if (response && response.ok) caches.open(CACHE).then(c => c.put(e.request, response.clone()));
      return response;
    }).catch(() => caches.match(e.request).then(cached => cached || caches.match("./index.html"))));
    return;
  }
  e.respondWith(caches.match(e.request).then(cached => cached || fetch(e.request).then(response => {
    const copy = response.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return response;
  }).catch(() => caches.match("./index.html"))));
});
