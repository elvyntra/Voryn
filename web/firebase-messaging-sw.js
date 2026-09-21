// Firebase Messaging Service Worker for Voryn Web Push & PWA
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

self.addEventListener('push', function(event) {
  if (event.data) {
    try {
      const payload = event.data.json();
      const data = payload.data || {};
      if (data.type === 'call_message') {
        const title = data.sender_name || 'Voryn Message';
        const options = {
          body: data.remind_to_call === 'true' ? '📞 ' + data.body : data.body,
          icon: '/icons/Icon-192.png',
          badge: '/favicon.png',
          data: {
            url: '/messages/thread/' + data.thread_id,
            thread_id: data.thread_id,
          },
        };
        event.waitUntil(self.registration.showNotification(title, options));
      }
    } catch (e) {
      console.error('[SW] push handling error', e);
    }
  }
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const url = event.notification.data ? event.notification.data.url : '/messages';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (let i = 0; i < clientList.length; i++) {
        const client = clientList[i];
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          client.navigate(url);
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(url);
      }
    })
  );
});
