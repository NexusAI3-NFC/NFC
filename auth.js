// =====================================================================
// NEXUS · Login compartido (Supabase Auth) para las apps internas
// (Control NFC y Agenda). NO se usa en páginas públicas de cliente
// (catalogo.html, seguimiento-cliente.html, menu.html) — esas siguen
// sin login, a propósito.
//
// Qué hace:
// 1. Si no hay sesión de Supabase, pide email + contraseña.
// 2. Si llegas desde un enlace de invitación de Supabase, pide que
//    elijas contraseña antes de entrar.
// 3. "Recordar en este dispositivo" guarda CUÁNDO se verificó la
//    contraseña por última vez en este móvil/ordenador. Si pasan más
//    de 7 días, se vuelve a pedir aunque el token de Supabase siga
//    siendo técnicamente válido — Supabase Auth no controla esto por
//    sí solo con esa granularidad, así que se lleva a mano.
// =====================================================================
(function () {
  const REMEMBER_KEY = 'nexus_auth_verified_at';
  const REMEMBER_DAYS = 7;
  const REMEMBER_MS = REMEMBER_DAYS * 24 * 60 * 60 * 1000;

  let resolveReady;
  window.NexusAuth = {
    ready: new Promise((resolve) => { resolveReady = resolve; }),
  };

  function el(html) {
    const t = document.createElement('template');
    t.innerHTML = html.trim();
    return t.content.firstChild;
  }

  function lastVerifiedOk() {
    const raw = localStorage.getItem(REMEMBER_KEY);
    if (!raw) return false;
    const t = parseInt(raw, 10);
    return !!t && (Date.now() - t) < REMEMBER_MS;
  }

  function markVerifiedNow(remember) {
    if (remember) localStorage.setItem(REMEMBER_KEY, String(Date.now()));
    else localStorage.removeItem(REMEMBER_KEY);
  }

  async function fetchNombre(sb, userId, fallbackEmail) {
    const { data } = await sb.from('socios').select('nombre').eq('user_id', userId).maybeSingle();
    return (data && data.nombre) || fallbackEmail;
  }

  function loginOverlay(sb, onDone) {
    const overlay = el(`
      <div class="modal-overlay" id="nexusAuthOverlay">
        <div class="modal-box">
          <h3>Nexus — Acceso</h3>
          <p id="nexusAuthError" style="color:#D9534F; display:none;"></p>
          <div class="field"><input type="email" id="nexusAuthEmail" placeholder="Email" autocomplete="username"></div>
          <div class="field"><input type="password" id="nexusAuthPass" placeholder="Contraseña" autocomplete="current-password"></div>
          <label style="display:flex; align-items:center; gap:8px; font-size:13px; margin-bottom:18px; color:var(--paper-dim, #C9C2B4);">
            <input type="checkbox" id="nexusAuthRemember" checked style="width:16px; height:16px;">
            Recordar en este dispositivo (7 días)
          </label>
          <button class="btn-submit" id="nexusAuthSubmit">Entrar</button>
        </div>
      </div>`);
    document.body.appendChild(overlay);

    const emailInput = overlay.querySelector('#nexusAuthEmail');
    const passInput = overlay.querySelector('#nexusAuthPass');
    const errEl = overlay.querySelector('#nexusAuthError');
    const btn = overlay.querySelector('#nexusAuthSubmit');

    async function submit() {
      const email = emailInput.value.trim();
      const password = passInput.value;
      const remember = overlay.querySelector('#nexusAuthRemember').checked;
      errEl.style.display = 'none';
      if (!email || !password) return;
      btn.disabled = true; btn.textContent = 'Entrando…';
      const { data, error } = await sb.auth.signInWithPassword({ email, password });
      btn.disabled = false; btn.textContent = 'Entrar';
      if (error) {
        errEl.textContent = 'Email o contraseña incorrectos.';
        errEl.style.display = 'block';
        return;
      }
      markVerifiedNow(remember);
      overlay.remove();
      onDone(data.session.user);
    }

    btn.onclick = submit;
    passInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
  }

  function setPasswordOverlay(sb, onDone) {
    const overlay = el(`
      <div class="modal-overlay" id="nexusSetPassOverlay">
        <div class="modal-box">
          <h3>Bienvenido a Nexus</h3>
          <p>Elige tu contraseña para activar tu cuenta.</p>
          <p id="nexusSetPassError" style="color:#D9534F; display:none;"></p>
          <div class="field"><input type="password" id="nexusNewPass" placeholder="Contraseña (mín. 8 caracteres)" autocomplete="new-password"></div>
          <div class="field"><input type="password" id="nexusNewPass2" placeholder="Repite la contraseña" autocomplete="new-password"></div>
          <button class="btn-submit" id="nexusSetPassSubmit">Guardar y entrar</button>
        </div>
      </div>`);
    document.body.appendChild(overlay);

    const errEl = overlay.querySelector('#nexusSetPassError');
    const btn = overlay.querySelector('#nexusSetPassSubmit');

    btn.onclick = async () => {
      const p1 = overlay.querySelector('#nexusNewPass').value;
      const p2 = overlay.querySelector('#nexusNewPass2').value;
      errEl.style.display = 'none';
      if (p1.length < 8) { errEl.textContent = 'Mínimo 8 caracteres.'; errEl.style.display = 'block'; return; }
      if (p1 !== p2) { errEl.textContent = 'Las contraseñas no coinciden.'; errEl.style.display = 'block'; return; }
      btn.disabled = true; btn.textContent = 'Guardando…';
      const { data, error } = await sb.auth.updateUser({ password: p1 });
      btn.disabled = false; btn.textContent = 'Guardar y entrar';
      if (error) {
        errEl.textContent = 'No se pudo guardar: ' + error.message;
        errEl.style.display = 'block';
        return;
      }
      markVerifiedNow(true);
      overlay.remove();
      onDone(data.user);
    };
  }

  window.NexusAuth.init = async function (sb) {
    const hash = window.location.hash || '';
    const search = window.location.search || '';
    const isInviteOrRecovery = /type=(invite|recovery)/.test(hash) || /type=(invite|recovery)/.test(search);

    const finish = async (user) => {
      const nombre = await fetchNombre(sb, user.id, user.email);
      if (window.history && history.replaceState) {
        history.replaceState(null, '', window.location.pathname + window.location.search.replace(/([?&])(type|access_token|refresh_token|expires_in|token_type)=[^&]*/g, ''));
      }
      resolveReady({ user, nombre });
    };

    const { data: { session } } = await sb.auth.getSession();

    if (session && isInviteOrRecovery) {
      setPasswordOverlay(sb, finish);
      return;
    }

    if (session && lastVerifiedOk()) {
      finish(session.user);
      return;
    }

    if (session && !lastVerifiedOk()) {
      // Token técnicamente válido, pero han pasado >7 días (o nunca se
      // marcó "recordar"): se pide la contraseña otra vez a propósito.
      await sb.auth.signOut();
    }

    loginOverlay(sb, finish);
  };

  window.NexusAuth.signOut = async function (sb) {
    if (!confirm('¿Cerrar sesión en este dispositivo?')) return;
    localStorage.removeItem(REMEMBER_KEY);
    await sb.auth.signOut();
    window.location.reload();
  };
})();
