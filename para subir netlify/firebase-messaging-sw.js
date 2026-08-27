importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC0fG4mn_VxKEd2oZotK6-rPd1x1lN7Q-Q',
  appId: '1:700792010765:web:26993d2778f1118c037d44',
  messagingSenderId: '700792010765',
  projectId: 'alerta-vuelos-49ba1',
  authDomain: 'alerta-vuelos-49ba1.firebaseapp.com',
  storageBucket: 'alerta-vuelos-49ba1.firebasestorage.app',
});

const messaging = firebase.messaging();