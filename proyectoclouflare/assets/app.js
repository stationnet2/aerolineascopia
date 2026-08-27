// app.js — AlertaTrip Web con Firebase (replica de la app Flutter)
// ============================================================

import {
  allAirports, cityGroups, airportByCode, airportsForCity,
  cityGroupById, nearestCityGroup, popularDestinationsFor,
  refreshCityGroupsFromFirestore
} from './city-airports.js';

const { auth, db, messaging, signInAnonymously, onAuthStateChanged, getToken, onMessage, serverTimestamp } = window._firebase;
const { collection, doc, setDoc, deleteDoc, updateDoc, onSnapshot, query, where, orderBy, limit } = window._firestore;

const API_BASE = '';
const AFFILIATE_MARKER = '761958';
const AFFILIATE_TRS = '560037';
const VAPID_KEY = 'BMtfOU3U44zywoRAZFQDTW8sTl5l3S7FvqNbh4A9lGYgs8tdqrTeNAkRlRPARjIHIzWJDkSGaeScCvcLhFfwHHk';

let state = {
  origin: null, destination: null, tripType: 'roundTrip',
  passengers: 1, anyDate: true, departureDate: null, returnDate: null,
  searching: false, results: null, nearbyDeals: [], nearbyOffers: null,
  detectedCity: null, alerts: [], notifications: [], user: null,
  currentView: 'search', fcmToken: null,
};

const $ = (sel) => document.querySelector(sel);
const fmtDate = (d) => `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')}/${d.getFullYear()}`;
const fmtISODate = (d) => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
const fmtCurrency = (n) => Math.round(n).toLocaleString('es-AR');
const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

function normalize(str) {
  return str.toLowerCase().normalize('NFD').replace(/[\u0300-\u030f]/g, '').replace(/[^a-z0-9\s]/g, '').trim();
}

// ============================================================
// FIREBASE AUTH
// ============================================================
async function initAuth() {
  onAuthStateChanged(auth, async (user) => {
    if (user) {
      state.user = user;
      console.log('[Auth] UID:', user.uid);
      await setupNotifications();
      loadAlertsFromFirestore();
      loadNotificationsFromFirestore();
    } else {
      try { await signInAnonymously(auth); } catch (e) { console.error('Auth failed:', e); }
    }
  });
}

// ============================================================
// FIREBASE MESSAGING
// ============================================================
async function setupNotifications() {
  if (!state.user) return;
  try {
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') return;
    const token = await getToken(messaging, { vapidKey: VAPID_KEY });
    if (!token) return;
    state.fcmToken = token;
    await setDoc(doc(db, 'users', state.user.uid), { fcmToken: token, updatedAt: serverTimestamp() }, { merge: true });
    onMessage(messaging, (payload) => {
      console.log('[FCM] Foreground:', payload);
      if (payload.notification) {
        showToast(`🔔 ${payload.notification.title}: ${payload.notification.body}`);
        loadNotificationsFromFirestore();
      }
    });
  } catch (e) { console.log('[FCM] No disponible:', e); }
}

function showToast(msg) {
  const el = document.createElement('div');
  el.style.cssText = 'position:fixed;top:20px;left:50%;transform:translateX(-50%);background:#12211D;color:white;padding:14px 24px;border-radius:16px;z-index:300;font-weight:700;box-shadow:0 10px 30px rgba(0,0,0,.3);animation:slideDown .3s ease';
  el.textContent = msg;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 5000);
}

// ============================================================
// FIRESTORE — ALERTAS
// ============================================================
function loadAlertsFromFirestore() {
  if (!state.user) return;
  const q = query(collection(db, 'flightAlerts'), where('userId', '==', state.user.uid));
  onSnapshot(q, (snap) => {
    state.alerts = snap.docs.map(d => {
      const data = d.data();
      return {
        id: d.id, ...data,
        dateFrom: data.dateFrom?.toDate ? data.dateFrom.toDate() : (data.dateFrom ? new Date(data.dateFrom) : null),
        dateTo: data.dateTo?.toDate ? data.dateTo.toDate() : (data.dateTo ? new Date(data.dateTo) : null),
        createdAt: data.createdAt?.toDate ? data.createdAt.toDate() : new Date(),
      };
    }).sort((a, b) => b.createdAt - a.createdAt);
    if (state.currentView === 'alerts') renderAlertsView();
  });
}

async function saveAlertToFirestore(alert) {
  if (!state.user) throw new Error('No hay usuario');
  const ref = doc(collection(db, 'flightAlerts'));
  await setDoc(ref, {
    userId: state.user.uid,
    originCityId: alert.originCityId,
    destinationCityId: alert.destinationCityId,
    tripType: alert.tripType,
    flexibleDates: alert.flexibleDates,
    dateFrom: alert.dateFrom ? new Date(alert.dateFrom) : null,
    dateTo: alert.dateTo ? new Date(alert.dateTo) : null,
    maxPrice: alert.maxPrice || null,
    passengers: alert.passengers,
    isActive: true,
    alertThresholdPercent: 15,
    createdAt: serverTimestamp(),
    lastKnownPrice: null,
  });
  return ref.id;
}

async function deleteAlertFromFirestore(id) {
  await deleteDoc(doc(db, 'flightAlerts', id));
}

async function toggleAlertActiveInFirestore(id, isActive) {
  await updateDoc(doc(db, 'flightAlerts', id), { isActive });
}

// ============================================================
// FIRESTORE — NOTIFICACIONES
// ============================================================
function loadNotificationsFromFirestore() {
  if (!state.user) return;
  const q = query(collection(db, 'flightNotifications'), where('userId', '==', state.user.uid), orderBy('createdAt', 'desc'), limit(30));
  onSnapshot(q, (snap) => {
    state.notifications = snap.docs.map(d => {
      const data = d.data();
      return {
        id: d.id, ...data,
        departureDate: data.departureDate?.toDate ? data.departureDate.toDate() : (data.departureDate ? new Date(data.departureDate) : null),
        returnDate: data.returnDate?.toDate ? data.returnDate.toDate() : (data.returnDate ? new Date(data.returnDate) : null),
        createdAt: data.createdAt?.toDate ? data.createdAt.toDate() : new Date(),
      };
    });
    updateAlertBadge();
  });
}

async function markNotificationRead(id) {
  await updateDoc(doc(db, 'flightNotifications', id), { read: true, readAt: serverTimestamp() });
}

async function deleteNotification(id) {
  await deleteDoc(doc(db, 'flightNotifications', id));
}

function updateAlertBadge() {
  const unread = state.notifications.filter(n => !n.read && !n.isTest).length;
  const navAlerts = $('#nav-alerts');
  const existing = navAlerts.querySelector('.badge');
  if (existing) existing.remove();
  if (unread > 0) {
    const badge = document.createElement('span');
    badge.className = 'badge';
    badge.textContent = unread > 9 ? '9+' : String(unread);
    badge.style.cssText = 'position:absolute;top:2px;right:6px;background:#D92D20;color:white;font-size:10px;font-weight:900;padding:2px 6px;border-radius:10px;';
    navAlerts.style.position = 'relative';
    navAlerts.appendChild(badge);
  }
}

// ============================================================
// DETECCIÓN DE UBICACIÓN
// ============================================================
async function detectLocation() {
  if (navigator.geolocation) {
    try {
      const pos = await new Promise((res, rej) => navigator.geolocation.getCurrentPosition(res, rej, { enableHighAccuracy: false, timeout: 8000, maximumAge: 600000 }));
      const city = nearestCityGroup(pos.coords.latitude, pos.coords.longitude);
      if (city) { state.detectedCity = city; state.origin = city; return; }
    } catch (e) { console.log('Geolocación no disponible'); }
  }
  const country = navigator.language?.split('-')[1] || 'AR';
  const popular = popularDestinationsFor(country);
  if (popular.length > 0) { state.detectedCity = popular[0]; state.origin = popular[0]; }
  else { const ba = cityGroupById('buenos_aires'); state.detectedCity = ba; state.origin = ba; }
}

// ============================================================
// API — VUELOS
// ============================================================
async function fetchSpecialOffers(originCityId) {
  const codes = airportsForCity(originCityId);
  if (!codes.length) return [];
  const res = await fetch(`${API_BASE}/special-offers?origin=${codes[0]}&currency=usd`);
  if (!res.ok) return [];
  const json = await res.json();
  if (json.success !== true) return [];
  const currency = (json.currency || 'usd').toUpperCase();
  return (json.data || []).map(e => ({
    originAirportCode: e.origin_airport || codes[0],
    destinationAirportCode: e.destination_airport || e.destination || '',
    price: Number(e.price), currency,
    departureDate: new Date(e.departure_at),
    returnDate: e.return_at ? new Date(e.return_at) : null,
    airline: e.airline || '',
    affiliateLink: buildAffiliateLink(e.link),
    transfers: e.transfers || 0,
  }));
}

async function searchDeals({ originCityId, destinationCityId, dateFrom, dateTo }) {
  const originCodes = airportsForCity(originCityId).slice(0, 2);
  const destCodes = airportsForCity(destinationCityId).slice(0, 2);
  const futures = [];
  for (const o of originCodes) {
    for (const d of destCodes) {
      const params = new URLSearchParams({ origin: o, destination: d, currency: 'usd' });
      if (dateFrom) params.set('departure_at', fmtISODate(dateFrom));
      if (dateTo) params.set('return_at', fmtISODate(dateTo));
      futures.push(fetch(`${API_BASE}/search-flights?${params}`).then(r => r.ok ? r.json() : null));
    }
  }
  const responses = await Promise.all(futures);
  let allDeals = [];
  for (const json of responses) {
    if (!json || json.success !== true) continue;
    const currency = (json.currency || 'usd').toUpperCase();
    for (const e of (json.data || [])) {
      allDeals.push({
        originAirportCode: e.origin_airport || e.origin || '',
        destinationAirportCode: e.destination_airport || e.destination || '',
        price: Number(e.price), currency,
        departureDate: new Date(e.departure_at),
        returnDate: e.return_at ? new Date(e.return_at) : null,
        airline: e.airline || '',
        affiliateLink: buildAffiliateLink(e.link),
        transfers: e.transfers || 0,
        durationMinutes: e.duration || null,
      });
    }
  }
  allDeals.sort((a, b) => a.price - b.price);
  return allDeals;
}

async function searchNearestDates({ originCityId, destinationCityId, departureDate, returnDate }) {
  const previous = [], next = [];
  const tripLength = returnDate ? Math.round((returnDate - departureDate) / 86400000) : null;
  for (let offset = 1; offset <= 60 && (previous.length < 2 || next.length < 2); offset++) {
    if (previous.length < 2) {
      const d = new Date(departureDate); d.setDate(d.getDate() - offset);
      if (d >= new Date(Date.now() - 86400000)) {
        const deals = await searchDeals({ originCityId, destinationCityId, dateFrom: d, dateTo: tripLength ? new Date(d.getTime() + tripLength * 86400000) : null });
        if (deals.length) previous.push({ requestedDate: d, deals });
      }
    }
    if (next.length < 2) {
      const d = new Date(departureDate); d.setDate(d.getDate() + offset);
      const deals = await searchDeals({ originCityId, destinationCityId, dateFrom: d, dateTo: tripLength ? new Date(d.getTime() + tripLength * 86400000) : null });
      if (deals.length) next.push({ requestedDate: d, deals });
    }
  }
  return [...previous, ...next];
}

function buildAffiliateLink(rawLink) {
  if (!rawLink) return '';
  try {
    const url = new URL(rawLink);
    const params = new URLSearchParams(url.search);
    params.set('marker', AFFILIATE_MARKER);
    params.set('locale', 'es');
    return `https://www.aviasales.com${url.pathname}?${params.toString()}`;
  } catch { return rawLink; }
}

function buildKlookLink(dest, checkIn, checkOut, passengers) {
  if (!dest || !dest.klookSvalue) {
    return `https://tp.media/r?campaign_id=137&marker=${AFFILIATE_MARKER}&p=4110&trs=${AFFILIATE_TRS}&u=${encodeURIComponent('https://www.klook.com/es/hotels/')}`;
  }
  const fmt = (d) => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
  const searchUrl = new URL('https://www.klook.com/es/hotels/searchresult/');
  searchUrl.searchParams.set('check_in', fmt(checkIn));
  searchUrl.searchParams.set('check_out', fmt(checkOut));
  searchUrl.searchParams.set('room_num', '1');
  searchUrl.searchParams.set('adult_num', String(passengers));
  searchUrl.searchParams.set('stype', dest.klookStype || 'city');
  searchUrl.searchParams.set('svalue', dest.klookSvalue);
  searchUrl.searchParams.set('city_id', dest.klookCityId || dest.klookSvalue);
  return `https://tp.media/r?campaign_id=137&marker=${AFFILIATE_MARKER}&p=4110&trs=${AFFILIATE_TRS}&u=${encodeURIComponent(searchUrl.toString())}`;
}

// ============================================================
// RENDER
// ============================================================
function init() {
  initAuth();
  detectLocation().then(() => { renderSearchView(); loadNearbyOffers(); });
  setupNavigation();
  tryLoadCatalog();
}

async function tryLoadCatalog() {
  try {
    const res = await fetch('/admin-destinations?collection=destinations', { headers: { 'x-admin-key': 'public-read' } });
    if (res.ok) { const json = await res.json(); if (json.docs?.length) refreshCityGroupsFromFirestore(json.docs); }
  } catch (e) {}
}

async function loadNearbyOffers() {
  const city = state.detectedCity || state.origin;
  if (!city) return;
  try { state.nearbyOffers = await fetchSpecialOffers(city.id); }
  catch (e) { state.nearbyOffers = []; }
  renderNearbyOffers();
}

function setupNavigation() {
  $('#nav-search').addEventListener('click', () => { state.currentView = 'search'; renderSearchView(); });
  $('#nav-alerts').addEventListener('click', () => { state.currentView = 'alerts'; renderAlertsView(); });
  $('#nav-create').addEventListener('click', () => { state.currentView = 'create-alert'; renderCreateAlertView(); });
}

function renderSearchView() {
  setView('view-search', 'search');
  updateSearchForm();
  renderNearbyOffers();
}

function setView(viewId, navKey) {
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  $(`#${viewId}`).classList.add('active');
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  if (navKey === 'search') $('#nav-search').classList.add('active');
  if (navKey === 'alerts') $('#nav-alerts').classList.add('active');
  if (navKey === 'create') $('#nav-create').classList.add('active');
}

function updateSearchForm() {
  $('#origin-display').textContent = state.origin?.displayName || 'Elegir ciudad';
  $('#origin-country').textContent = state.origin?.country || '';
  $('#dest-display').textContent = state.destination?.displayName || 'Elegir ciudad';
  $('#dest-country').textContent = state.destination?.country || '';
  $('#passengers-count').textContent = state.passengers;
  $('#trip-type-oneway').classList.toggle('active', state.tripType === 'oneWay');
  $('#trip-type-round').classList.toggle('active', state.tripType === 'roundTrip');
  $('#any-date-toggle').checked = state.anyDate;
  $('#date-picker-area').style.display = state.anyDate ? 'none' : 'block';
  $('#date-display').textContent = state.anyDate ? 'Cualquier fecha'
    : state.tripType === 'oneWay' ? (state.departureDate ? fmtDate(state.departureDate) : 'Elegir fecha')
    : (state.departureDate && state.returnDate ? `${fmtDate(state.departureDate)} — ${fmtDate(state.returnDate)}` : 'Elegir fechas');
}

function renderNearbyOffers() {
  const container = $('#nearby-offers');
  if (!state.nearbyOffers) { container.innerHTML = '<div class="spinner"></div>'; return; }
  if (state.nearbyOffers.length === 0) { container.innerHTML = '<p class="muted">No hay ofertas destacadas en este momento.</p>'; return; }
  const byCity = new Map(), byCode = new Map();
  for (const deal of state.nearbyOffers) {
    const city = cityGroupForAirport(deal.destinationAirportCode);
    if (city) { const cur = byCity.get(city.id); if (!cur || deal.price < cur.price) byCity.set(city.id, deal); }
    else { const cur = byCode.get(deal.destinationAirportCode); if (!cur || deal.price < cur.price) byCode.set(deal.destinationAirportCode, deal); }
  }
  const cityEntries = Array.from(byCity.entries()).sort((a, b) => a[1].price - b[1].price);
  const rawEntries = Array.from(byCode.entries()).sort((a, b) => a[1].price - b[1].price);
  let html = '';
  for (const [cityId, deal] of cityEntries) {
    const city = cityGroupById(cityId);
    html += buildExploreCard(city?.displayName || deal.destinationAirportCode, city?.country || '', deal.price, deal.currency, city?.imageUrl, deal.affiliateLink);
  }
  for (const [code, deal] of rawEntries) {
    const ap = airportByCode(code);
    html += buildExploreCard(ap?.name || code, '', deal.price, deal.currency, null, deal.affiliateLink);
  }
  container.innerHTML = html;
}

function buildExploreCard(title, country, price, currency, imageUrl, link) {
  const bg = imageUrl ? `style="background-image:url('${imageUrl}')"` : '';
  return `<a class="explore-card" ${bg} href="${escapeHtml(link)}" target="_blank" rel="noopener">
    <div class="explore-overlay"></div>
    <span class="explore-price">${currency} ${fmtCurrency(price)}</span>
    <div class="explore-info"><div class="explore-title">${escapeHtml(title)}</div>${country ? `<div class="explore-country">${escapeHtml(country)}</div>` : ''}</div>
  </a>`;
}

function cityGroupForAirport(code) { const ap = airportByCode(code); return ap ? cityGroupById(ap.cityGroupId) : null; }

function renderResults() {
  const container = $('#results-area');
  console.log('[renderResults] searching:', state.searching, 'results:', state.results?.length);
  if (state.searching) { container.innerHTML = '<div class="spinner"></div><p class="center muted">Buscando las mejores opciones...</p>'; return; }
  if (!state.results) { container.innerHTML = ''; return; }
  if (state.results.length === 0) {
    container.innerHTML = `<div class="card"><h3>No encontramos vuelos</h3><p class="muted">Proba con otras fechas o ciudades. También podés <a href="#" onclick="app.goCreate();return false;">crear una alerta</a>.</p></div>`;
    return;
  }
  let html = '<h2 class="section-title">✈ Mejores opciones</h2>';
  if (state.usedDefaultDates) html += `<p class="muted">Precios de referencia saliendo el ${fmtDate(state.searchedDepartureDate)} y volviendo una semana después.</p>`;
  for (const deal of state.results.slice(0, 10)) {
    try {
      html += buildDealCard(deal);
    } catch (e) {
      console.error('[renderResults] Error renderizando deal:', deal, e);
    }
  }
  console.log('[renderResults] HTML generado, longitud:', html.length);
  container.innerHTML = html;
}

function buildDealCard(deal) {
  const originAp = airportByCode(deal.originAirportCode), destAp = airportByCode(deal.destinationAirportCode);
  const originName = originAp?.name || deal.originAirportCode, destName = destAp?.name || deal.destinationAirportCode;
  const totalPrice = deal.price * state.passengers;
  const isRoundTrip = deal.returnDate != null;
  return `<div class="deal-card">
    <div class="deal-header"><div class="deal-price">${deal.currency} ${fmtCurrency(totalPrice)}</div><span class="deal-badge ${deal.transfers === 0 ? 'direct' : 'stop'}">${deal.transfers === 0 ? 'Directo' : deal.transfers + ' escala(s)'}</span></div>
    ${state.passengers > 1 ? `<div class="deal-sub">Total para ${state.passengers} pasajeros (${deal.currency} ${fmtCurrency(deal.price)} c/u)</div>` : ''}
    <div class="deal-legs">
      <div class="deal-leg"><span class="leg-icon">🛫</span><div><div class="leg-label">Ida · ${fmtDate(deal.departureDate)}</div><div class="leg-route">${escapeHtml(originName)} → ${escapeHtml(destName)}</div></div></div>
      ${isRoundTrip ? `<div class="deal-leg"><span class="leg-icon">🛬</span><div><div class="leg-label">Vuelta · ${fmtDate(deal.returnDate)}</div><div class="leg-route">${escapeHtml(destName)} → ${escapeHtml(originName)}</div></div></div>` : ''}
    </div>
    <div class="deal-meta">${escapeHtml(deal.airline)}${deal.durationMinutes ? ` · ${Math.floor(deal.durationMinutes/60)}h ${deal.durationMinutes%60}m` : ''}</div>
    <a href="${escapeHtml(deal.affiliateLink)}" target="_blank" rel="noopener" class="btn btn-primary deal-btn">Ver oferta</a>
  </div>`;
}

function renderNearbyDateAlternatives() {
  const container = $('#nearby-dates-area');
  if (!state.nearbyDeals?.length) { container.innerHTML = ''; return; }
  const best = state.results?.[0];
  let bestAlt = null;
  for (const alt of state.nearbyDeals) { const d = alt.deals[0]; if (d && (!bestAlt || d.price < bestAlt.price)) bestAlt = d; }
  const hasSaving = best && bestAlt && bestAlt.price < best.price;
  let html = '<h2 class="section-title">📅 Fechas cercanas disponibles</h2>';
  if (hasSaving) html += `<div class="saving-banner">💰 Podés ahorrar ${best.currency} ${fmtCurrency((best.price - bestAlt.price) * state.passengers)}</div>`;
  for (const alt of state.nearbyDeals) {
    const deal = alt.deals[0];
    const isBest = bestAlt && deal === bestAlt;
    html += `<a href="${escapeHtml(deal.affiliateLink)}" target="_blank" class="nearby-card ${isBest ? 'best' : ''}">
      <div class="nearby-info"><div class="nearby-date">${fmtDate(alt.requestedDate)}</div><div class="nearby-type">${deal.returnDate ? fmtDate(alt.requestedDate)+' → '+fmtDate(deal.returnDate) : 'Solo ida'}</div><span class="nearby-link">Ver y reservar →</span></div>
      <div class="nearby-price">${deal.currency} ${fmtCurrency(deal.price * state.passengers)}${isBest ? '<span class="best-tag">MEJOR PRECIO</span>' : ''}</div>
    </a>`;
  }
  container.innerHTML = html;
}

function renderAlertsView() {
  setView('view-alerts', 'alerts');
  const container = $('#alerts-list');
  const unreadNotifs = state.notifications.filter(n => !n.read && !n.isTest);
  let html = '';
  if (unreadNotifs.length > 0) {
    html += `<div style="background:linear-gradient(135deg,#D92D20,#FF6B35);color:white;border-radius:24px;padding:18px;margin-bottom:20px;">
      <div style="font-weight:900;font-size:16px;margin-bottom:4px">🔔 ¡TENÉS ${unreadNotifs.length} ALERTA${unreadNotifs.length===1?'':'S'} ENCONTRADA!</div>
      <div style="font-size:13px;opacity:.9">Abrí la oferta para ver el precio y reservar antes de que cambie.</div>
    </div>`;
    for (const n of unreadNotifs.slice(0, 5)) {
      const origin = cityGroupById(n.originCityId), dest = cityGroupById(n.destinationCityId);
      html += `<div style="background:white;border-radius:20px;padding:16px;margin-bottom:12px;border:2px solid #D92D20;box-shadow:0 4px 16px rgba(217,45,32,.1)">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
          <span style="background:#FFE4E1;color:#D92D20;font-size:10px;font-weight:900;padding:4px 10px;border-radius:20px">🚨 ALERTA NUEVA</span>
          <button onclick="app.dismissNotif('${n.id}')" style="background:none;border:none;font-size:18px;cursor:pointer">✕</button>
        </div>
        <div style="font-weight:900;font-size:18px;margin-bottom:4px">${origin?.displayName||n.origin} → ${dest?.displayName||n.destination}</div>
        <div style="font-size:13px;color:var(--muted);margin-bottom:12px">${n.body}</div>
        <div style="background:#F1F8FF;border-radius:16px;padding:14px;display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
          <span style="font-weight:700;color:#475467">Precio encontrado</span>
          <span style="font-size:24px;font-weight:900;color:#0B5ED7">${n.currency} ${fmtCurrency(n.price)}</span>
        </div>
        <a href="${escapeHtml(n.affiliateLink)}" target="_blank" onclick="app.markRead('${n.id}')" class="btn btn-primary" style="width:100%">Ver y reservar este vuelo</a>
      </div>`;
    }
  }
  html += '<h2 class="section-title">Tus alertas activas</h2>';
  if (state.alerts.length === 0) {
    html += `<div class="empty-state"><div class="empty-icon">🔔</div><h3>No tenés alertas guardadas</h3><p class="muted">Creá una para que te avisemos cuando baje el precio.</p><button class="btn btn-primary" onclick="app.goCreate()">Crear alerta</button></div>`;
  } else {
    for (const alert of state.alerts) {
      const origin = cityGroupById(alert.originCityId), dest = cityGroupById(alert.destinationCityId);
      const parts = [];
      if (alert.flexibleDates) parts.push('Fechas flexibles');
      else if (alert.dateFrom && alert.dateTo) parts.push(`${fmtDate(alert.dateFrom)} — ${fmtDate(alert.dateTo)}`);
      else if (alert.dateFrom) parts.push(fmtDate(alert.dateFrom));
      if (alert.maxPrice) parts.push(`Tope: USD ${fmtCurrency(alert.maxPrice)}`);
      html += `<div class="alert-card ${alert.isActive ? '' : 'inactive'}">
        <div class="alert-info"><div class="alert-route">${origin?.displayName || alert.originCityId} → ${dest?.displayName || alert.destinationCityId}</div><div class="alert-meta">${parts.join(' · ')} · ${alert.passengers} pasajero${alert.passengers > 1 ? 's' : ''}</div></div>
        <div class="alert-actions"><label class="switch"><input type="checkbox" ${alert.isActive ? 'checked' : ''} onchange="app.toggleAlert('${alert.id}')"><span></span></label><button class="btn-icon" onclick="app.deleteAlert('${alert.id}')">🗑</button></div>
      </div>`;
    }
  }
  container.innerHTML = html;
}

function renderCreateAlertView() {
  setView('view-create-alert', 'create');
  alertOrigin = state.origin; alertDestination = null;
  $('#alert-origin-display').textContent = alertOrigin?.displayName || 'Elegir ciudad';
  $('#alert-dest-display').textContent = 'Elegir ciudad';
  $('#alert-trip-oneway').classList.remove('active');
  $('#alert-trip-round').classList.add('active');
  $('#alert-flexible').checked = false;
  $('#alert-date-area').style.display = 'block';
  $('#alert-passengers').textContent = '1';
  $('#alert-maxprice').value = '';
  $('#alert-create-btn').disabled = true;
  $('#alert-date-display').textContent = 'Elegir fechas';
  $('#alert-date-display').dataset.from = '';
  $('#alert-date-display').dataset.to = '';
  updateAlertForm();
}

// ============================================================
// EVENTOS DEL BUSCADOR
// ============================================================
$('#origin-btn').addEventListener('click', () => openCityPicker('origin'));
$('#dest-btn').addEventListener('click', () => openCityPicker('destination'));
$('#swap-btn').addEventListener('click', () => { const tmp = state.origin; state.origin = state.destination; state.destination = tmp; updateSearchForm(); });
$('#trip-type-oneway').addEventListener('click', () => { state.tripType = 'oneWay'; updateSearchForm(); });
$('#trip-type-round').addEventListener('click', () => { state.tripType = 'roundTrip'; updateSearchForm(); });
$('#passengers-minus').addEventListener('click', () => { if (state.passengers > 1) { state.passengers--; updateSearchForm(); } });
$('#passengers-plus').addEventListener('click', () => { if (state.passengers < 9) { state.passengers++; updateSearchForm(); } });
$('#any-date-toggle').addEventListener('change', (e) => { state.anyDate = e.target.checked; if (state.anyDate) { state.departureDate = null; state.returnDate = null; } updateSearchForm(); });
$('#date-btn').addEventListener('click', () => {
  if (state.anyDate) return;
  if (state.tripType === 'oneWay') {
    const d = prompt('Fecha de ida (YYYY-MM-DD):', fmtISODate(new Date(Date.now() + 7*86400000)));
    if (d) { state.departureDate = new Date(d); state.anyDate = false; }
  } else {
    const d1 = prompt('Fecha de ida (YYYY-MM-DD):', fmtISODate(new Date(Date.now() + 7*86400000)));
    const d2 = prompt('Fecha de vuelta (YYYY-MM-DD):', fmtISODate(new Date(Date.now() + 14*86400000)));
    if (d1 && d2) { state.departureDate = new Date(d1); state.returnDate = new Date(d2); state.anyDate = false; }
  }
  updateSearchForm();
});
$('#search-btn').addEventListener('click', performSearch);

async function performSearch() {
  if (!state.origin || !state.destination) { alert('Elegí origen y destino'); return; }
  if (state.origin.id === state.destination.id) { alert('El destino debe ser diferente al origen'); return; }
  state.searching = true; state.results = null; state.nearbyDeals = []; state.usedDefaultDates = false; state.searchedDepartureDate = null;
  renderResults(); $('#nearby-dates-area').innerHTML = '';
  try {
    const isOneWay = state.tripType === 'oneWay';
    let departure = isOneWay ? state.departureDate : (state.anyDate ? null : state.departureDate);
    let returnDate = isOneWay ? null : (state.anyDate ? null : state.returnDate);
    if (!isOneWay && state.anyDate && !departure) { departure = new Date(Date.now() + 7*86400000); returnDate = new Date(Date.now() + 14*86400000); state.usedDefaultDates = true; }
    state.results = await searchDeals({ originCityId: state.origin.id, destinationCityId: state.destination.id, dateFrom: departure, dateTo: returnDate });
    console.log('[performSearch] Resultados:', state.results?.length);
    state.searchedDepartureDate = departure;
    if (!state.anyDate && departure) state.nearbyDeals = await searchNearestDates({ originCityId: state.origin.id, destinationCityId: state.destination.id, departureDate: departure, returnDate });
    renderResults(); renderNearbyDateAlternatives();
    $('#results-area').scrollIntoView({ behavior: 'smooth', block: 'start' });
  } catch (e) { $('#results-area').innerHTML = `<div class="error-box">No pudimos buscar precios ahora. Proba de nuevo.</div>`; }
  finally { state.searching = false; }
}

// ============================================================
// SELECTOR DE CIUDADES
// ============================================================
function openCityPicker(target) {
  const modal = $('#city-modal'), input = $('#city-search-input'), list = $('#city-search-results');
  modal.style.display = 'flex'; input.value = ''; input.focus();
  renderCityList(list, '', target);
  input.oninput = debounce(() => renderCityList(list, input.value, target), 150);
  $('#city-modal-close').onclick = () => modal.style.display = 'none';
  modal.onclick = (e) => { if (e.target === modal) modal.style.display = 'none'; };
}

function renderCityList(container, query, target) {
  const q = normalize(query);
  let cities = !q ? popularDestinationsFor(navigator.language?.split('-')[1] || 'AR') : cityGroups.filter(c => {
    const nq = normalize(q);
    if (normalize(c.displayName).includes(nq)) return true;
    if (normalize(c.country).includes(nq)) return true;
    for (const code of c.airportCodes) { const ap = airportByCode(code); if (ap && (normalize(ap.iataCode).includes(nq) || normalize(ap.name).includes(nq))) return true; }
    return false;
  }).sort((a, b) => {
    const nq = normalize(q), score = (c) => { const city = normalize(c.displayName), country = normalize(c.country); if (city === nq) return 0; if (city.startsWith(nq)) return 1; if (country === nq) return 2; if (country.startsWith(nq)) return 3; return 4; };
    return score(a) - score(b);
  });
  const other = target === 'origin' ? state.destination : state.origin;
  cities = cities.filter(c => !other || c.id !== other.id);
  if (!cities.length) { container.innerHTML = '<div class="city-empty">No encontramos ese destino.</div>'; return; }
  container.innerHTML = cities.map(c => {
    const codes = c.airportCodes.map(code => airportByCode(code)?.iataCode || code).join(' · ');
    return `<div class="city-item" data-id="${c.id}"><div class="city-icon">✈</div><div class="city-info"><div class="city-name">${escapeHtml(c.displayName)}</div><div class="city-meta">${escapeHtml(c.country)} · ${codes}</div></div></div>`;
  }).join('');
  container.querySelectorAll('.city-item').forEach(el => el.addEventListener('click', () => {
    const city = cityGroupById(el.dataset.id);
    if (target === 'origin') state.origin = city; else state.destination = city;
    $('#city-modal').style.display = 'none'; updateSearchForm();
  }));
}

// ============================================================
// CREAR ALERTA
// ============================================================
let alertOrigin = null, alertDestination = null;
$('#alert-origin-btn').addEventListener('click', () => openCityPickerForAlert('origin'));
$('#alert-dest-btn').addEventListener('click', () => openCityPickerForAlert('destination'));
$('#alert-trip-oneway').addEventListener('click', () => { $('#alert-trip-oneway').classList.add('active'); $('#alert-trip-round').classList.remove('active'); updateAlertForm(); });
$('#alert-trip-round').addEventListener('click', () => { $('#alert-trip-round').classList.add('active'); $('#alert-trip-oneway').classList.remove('active'); updateAlertForm(); });
$('#alert-flexible').addEventListener('change', (e) => { $('#alert-date-area').style.display = e.target.checked ? 'none' : 'block'; updateAlertForm(); });
$('#alert-passengers-minus').addEventListener('click', () => { let n = parseInt($('#alert-passengers').textContent); if (n > 1) $('#alert-passengers').textContent = n - 1; });
$('#alert-passengers-plus').addEventListener('click', () => { let n = parseInt($('#alert-passengers').textContent); if (n < 9) $('#alert-passengers').textContent = n + 1; });
$('#alert-date-btn').addEventListener('click', () => {
  const isRound = $('#alert-trip-round').classList.contains('active');
  if (isRound) {
    const d1 = prompt('Fecha de ida (YYYY-MM-DD):', fmtISODate(new Date(Date.now() + 7*86400000)));
    const d2 = prompt('Fecha de vuelta (YYYY-MM-DD):', fmtISODate(new Date(Date.now() + 14*86400000)));
    if (d1 && d2) { $('#alert-date-display').dataset.from = d1; $('#alert-date-display').dataset.to = d2; $('#alert-date-display').textContent = `${fmtDate(new Date(d1))} — ${fmtDate(new Date(d2))}`; }
  } else {
    const d = prompt('Fecha de ida (YYYY-MM-DD):', fmtISODate(new Date(Date.now() + 7*86400000)));
    if (d) { $('#alert-date-display').dataset.from = d; $('#alert-date-display').dataset.to = ''; $('#alert-date-display').textContent = fmtDate(new Date(d)); }
  }
  updateAlertForm();
});
$('#alert-maxprice').addEventListener('input', updateAlertForm);
$('#alert-create-btn').addEventListener('click', async () => {
  const isRound = $('#alert-trip-round').classList.contains('active');
  const isFlexible = $('#alert-flexible').checked;
  try {
    await saveAlertToFirestore({
      originCityId: alertOrigin.id, destinationCityId: alertDestination.id,
      tripType: isRound ? 'roundTrip' : 'oneWay', flexibleDates: isFlexible,
      dateFrom: isFlexible ? null : $('#alert-date-display').dataset.from,
      dateTo: isFlexible ? null : ($('#alert-date-display').dataset.to || null),
      maxPrice: parseFloat($('#alert-maxprice').value) || null,
      passengers: parseInt($('#alert-passengers').textContent),
    });
    alertOrigin = null; alertDestination = null;
    showToast('✅ Alerta guardada. Te avisamos cuando baje el precio.');
    renderAlertsView();
  } catch (e) { alert('No se pudo guardar: ' + e.message); }
});

function openCityPickerForAlert(target) {
  const modal = $('#city-modal'), input = $('#city-search-input'), list = $('#city-search-results');
  modal.style.display = 'flex'; input.value = ''; input.focus();
  renderCityListForAlert(list, '', target);
  input.oninput = debounce(() => renderCityListForAlert(list, input.value, target), 150);
  $('#city-modal-close').onclick = () => modal.style.display = 'none';
}
function renderCityListForAlert(container, query, target) {
  const q = normalize(query);
  let cities = !q ? popularDestinationsFor(navigator.language?.split('-')[1] || 'AR') : cityGroups.filter(c => {
    const nq = normalize(q); if (normalize(c.displayName).includes(nq)) return true; if (normalize(c.country).includes(nq)) return true;
    for (const code of c.airportCodes) { const ap = airportByCode(code); if (ap && (normalize(ap.iataCode).includes(nq) || normalize(ap.name).includes(nq))) return true; }
    return false;
  });
  const other = target === 'origin' ? alertDestination : alertOrigin;
  cities = cities.filter(c => !other || c.id !== other.id);
  if (!cities.length) { container.innerHTML = '<div class="city-empty">No encontramos ese destino.</div>'; return; }
  container.innerHTML = cities.map(c => {
    const codes = c.airportCodes.map(code => airportByCode(code)?.iataCode || code).join(' · ');
    return `<div class="city-item" data-id="${c.id}"><div class="city-icon">✈</div><div class="city-info"><div class="city-name">${escapeHtml(c.displayName)}</div><div class="city-meta">${escapeHtml(c.country)} · ${codes}</div></div></div>`;
  }).join('');
  container.querySelectorAll('.city-item').forEach(el => el.addEventListener('click', () => {
    const city = cityGroupById(el.dataset.id);
    if (target === 'origin') { alertOrigin = city; $('#alert-origin-display').textContent = city.displayName; }
    else { alertDestination = city; $('#alert-dest-display').textContent = city.displayName; }
    $('#city-modal').style.display = 'none'; updateAlertForm();
  }));
}
function updateAlertForm() {
  const hasOrigin = alertOrigin != null, hasDest = alertDestination != null;
  const isFlexible = $('#alert-flexible').checked;
  const hasDates = isFlexible || $('#alert-date-display').dataset.from;
  $('#alert-create-btn').disabled = !(hasOrigin && hasDest && alertOrigin.id !== alertDestination.id && hasDates);
}

// ============================================================
// HOTELES / EXCURSIONES
// ============================================================
$('#klook-btn').addEventListener('click', () => {
  const dest = state.destination, checkIn = state.departureDate || new Date(Date.now() + 14*86400000), checkOut = state.returnDate || new Date(checkIn.getTime() + 5*86400000);
  window.open(buildKlookLink(dest, checkIn, checkOut, state.passengers), '_blank');
});
$('#kkday-btn').addEventListener('click', () => {
  window.open(`https://tp.media/r?campaign_id=633&marker=${AFFILIATE_MARKER}&p=9074&trs=${AFFILIATE_TRS}&u=${encodeURIComponent('https://www.kkday.com/es/')}`, '_blank');
});

// ============================================================
// HELPERS
// ============================================================
function escapeHtml(text) { const div = document.createElement('div'); div.textContent = text; return div.innerHTML; }

window.app = {
  goCreate: () => { state.currentView = 'create-alert'; renderCreateAlertView(); },
  toggleAlert: (id) => toggleAlertActiveInFirestore(id, !state.alerts.find(a => a.id === id)?.isActive),
  deleteAlert: (id) => { if (confirm('¿Borrar esta alerta?')) deleteAlertFromFirestore(id); },
  markRead: (id) => markNotificationRead(id),
  dismissNotif: (id) => deleteNotification(id),
};

document.addEventListener('DOMContentLoaded', init);