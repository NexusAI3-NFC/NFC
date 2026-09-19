// =====================================================================
// NEXUS · Suscripción a notificaciones push (Web Push), para que un
// aviso llegue a un móvil aunque la app esté cerrada del todo. La
// clave pública VAPID de aquí abajo es pública por diseño (no hace
// falta ocultarla) — la privada solo vive en la Edge Function.
// Compartido entre Control NFC y Agenda.
// =====================================================================
(function () {
  const VAPID_PUBLIC_KEY = 'BOj0PUuKygPNU2OHsfeExvdt6Nk7I-NcKRaZQ77AfCYdT_UAix4CcdY8NW4oH_cOQRdR7YqxWdO_fT84ihfrWZI';

  function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - base64String.length % 4) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const rawData = atob(base64);
    return Uint8Array.from([...rawData].map(c => c.charCodeAt(0)));
  }

  function deviceLabel() {
    const ua = navigator.userAgent;
    let so = 'Dispositivo';
    if (/iPhone|iPad/.test(ua)) so = 'iPhone/iPad';
    else if (/Android/.test(ua)) so = 'Android';
    else if (/Macintosh/.test(ua)) so = 'Mac';
    else if (/Windows/.test(ua)) so = 'Windows';
    let nav = 'navegador';
    if (/Edg/.test(ua)) nav = 'Edge';
    else if (/Chrome/.test(ua)) nav = 'Chrome';
    else if (/Firefox/.test(ua)) nav = 'Firefox';
    else if (/Safari/.test(ua)) nav = 'Safari';
    return `${so} · ${nav}`;
  }

  window.NexusPush = {
    supported: (typeof navigator !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window),

    // Da de alta (o refresca) la suscripción de ESTE dispositivo para
    // el usuario logueado en `sb`. Pide permiso si hace falta. Devuelve
    // { ok: true } o { ok: false, motivo } — nunca lanza sin avisar.
    async subscribe(sb) {
      if (!this.supported) {
        console.warn('NexusPush: este navegador no admite push (serviceWorker/PushManager).');
        return { ok: false, motivo: 'no-soportado' };
      }
      try {
        const permiso = (Notification.permission === 'granted')
          ? 'granted'
          : await Notification.requestPermission();
        if (permiso !== 'granted') return { ok: false, motivo: 'sin-permiso' };

        console.log('NexusPush: esperando el service worker…');
        const reg = await navigator.serviceWorker.ready;
        console.log('NexusPush: service worker listo, suscribiendo…');

        let sub = await reg.pushManager.getSubscription();
        if (!sub) {
          sub = await reg.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
          });
        }
        console.log('NexusPush: suscrito en el navegador, guardando en Supabase…', sub.endpoint);

        const json = sub.toJSON();
        const { data: { user } } = await sb.auth.getUser();
        if (!user) { console.error('NexusPush: no hay sesión de Supabase todavía.'); return { ok: false, motivo: 'sin-sesion' }; }

        const { error } = await sb.from('push_subscriptions').upsert({
          user_id: user.id,
          endpoint: json.endpoint,
          p256dh: json.keys.p256dh,
          auth_key: json.keys.auth,
          device_label: deviceLabel(),
        }, { onConflict: 'endpoint' });

        if (error) { console.error('NexusPush: error guardando la suscripción en Supabase:', error); return { ok: false, motivo: error.message }; }
        console.log('NexusPush: suscripción guardada correctamente.');
        return { ok: true };
      } catch (err) {
        console.error('NexusPush: fallo al suscribirse:', err);
        return { ok: false, motivo: (err && err.message) || String(err) };
      }
    },
  };
})();
