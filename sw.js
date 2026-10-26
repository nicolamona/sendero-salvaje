// Recuperación de emergencia: retirar el service worker que puede servir una versión vieja del juego.
self.addEventListener("install", event => {
  event.waitUntil(self.skipWaiting());
});
self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter(name => name.startsWith("sendero-salvaje-")).map(name => caches.delete(name)));
    await self.registration.unregister();
    const clientsList = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    await Promise.all(clientsList.map(client => {
      try {
        const url = new URL(client.url);
        if (url.origin === self.location.origin && url.pathname.startsWith("/sendero-salvaje/")) {
          url.searchParams.set("recuperacion", "sw-retirado-20261026");
          return client.navigate(url.href);
        }
      } catch (_) {}
      return Promise.resolve();
    }));
  })());
});
