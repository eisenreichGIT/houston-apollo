// Houston service worker: shows alerts from your Apollo as notifications (Web Push).
// It doesn't cache anything; the app always loads fresh from the Apollo.
'use strict';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));

self.addEventListener('push', event => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch (e) { d = { body: event.data ? event.data.text() : '' }; }
  event.waitUntil(self.registration.showNotification(d.title || 'Houston', {
    body: d.body || '',
    tag: d.tag || 'houston',
    renotify: true,
    icon: 'icon-192.png',
    badge: 'favicon.png'
  }));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const url = './';                // always Houston itself, never another site
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(wins => {
    for (const w of wins) if ('focus' in w) return w.focus();
    return self.clients.openWindow(url);
  }));
});
