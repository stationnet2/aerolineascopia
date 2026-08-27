importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyC0fG4mn_VxKEd2oZotK6-rPd1x1lN7Q-Q",
  authDomain: "alerta-vuelos-49ba1.firebaseapp.com",
  projectId: "alerta-vuelos-49ba1",
  storageBucket: "alerta-vuelos-49ba1.firebasestorage.app",
  messagingSenderId: "700792010765",
  appId: "1:700792010765:web:26993d2778f1118c037d44"
});

const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  self.registration.showNotification(payload.notification.title, {
    body: payload.notification.body,
    icon: '/icon-192.png',
    data: payload.data
  });
});