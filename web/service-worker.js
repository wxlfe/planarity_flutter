self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    (async function () {
      try {
        const cacheNames = await caches.keys();
        await Promise.all(
          cacheNames.map(function (cacheName) {
            return caches.delete(cacheName);
          })
        );
      } catch (_) {}

      await self.registration.unregister();

      const clients = await self.clients.matchAll({
        includeUncontrolled: true,
        type: 'window',
      });

      await Promise.all(
        clients.map(function (client) {
          return client.navigate(client.url);
        })
      );
    })()
  );
});
