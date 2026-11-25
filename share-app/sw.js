// Installability only: Chrome wants a service worker with a fetch handler. Nothing is cached.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("fetch", () => {});
