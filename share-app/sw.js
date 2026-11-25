// Receives the phone's share-menu POST (a static site can't): text goes to the page in the address,
// files wait in the Cache until the page has uploaded them. Nothing else is cached.
const FILES = "crew-share-files";
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", (e) => {
  if (e.request.method === "POST" && new URL(e.request.url).pathname === "/share-target") e.respondWith(receive(e.request));
});

async function receive(request) {
  const form = await request.formData();
  const files = form.getAll("media").filter((f) => typeof f !== "string" && f.size);
  if (!files.length) {
    const q = new URLSearchParams();
    for (const k of ["title", "text", "url"]) if (typeof form.get(k) === "string") q.set(k, form.get(k));
    return Response.redirect(`/?${q}`, 303);
  }
  const cache = await caches.open(FILES);
  const stamp = Date.now();
  await Promise.all(files.map((f, i) => cache.put(`/shared-files/${stamp}-${i}`, new Response(f, { headers: { "x-name": encodeURIComponent(f.name), "x-id": crypto.randomUUID(), "x-at": new Date(stamp).toISOString(), "content-type": f.type || "application/octet-stream" } }))));
  return Response.redirect("/?files=1", 303);
}
