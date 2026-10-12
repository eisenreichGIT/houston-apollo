// Houston app. Served by Houston on the Apollo; no outside scripts.
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const KEY = 'apolloToken';               // same key as the old Apollo Remote page: no sign-in needed after upgrading
  const BROWSER_TZ = (() => { try { return Intl.DateTimeFormat().resolvedOptions().timeZone || null; } catch (e) { return null; } })();

  // ---------------------------------------------------------------- icons
  const ICON = {
    control: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M12 3v8"/><path d="M6.3 6.8a8 8 0 1 0 11.4 0"/></svg>',
    schedule: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>',
    stats: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 20h16"/><path d="M7 16v-5M12 16V6M17 16v-8"/></svg>',
    settings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>',
    alert: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>',
    activity: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 12h4l3-7 4 14 3-7h4"/></svg>',
    super_eco: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 16a8 8 0 0 1 16 0"/><path d="M12 16L6.4 14"/><circle cx="12" cy="16" r="1.6" fill="currentColor" stroke="none"/></svg>',
    eco: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 16a8 8 0 0 1 16 0"/><path d="M12 16L8.6 11.1"/><circle cx="12" cy="16" r="1.6" fill="currentColor" stroke="none"/></svg>',
    balanced: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 16a8 8 0 0 1 16 0"/><path d="M12 16L12 10"/><circle cx="12" cy="16" r="1.6" fill="currentColor" stroke="none"/></svg>',
    turbo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 16a8 8 0 0 1 16 0"/><path d="M12 16L16.9 12.6"/><circle cx="12" cy="16" r="1.6" fill="currentColor" stroke="none"/></svg>',
    custom: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/></svg>',
    sun: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
    moon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/></svg>',
    start: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5v14l11-7z"/></svg>',
    stop: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M6 6h12v12H6z"/></svg>',
    restart: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M20 12a8 8 0 1 1-2.3-5.6M20 4v5h-5"/></svg>',
    saved: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
    fail: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M12 7v6M12 17h.01"/><circle cx="12" cy="12" r="9.5"/></svg>',
    node: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><ellipse cx="12" cy="6" rx="7.5" ry="3"/><path d="M4.5 6v6c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3V6M4.5 12v6c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3v-6"/></svg>',
    update: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 16.5v-9M8 11l4-4 4 4"/></svg>',
    light: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 18h6M10 21h4"/><path d="M12 3a6 6 0 0 0-3.6 10.8c.6.5 1 1.2 1.1 2.2h5c.1-1 .5-1.7 1.1-2.2A6 6 0 0 0 12 3z"/></svg>',
    trash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V4h6v3"/></svg>'
  };
  const MODE_INFO = {
    super_eco: { name: 'Super Eco', hint: 'lowest power' },
    eco: { name: 'Eco', hint: 'quietest' },
    balanced: { name: 'Balanced', hint: 'middle' },
    turbo: { name: 'Turbo', hint: 'fastest, loud' }
  };

  // ---------------------------------------------------------------- state
  let token = null, III = false, device = null, busy = false, timer = null, view = 'control';
  const cur = { status: null, mode: null, node: null, hr: null };
  let hrTouched = false;
  let units = 'F', settings = null, statsRange = '24h', statsTimer = null, fleetTimer = null, statsData = null, loadedAt = Date.now();
  const MODE_KEYS = ['super_eco', 'eco', 'balanced', 'turbo', 'custom'];
  // CSS color for a mode, from the theme tokens, so it follows light / dark without redrawing
  const modeColor = t => { const k = t && t.startsWith('custom') ? 'custom' : t; return MODE_KEYS.includes(k) ? 'var(--m-' + k + ')' : 'var(--m-other)'; };
  const toUnit = c => units === 'F' ? c * 9 / 5 + 32 : c;
  const fromUnit = v => units === 'F' ? (v - 32) * 5 / 9 : v;
  const fmtTemp = c => c == null || isNaN(c) ? '–' : Math.round(toUnit(c)) + '°' + units;
  const fmtDur = sec => { if (sec == null) return '–'; sec = Math.max(0, Math.round(sec)); const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
    return d ? d + 'd ' + h + 'h' : h ? h + 'h ' + m + 'm' : m + 'm'; };
  const ago = sec => sec < 60 ? 'just now' : sec < 3600 ? Math.round(sec / 60) + ' min ago' : sec < 86400 ? Math.round(sec / 3600) + ' h ago' : Math.round(sec / 86400) + ' d ago';
  const bigWords = n => { if (n == null || isNaN(n)) return '–'; const a = Math.abs(n);
    return a >= 1e12 ? (n / 1e12).toFixed(2) + ' trillion' : a >= 1e9 ? (n / 1e9).toFixed(2) + ' billion' : a >= 1e6 ? (n / 1e6).toFixed(2) + ' million' : Math.round(n).toLocaleString(); };
  const shortNum = n => { n = n || 0; const a = Math.abs(n);
    return a >= 1e9 ? (n / 1e9).toFixed(1) + 'B' : a >= 1e6 ? (n / 1e6).toFixed(1) + 'M' : a >= 1e4 ? Math.round(n / 1e3) + 'K' : a >= 1e3 ? (n / 1e3).toFixed(1) + 'K' : String(Math.round(n)); };
  const money = x => x == null ? '–' : ((settings && settings.currency) || '$') + (x < 10 ? x.toFixed(2) : Math.round(x).toLocaleString());
  const node = { status: null, solo: false, available: null, useMutation: null, busy: false };
  let saved = null, draft = null, upcomingList = [], nowExpected = null, authorized = true, schedLoaded = false;

  // ---------------------------------------------------------------- helpers
  const store = {
    get() { try { return localStorage.getItem(KEY); } catch (e) { return null; } },
    set(v) { try { localStorage.setItem(KEY, v); } catch (e) {} },
    clear() { try { localStorage.removeItem(KEY); } catch (e) {} }
  };
  const el = (tag, attrs, ...kids) => {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (k === 'class') n.className = v;
      else if (k === 'html') n.innerHTML = v;          // only ever used with the constant icons above
      else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
      else if (v === true) n.setAttribute(k, '');
      else if (v !== false && v != null) n.setAttribute(k, v);
    }
    for (const c of kids) if (c != null) n.append(c.nodeType ? c : document.createTextNode(c));
    return n;
  };
  const modeName = t => {
    if (!t) return '';
    if (t.startsWith('custom:')) return t.slice(7) + ' TH/s';
    return (MODE_INFO[t] && MODE_INFO[t].name) || t;
  };
  const modeToken = (m, hr) => m === 'custom' ? 'custom:' + hr : m;
  const modeIcon = t => ICON[t && t.startsWith('custom') ? 'custom' : t] || ICON.restart;
  const pad = n => String(n).padStart(2, '0');
  const fmtTime = hhmm => {
    if (!hhmm) return '';
    const [h, m] = hhmm.split(':').map(Number);
    return new Date(2000, 0, 1, h, m).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  };
  const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const fmtDays = days => {
    const s = [...days].sort((a, b) => a - b).join(',');
    if (s === '1,2,3,4,5,6,7') return 'Every day';
    if (s === '1,2,3,4,5') return 'Weekdays';
    if (s === '6,7') return 'Weekends';
    const parts = []; let i = 0; const d = [...days].sort((a, b) => a - b);
    while (i < d.length) {
      let j = i; while (j + 1 < d.length && d[j + 1] === d[j] + 1) j++;
      parts.push(j - i >= 2 ? DAYS[d[i] - 1] + '–' + DAYS[d[j] - 1] : d.slice(i, j + 1).map(x => DAYS[x - 1]).join(', '));
      i = j + 1;
    }
    return parts.join(', ');
  };
  const minutes = hhmm => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };

  let toastTimer = null;
  function toast(text, kind, ms) {
    const t = $('toast');
    if (!text) { t.classList.add('hidden'); return; }
    t.textContent = text; t.className = kind || '';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.add('hidden'), ms || (kind === 'err' ? 7000 : 4500));
  }

  function ask(title, text, yes, opts) {
    opts = opts || {};
    return new Promise(resolve => {
      $('dlgTitle').textContent = title; $('dlgText').textContent = text || '';
      $('dlgYes').textContent = yes || 'OK'; $('dlgNo').textContent = opts.no || 'Cancel';
      $('dlgYes').className = 'primary' + (opts.danger ? ' danger' : '');
      $('scrim').classList.remove('hidden'); $('dlgYes').focus();
      const done = v => {
        $('scrim').classList.add('hidden');
        $('dlgYes').onclick = $('dlgNo').onclick = $('scrim').onclick = null; document.onkeydown = null;
        resolve(v);
      };
      $('dlgYes').onclick = () => done(true);
      $('dlgNo').onclick = () => done(false);
      $('scrim').onclick = e => { if (e.target === $('scrim')) done(false); };
      document.onkeydown = e => { if (e.key === 'Escape') done(false); };
    });
  }

  const unreachable = () => `Can't reach Houston at ${location.hostname}. Away from home? Make sure Tailscale is connected.`;

  async function gql(query, variables, timeoutMs) {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), timeoutMs || 20000);
    try {
      const headers = { 'Content-Type': 'application/json' };
      if (token) headers.Authorization = 'Bearer ' + token;
      const r = await fetch('api/graphql', { method: 'POST', headers, body: JSON.stringify({ query, variables: variables || {} }), signal: ctrl.signal });
      const j = await r.json();
      if (j.errors && j.errors.length) {
        const e = new Error(j.errors[0].message);
        e.code = j.errors[0].extensions && j.errors[0].extensions.code;
        throw e;
      }
      return j.data;
    } catch (e) {
      if (e.name === 'AbortError') throw new Error('timeout');
      if (e instanceof TypeError) throw new Error(unreachable());
      throw e;
    } finally { clearTimeout(t); }
  }

  async function rest(method, path, body) {
    let r;
    try {
      r = await fetch(path, { method, headers: Object.assign({ Authorization: 'Bearer ' + token },
        body ? { 'Content-Type': 'application/json' } : {}), body: body ? JSON.stringify(body) : undefined, cache: 'no-store' });
    } catch (e) { throw new Error(unreachable()); }
    let j = null; try { j = await r.json(); } catch (e) {}
    if (r.status === 401) { const e = new Error('Please sign in again.'); e.code = 'UNAUTHENTICATED'; throw e; }
    if (r.status === 404 && path.indexOf('api/') === 0) throw new Error('This Houston is older than the app: update it on the Apollo (install-houston.sh).');
    if (!r.ok) throw new Error((j && j.error) || ('Error ' + r.status));
    return j;
  }

  function handleAuthError(e) {
    if (e.code === 'UNAUTHENTICATED') { showLogin(); toast('Signed out. Please sign in again.', 'err'); return true; }
    return false;
  }

  // ---------------------------------------------------------------- tabs
  const TABS = [['control', 'Home'], ['stats', 'Stats'], ['schedule', 'Schedule'], ['activity', 'Activity'], ['settings', 'Settings']];
  for (const nav of [$('tabsTop'), $('tabbar')]) {
    for (const [id, name] of TABS) {
      nav.append(el('button', { class: 'tab', type: 'button', role: 'tab', 'data-tab': id, 'aria-selected': 'false',
        onclick: () => go(id) }, el('span', { html: ICON[id], style: 'display:contents' }), name));
    }
  }
  // ---------------------------------------------------------------- appearance (per device)
  const THEME_KEY = 'houstonTheme';
  const lightQuery = window.matchMedia ? window.matchMedia('(prefers-color-scheme: light)') : null;
  const themePref = () => document.documentElement.dataset.theme || 'dark';
  const isLight = () => { const p = themePref(); return p === 'light' || (p === 'system' && !!(lightQuery && lightQuery.matches)); };
  function applyTheme(p, save) {
    if (['light', 'dark', 'system'].indexOf(p) < 0) p = 'dark';
    document.documentElement.dataset.theme = p;
    if (save) { try { localStorage.setItem(THEME_KEY, p); } catch (e) {} }
    const light = isLight();
    document.querySelector('meta[name="theme-color"]').setAttribute('content', light ? '#F6F4EE' : '#0F100D');
    const tb = $('themeBtn'); tb.innerHTML = light ? ICON.moon : ICON.sun;   // constant icon markup only
    tb.setAttribute('aria-label', light ? 'Switch to dark mode' : 'Switch to light mode'); tb.title = tb.getAttribute('aria-label');
    setSeg($('themeSeg'), 'theme', p);
  }
  $('themeBtn').addEventListener('click', () => applyTheme(isLight() ? 'dark' : 'light', true));
  document.querySelectorAll('#themeSeg [data-theme]').forEach(b => b.addEventListener('click', () => applyTheme(b.dataset.theme, true)));
  if (lightQuery && lightQuery.addEventListener) lightQuery.addEventListener('change', () => { if (themePref() === 'system') applyTheme('system'); });
  applyTheme(themePref());

  async function go(id, opts) {
    if (view === 'schedule' && id !== 'schedule' && isDirty() && !(opts && opts.force)) {
      const leave = await ask('Leave without saving?', 'Your schedule changes haven\'t been saved.', 'Discard changes', { no: 'Keep editing', danger: true });
      if (!leave) return;
      draft = clone(saved); renderSchedule();
    }
    view = id;
    document.querySelectorAll('.tab').forEach(b => b.setAttribute('aria-selected', String(b.dataset.tab === id)));
    for (const [t] of TABS) $('view-' + t).classList.toggle('hidden', t !== id);
    window.scrollTo(0, 0);
    clearInterval(statsTimer); clearInterval(fleetTimer); clearInterval(logTimer);
    if (id === 'control') { refresh(true); loadFleet(); fleetTimer = setInterval(() => { if (!document.hidden) loadFleet(); }, 30000); }
    if (id === 'stats') { loadStats(); statsTimer = setInterval(() => { if (!document.hidden) loadStats(true); }, 60000); }
    if (id === 'schedule') loadSchedule();
    if (id === 'activity') { if (opts && opts.pane) actPane = opts.pane; showPane(); }
    if (id === 'settings') renderSettings();
  }

  // ---------------------------------------------------------------- sign in / out
  function showLogin() {
    token = null; store.clear();
    for (const [t] of TABS) $('view-' + t).classList.add('hidden');
    ['tabsTop', 'tabbar', 'logoutBtn'].forEach(i => $(i).classList.add('hidden'));
    $('login').classList.remove('hidden'); $('pw').value = ''; $('pw').focus();
    clearInterval(timer); clearInterval(statsTimer); clearInterval(fleetTimer); clearInterval(priceTimer); clearInterval(logTimer); clearTimeout(updTimer); upd = null; price = null; renderPrice(); schedLoaded = false; saved = draft = null; node.available = null; settings = null;
  }

  async function showApp(first) {
    $('login').classList.add('hidden');
    await loadSettings();
    ['tabsTop', 'tabbar', 'logoutBtn'].forEach(i => $(i).classList.remove('hidden'));
    let act = pendingAction; pendingAction = null;
    // A link like …:8088/#stop could be sent by anyone, so ask first, except from a home-screen
    // shortcut (opened as an app), where one tap is the point.
    const standalone = (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true;
    if (act && !standalone) {
      const what = act === 'start' ? 'Start the miner' : act === 'stop' ? 'Stop the miner' : act === 'node_start' ? 'Start the Bitcoin node'
        : act === 'node_stop' ? 'Stop the Bitcoin node' : act.startsWith('custom:') ? 'Set a custom target of ' + act.slice(7) + ' TH/s' : 'Switch to ' + modeName(act);
      if (!(await ask(what + '?', 'This link asks Houston to do that. Only continue if you opened it yourself.', 'Continue'))) act = null;
    }
    go(pendingTab === 'logs' ? 'activity' : pendingTab || 'control', { force: true, pane: pendingTab === 'logs' ? 'logs' : null }); pendingTab = null;
    if (act === 'start' || act === 'stop') action(act);
    else if (act === 'node_start' || act === 'node_stop') nodeAction(act.slice(5));
    else if (act && MODE_INFO[act]) setMode(act);
    else if (act && act.startsWith('custom:')) setMode('custom', parseInt(act.slice(7), 10));
    clearInterval(timer);
    timer = setInterval(() => { if (!document.hidden && !busy && view === 'control') refresh(true); }, 10000);
    loadSchedule(true);   // for the "next change" card
    loadUpdate(false);    // for the "new Apollo software" card
    loadPrice(); clearInterval(priceTimer);
    priceTimer = setInterval(() => { if (!document.hidden) loadPrice(); }, 60000);
  }

  $('loginForm').addEventListener('submit', async ev => {
    ev.preventDefault();
    toast('Signing in…');
    try {
      token = null;
      const d = await gql('query ($p: String!) { Auth { login(input: { password: $p }) { result { accessToken } error { message } } } }', { p: $('pw').value });
      const l = d.Auth.login;
      if (l.error || !l.result) throw new Error(l.error ? l.error.message : 'Sign-in failed');
      token = l.result.accessToken; store.set(token);
      toast(''); showApp();
    } catch (e) { toast(/invalid|password/i.test(e.message) ? 'Wrong password. Use your Apollo dashboard password.' : e.message, 'err'); }
  });
  $('logoutBtn').addEventListener('click', async () => {
    if (view === 'schedule' && isDirty() && !(await ask('Sign out?', 'Your schedule changes haven\'t been saved.', 'Sign out', { danger: true }))) return;
    showLogin();
  });

  // ---------------------------------------------------------------- control
  function buildModes() {
    const box = $('modes'); box.textContent = '';
    const list = III ? ['super_eco', 'eco', 'balanced', 'turbo'] : ['eco', 'balanced', 'turbo'];
    for (const m of list) {
      const hint = m === 'eco' && III ? 'quiet' : MODE_INFO[m].hint;
      box.append(el('button', { class: 'mode', type: 'button', 'data-mode': m, 'aria-label': MODE_INFO[m].name + ' mode', style: '--mc:' + modeColor(m),
        onclick: () => pickMode(m) }, el('span', { html: ICON[m], style: 'display:contents' }), MODE_INFO[m].name, el('small', {}, hint)));
    }
    box.classList.toggle('four', III);
    $('customRow').classList.toggle('hidden', !III);
  }

  function setStatus(s) {
    const st = (s || 'unknown').toLowerCase();
    $('dot').className = 'dot ' + st;
    $('statusText').textContent = st;
    $('startBtn').disabled = busy || st === 'online';
    $('stopBtn').disabled = busy || st === 'offline';
    renderModes();
  }

  function renderModes() {
    document.querySelectorAll('.mode').forEach(b => {
      b.classList.toggle('active', b.dataset.mode === cur.mode);
      b.disabled = busy || !cur.mode;
    });
    if (III) {
      $('customRow').classList.toggle('active', cur.mode === 'custom');
      if (!hrTouched && cur.hr) $('hrRange').value = cur.hr;
      $('hrVal').textContent = $('hrRange').value + ' TH/s';
      $('hrApply').disabled = $('hrRange').disabled = busy || !cur.mode;
    }
  }

  function renderModeBadge() {
    const mb = $('modeBadge'), mt = cur.mode === 'custom' ? 'custom:' + cur.hr : cur.mode;
    if (!mt) { mb.classList.add('hidden'); return; }
    mb.innerHTML = modeIcon(mt);            // constant icon markup only
    mb.append(mt.startsWith('custom:') ? 'Custom ' + modeName(mt) : modeName(mt));
    mb.style.setProperty('--mc', modeColor(mt)); mb.classList.remove('hidden');
  }

  const fmt = (n, d) => (n == null || isNaN(n)) ? '–' : n.toFixed(d);

  async function refresh(quiet) {
    try {
      const d = await gql(`query {
        Miner {
          online { result { online { status } } error { message } }
          stats { result { stats { master { boardsW upTime intervals { int_30 { bySol } } } pool { host intervals { int_0 { sharesAccepted sharesRejected } } }
            fans { int_0 { rpm } } slots { int_0 { temperature } } } ckpool { pool { hashrate1hr } } } error { message } }
        }
        Settings { read { result { settings { minerMode ${III ? 'minerHashrate ' : ''}nodeSoftware } } error { message } } }
      }`);
      const status = d.Miner.online.result && d.Miner.online.result.online.status;
      const st = d.Settings.read.result && d.Settings.read.result.settings;
      cur.status = (status || '').toLowerCase();
      if (st) { cur.mode = st.minerMode; cur.node = st.nodeSoftware; cur.hr = st.minerHashrate || null; }
      setStatus(status);
      const boards = (d.Miner.stats.result && d.Miner.stats.result.stats) || [];
      const live = cur.status === 'online' && boards.length;
      const ghs = boards.reduce((a, b) => a + ((b.master && b.master.intervals && b.master.intervals.int_30 && b.master.intervals.int_30.bySol) || 0), 0);
      const w = boards.reduce((a, b) => a + ((b.master && b.master.boardsW) || 0), 0);
      const temps = boards.map(b => b.slots && b.slots.int_0 && b.slots.int_0.temperature).filter(t => t != null);
      $('hash').textContent = live ? fmt(ghs / 1000, 2) : cur.status === 'offline' ? '0.00' : '–';
      $('hash').classList.toggle('idle', !live);
      $('watts').textContent = live ? fmt(w, 0) : '–';
      $('temp').textContent = live && temps.length ? String(Math.round(toUnit(Math.max(...temps)))) : '–';
      $('tempUnit').textContent = '°' + units;
      const b0 = boards[0] || {};
      const rpm = boards.flatMap(b => (b.fans && b.fans.int_0 && b.fans.int_0.rpm) || []).filter(Boolean);
      const acc = boards.reduce((a, b) => a + ((b.pool && b.pool.intervals && b.pool.intervals.int_0 && b.pool.intervals.int_0.sharesAccepted) || 0), 0);
      const rej = boards.reduce((a, b) => a + ((b.pool && b.pool.intervals && b.pool.intervals.int_0 && b.pool.intervals.int_0.sharesRejected) || 0), 0);
      $('dEff').textContent = live && ghs ? (w / (ghs / 1000)).toFixed(1) : '–';
      $('dFan').textContent = live && rpm.length ? Math.round(rpm.reduce((a, b) => a + b, 0) / rpm.length).toLocaleString() : '–';
      $('dShares').textContent = live ? shortNum(acc) + ' / ' + shortNum(rej) : '–';
      $('dUp').textContent = live && b0.master && b0.master.upTime ? fmtDur(b0.master.upTime) : '–';
      const solo = d.Miner.stats.result && d.Miner.stats.result.ckpool && d.Miner.stats.result.ckpool.pool;
      const host = b0.pool && b0.pool.host;
      $('poolLine').textContent = !live ? '' : solo ? 'Mining to the solo pool on this Apollo' : host ? 'Pool: ' + host : '';
      renderModeBadge();
      $('updated').textContent = 'updated ' + new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' });
      if (!quiet) toast('');
      if (!node.busy) nodeRefresh();
    } catch (e) {
      if (handleAuthError(e)) return;
      setStatus('unknown');
      if (!quiet || !document.hidden) toast(e.message, 'err');
    }
  }

  async function action(name) {
    busy = true; setStatus(cur.status);
    $('dot').className = 'dot pending';
    $('statusText').textContent = name === 'start' ? 'Starting…' : 'Stopping…';
    toast(name === 'start' ? 'Starting… the Apollo resets its hashboard first (about 45 seconds).' : 'Stopping…', '', 60000);
    try {
      const d = await gql(`query { Miner { ${name} { error { message } } } }`, {}, 180000);
      const err = d.Miner[name].error;
      if (err) throw new Error(err.message);
      toast(name === 'start' ? 'Started. It may show “pending” for a minute while hashing ramps up.' : 'Miner stopped.', 'ok');
    } catch (e) {
      if (handleAuthError(e)) { busy = false; return; }
      toast(e.message === 'timeout' ? 'No reply yet. The Apollo may still be working; check again in a minute.' : e.message, 'err');
    } finally {
      busy = false;
      await refresh(true);
    }
  }

  // ---------------------------------------------------------------- Bitcoin node
  const fmtBytes = b => { const n = Number(b); if (!n) return '–'; return n >= 1e12 ? (n / 1e12).toFixed(2) + ' TB' : (n / 1e9).toFixed(0) + ' GB'; };

  async function nodeCheckStorage() {
    // Apollo software 2.1.4+ reports whether there's a drive for the blockchain (some Apollo III ship without one).
    // Houston tells us whether this Apollo has that check, so older software isn't sent a request it rejects.
    const f = device && device.features;
    if (f && f.nodeStorage === false) { node.available = true; return; }
    try {
      const d = await gql('query { Node { storage { result { state available } } } }');
      node.available = !(d.Node.storage.result && d.Node.storage.result.available === false);
    } catch (e) {
      if (handleAuthError(e)) return;
      node.available = true;            // older software: no storage check, assume a drive
    }
  }

  async function nodeRefresh() {
    if (node.available === null) await nodeCheckStorage();
    $('nodeCard').classList.remove('hidden');
    $('nodeNoDrive').classList.toggle('hidden', node.available !== false);
    $('nodeBody').classList.toggle('hidden', node.available === false);
    if (node.available === false) return;
    try {
      const d = await gql(`query {
        Node {
          online { result { online { status } } }
          stats { result { stats { connectionCount blockchainInfo { blocks headers verificationprogress sizeOnDisk } } } }
        }
        Settings { read { result { settings { nodeEnableSoloMining } } } }
      }`);
      const st = ((d.Node.online.result && d.Node.online.result.online.status) || 'unknown').toLowerCase();
      if (!node.busy) node.status = st;
      const set = d.Settings.read.result && d.Settings.read.result.settings;
      node.solo = !!(set && set.nodeEnableSoloMining);
      $('logSolo').classList.toggle('hidden', !node.solo);
      const s = d.Node.stats.result && d.Node.stats.result.stats;
      const bi = s && s.blockchainInfo;
      const live = st === 'online' && bi;
      if (!node.busy) { $('nodeDot').className = 'dot ' + st; $('nodeStatus').textContent = st; }
      const prog = live && bi.verificationprogress != null ? bi.verificationprogress : null;
      const synced = prog != null && (prog > 0.9999 || (bi.headers && bi.blocks >= bi.headers - 1));
      $('nodeSync').textContent = !live ? '' : synced ? 'Synced' : 'Syncing ' + (prog * 100).toFixed(1) + '%';
      $('nodeBar').classList.toggle('hidden', !live || synced);
      $('nodeBarFill').style.width = live && prog != null ? (prog * 100).toFixed(1) + '%' : '0';
      $('nodeHeight').textContent = live && bi.blocks != null ? bi.blocks.toLocaleString() : '–';
      $('nodePeers').textContent = live && s.connectionCount != null ? String(s.connectionCount) : '–';
      $('nodeDisk').textContent = live ? fmtBytes(bi.sizeOnDisk) : '–';
      $('nodeSoloNote').classList.toggle('hidden', !node.solo);
      renderNodeButtons();
    } catch (e) {
      if (handleAuthError(e)) return;
      $('nodeDot').className = 'dot'; $('nodeStatus').textContent = 'unknown'; renderNodeButtons();
    }
  }

  function renderNodeButtons() {
    $('nodeStartBtn').disabled = node.busy || node.status === 'online' || node.status === 'pending';
    $('nodeStopBtn').disabled = node.busy || node.status === 'offline';
  }

  // Apollo software 2.1.4+ takes node start/stop as a mutation; older software only as a query
  async function nodeSend(name) {
    const f = device && device.features;
    if (node.useMutation === null && f && typeof f.nodeMutation === 'boolean') node.useMutation = f.nodeMutation;
    if (node.useMutation !== false) {
      try {
        const d = await gql(`mutation { Node { ${name} { error { message } } } }`, {}, 150000);
        node.useMutation = true; return d.Node[name].error;
      } catch (e) {
        if (!/on type "?Mutation"?|not configured for mutations/i.test(e.message)) throw e;
        node.useMutation = false;
      }
    }
    const d = await gql(`query { Node { ${name} { error { message } } } }`, {}, 150000);
    return d.Node[name].error;
  }

  async function nodeAction(name) {
    node.busy = true; renderNodeButtons();
    $('nodeDot').className = 'dot pending';
    $('nodeStatus').textContent = name === 'start' ? 'Starting…' : 'Stopping…';
    toast(name === 'start' ? 'Starting the Bitcoin node…' : 'Stopping the Bitcoin node (it saves its state first; can take a minute)…', '', 150000);
    try {
      const err = await nodeSend(name);
      if (err) throw new Error(err.message);
      node.status = name === 'start' ? 'pending' : 'offline';
      toast(name === 'start' ? 'Node starting. It catches up with the network over the next few minutes.' : 'Bitcoin node stopped.', 'ok');
    } catch (e) {
      if (handleAuthError(e)) { node.busy = false; return; }
      toast(e.message === 'timeout' ? 'No reply yet. The node may still be shutting down; check again in a minute.' : e.message, 'err');
    } finally {
      node.busy = false;
      await nodeRefresh();
    }
  }

  $('nodeStartBtn').addEventListener('click', () => nodeAction('start'));
  $('nodeStopBtn').addEventListener('click', async () => {
    const text = node.solo
      ? 'You\'re solo mining through this node, so the miner can\'t mine until the node is back on.'
      : 'Mining continues through your pool. The node stops syncing and relaying blocks until you start it again.';
    if (await ask('Stop the Bitcoin node?', text, 'Stop node', { danger: true })) nodeAction('stop');
  });

  async function setMode(mode, hr) {
    const name = mode === 'custom' ? hr + ' TH/s' : modeName(mode);
    if ((mode === 'super_eco' || mode === 'custom') && !III) { toast(name + ' needs an Apollo III.', 'err'); return refresh(true); }
    if (mode === 'custom' && !(hr >= 5 && hr <= 20)) { toast('Custom target must be 5–20 TH/s.', 'err'); return; }
    busy = true; setStatus(cur.status);
    toast('Switching to ' + name + '…', '', 60000);
    try {
      await refresh(true);
      if (cur.mode === mode && (mode !== 'custom' || cur.hr === hr)) { toast('Already in ' + name + ' mode.'); return; }
      // Send nodeSoftware back unchanged: Apollo software up to 2.1.2 treats a missing
      // value as a node software change and would needlessly restart the Bitcoin node.
      const d = mode === 'custom'
        ? await gql('query ($m: MinerMode!, $n: NodeSoftware, $h: Int) { Settings { update(input: { minerMode: $m, nodeSoftware: $n, minerHashrate: $h }) { result { settings { minerMode } } error { message } } } }',
            { m: mode, n: cur.node, h: hr }, 60000)
        : await gql('query ($m: MinerMode!, $n: NodeSoftware) { Settings { update(input: { minerMode: $m, nodeSoftware: $n }) { result { settings { minerMode } } error { message } } } }',
            { m: mode, n: cur.node }, 60000);
      if (d.Settings.update.error) throw new Error(d.Settings.update.error.message);
      cur.mode = mode; if (mode === 'custom') cur.hr = hr; hrTouched = false; renderModes();
      if (cur.status === 'offline') {
        toast('Mode set to ' + name + '. The miner is stopped; it uses this mode when it starts.', 'ok');
      } else {
        $('dot').className = 'dot pending'; $('statusText').textContent = 'Restarting…';
        toast('Applying ' + name + ': the miner restarts (about a minute).', '', 180000);
        const r = await gql('query { Miner { restart { error { message } } } }', {}, 180000);
        if (r.Miner.restart.error) throw new Error('Mode saved, but the restart failed: ' + r.Miner.restart.error.message);
        toast('Switched to ' + name + '. It may show “pending” for a minute while hashing ramps up.', 'ok');
      }
    } catch (e) {
      if (handleAuthError(e)) { busy = false; return; }
      toast(e.message === 'timeout' ? 'No reply yet. The Apollo may still be working; check again in a minute.' : e.message, 'err');
    } finally {
      busy = false;
      await refresh(true);
    }
  }

  const restartNote = () => cur.status === 'offline' ? 'The miner is stopped; it uses this mode when it starts.' : 'The miner restarts to apply it (about a minute).';
  async function pickMode(m) {
    if (m === cur.mode) return;
    if (await ask('Switch to ' + modeName(m) + '?', restartNote(), 'Switch')) setMode(m);
  }
  $('hrRange').addEventListener('input', () => { hrTouched = true; $('hrVal').textContent = $('hrRange').value + ' TH/s'; });
  $('hrApply').addEventListener('click', async () => {
    const h = parseInt($('hrRange').value, 10);
    if (cur.mode === 'custom' && cur.hr === h) { toast('Already targeting ' + h + ' TH/s.'); return; }
    if (await ask('Target ' + h + ' TH/s?', restartNote(), 'Set target')) setMode('custom', h);
  });
  $('startBtn').addEventListener('click', () => action('start'));
  $('stopBtn').addEventListener('click', async () => { if (await ask('Stop the miner?', 'It stays stopped until you or the schedule start it.', 'Stop', { danger: true })) action('stop'); });
  $('nextCard').addEventListener('click', () => go('schedule'));

  // ---------------------------------------------------------------- schedule
  const clone = o => JSON.parse(JSON.stringify(o));
  const strip = s => s && JSON.stringify({ enabled: s.enabled, base: s.base, tz: s.tz || null, windows: s.windows });
  const isDirty = () => !!(draft && saved && strip(draft) !== strip(saved));

  const modeChoices = () => III ? ['super_eco', 'eco', 'balanced', 'turbo', 'custom'] : ['eco', 'balanced', 'turbo'];

  async function loadSchedule(background) {
    if (background && schedLoaded) return;
    if (!background && isDirty()) { renderSchedule(); return; }
    try {
      const j = await rest('GET', 'api/schedule');
      applyScheduleResponse(j);
    } catch (e) {
      if (handleAuthError(e)) return;
      if (!background) { $('schedLoading').textContent = e.message; toast(e.message, 'err'); }
    }
  }

  function applyScheduleResponse(j) {
    saved = j.schedule || { enabled: false, base: 'eco', windows: [] };
    if (!saved.tz && BROWSER_TZ) saved.tz = BROWSER_TZ;      // new schedule: use this device's time zone
    if (!saved.base) saved.base = 'eco';
    draft = clone(saved); upcomingList = j.upcoming || []; nowExpected = j.now || null;
    authorized = j.authorized !== false; schedLoaded = true;
    renderSchedule(); renderNext();
  }

  async function loadDevice() {
    try {
      const ctrl = new AbortController(); setTimeout(() => ctrl.abort(), 4000);
      const r = await fetch('api/device', { cache: 'no-store', signal: ctrl.signal });
      if (r.ok) { device = await r.json(); loadedAt = Date.now(); }
    } catch (e) {}
  }

  function renderNext() {
    const n = upcomingList[0];
    $('nextCard').classList.toggle('hidden', !n || !saved || !saved.enabled);
    if (n) { $('nextText').textContent = whenText(n.time) + ' · ' + n.label; }
  }

  function whenParts(iso) {
    const [d, t] = iso.split('T'); const [y, mo, da] = d.split('-').map(Number); const [h, mi] = t.split(':').map(Number);
    const dt = new Date(y, mo - 1, da, h, mi);
    let today = null;
    if (device && device.time) { const p = device.time.slice(0, 10).split('-').map(Number); today = new Date(p[0], p[1] - 1, p[2]); }
    const diff = today ? Math.round((new Date(y, mo - 1, da) - today) / 864e5) : null;
    const day = diff === 0 ? 'Today' : diff === 1 ? 'Tomorrow' : dt.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' });
    return { day, time: dt.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }) };
  }
  const whenText = iso => { const p = whenParts(iso); return p.day + ' ' + p.time; };

  function windowProblem(w) {
    if (!w.days.length) return 'Pick at least one day.';
    if (!w.on) return 'Pick a start time.';
    if (w.type === 'mode' && !w.off) return 'Pick an end time.';
    if (w.off && w.off === w.on) return 'Start and end can\'t be the same time.';
    if (w.type === 'mode' && (!w.mode || w.mode === draft.base)) return 'Pick a mode different from your normal mode (' + modeName(draft.base) + ').';
    return null;
  }

  function windowSummary(w) {
    const days = w.days.length ? fmtDays(w.days) : '';
    const overnight = w.off && w.on && minutes(w.off) < minutes(w.on);
    const span = fmtTime(w.on) + (w.off ? '–' + fmtTime(w.off) + (overnight ? ' (next day)' : '') : '');
    const frag = document.createDocumentFragment();
    frag.append(el('b', {}, days), ', ' + span + ': ');
    if (w.type === 'mode') {
      frag.append(el('b', {}, modeName(w.mode)), ', then back to ' + modeName(draft.base) + '.');
    } else {
      frag.append('mining' + (w.mode ? ' in ' : ''), w.mode ? el('b', {}, modeName(w.mode)) : '',
        w.off ? ', stopped the rest of the time.' : ' and keeps running (no stop time).');
    }
    return frag;
  }

  function modeSelect(value, allowKeep, onChange) {
    const wrap = el('div', { class: 'modefield' });
    const base = value && value.startsWith('custom:') ? 'custom' : (value || '');
    const sel = el('select', { 'aria-label': 'Mode' });
    if (allowKeep) sel.append(el('option', { value: '' }, 'Keep current mode'));
    for (const m of modeChoices()) sel.append(el('option', { value: m }, m === 'custom' ? 'Custom TH/s' : modeName(m)));
    sel.value = base;
    const hr = el('select', { class: 'hr', 'aria-label': 'Target TH/s' });
    for (let h = 5; h <= 20; h++) hr.append(el('option', { value: String(h) }, h + ' TH/s'));
    hr.value = value && value.startsWith('custom:') ? value.slice(7) : '14';
    const label = el('label', {}, allowKeep ? 'Mode while mining' : 'Switch to');
    const left = el('div', {}, label, sel);
    wrap.append(left);
    const hrBox = el('div', { class: base === 'custom' ? '' : 'hidden' }, el('label', {}, 'Target'), hr);
    wrap.append(hrBox);
    const emit = () => { hrBox.classList.toggle('hidden', sel.value !== 'custom'); onChange(sel.value === 'custom' ? 'custom:' + hr.value : (sel.value || null)); };
    sel.addEventListener('change', emit); hr.addEventListener('change', emit);
    return wrap;
  }

  function renderSchedule() {
    if (!draft) return;
    $('schedLoading').classList.add('hidden'); $('schedBody').classList.remove('hidden');
    $('enabledSwitch').setAttribute('aria-checked', String(!!draft.enabled));
    $('enabledText').textContent = draft.enabled
      ? 'On. The Apollo follows this schedule by itself; your phone or computer can be off.'
      : 'Off. Nothing changes automatically.';
    const bs = $('baseSelect'); bs.textContent = '';
    for (const m of modeChoices().filter(m => m !== 'custom')) bs.append(el('option', { value: m }, modeName(m)));
    if (draft.base && draft.base.startsWith('custom:')) bs.append(el('option', { value: draft.base }, modeName(draft.base)));
    bs.value = draft.base;
    $('baseRow').classList.toggle('hidden', !draft.windows.some(w => w.type === 'mode'));
    $('authBanner').classList.toggle('hidden', authorized || !saved.enabled);

    const box = $('windows'); box.textContent = '';
    if (!draft.windows.length) {
      box.append(el('div', { class: 'card empty' }, 'No time windows yet. Add one to switch modes or run the miner at set times.'));
    }
    draft.windows.forEach((w, i) => box.append(windowCard(w, i)));
    $('addBtn').disabled = draft.windows.length >= 20;
    renderUpcoming(); renderSaveBar();
  }

  function windowCard(w, i) {
    const card = el('div', { class: 'win' });
    const changed = () => { renderSaveBar(); summary.textContent = ''; summary.append(windowSummary(w));
      const p = windowProblem(w); problem.textContent = p || ''; problem.classList.toggle('hidden', !p);
      $('baseRow').classList.toggle('hidden', !draft.windows.some(x => x.type === 'mode')); };
    const seg = el('div', { class: 'seg', role: 'group', 'aria-label': 'Window type' });
    for (const [t, name] of [['mode', 'Change mode'], ['run', 'Mine only']]) {
      seg.append(el('button', { type: 'button', 'aria-pressed': String(w.type === t), onclick: () => {
        if (w.type === t) return;
        w.type = t;
        if (t === 'mode') { if (!w.off) w.off = '16:30'; if (!w.mode || w.mode === draft.base) w.mode = modeChoices().find(m => m !== draft.base && m !== 'custom'); }
        renderSchedule();
      } }, name));
    }
    card.append(el('div', { class: 'win-head' }, seg,
      el('button', { class: 'icon-btn', type: 'button', 'aria-label': 'Remove this window', title: 'Remove', html: ICON.trash,
        onclick: () => { draft.windows.splice(i, 1); renderSchedule(); } })));

    const days = el('div', { class: 'days', role: 'group', 'aria-label': 'Days' });
    const dayBtns = [];
    DAYS.forEach((d, k) => {
      const b = el('button', { class: 'day', type: 'button', 'aria-pressed': String(w.days.includes(k + 1)), 'aria-label': d, title: d,
        onclick: () => {
          const n = k + 1; w.days = w.days.includes(n) ? w.days.filter(x => x !== n) : [...w.days, n].sort((a, b) => a - b);
          b.setAttribute('aria-pressed', String(w.days.includes(n))); changed();
        } }, d[0]);
      dayBtns.push(b); days.append(b);
    });
    const setDays = list => { w.days = list; dayBtns.forEach((b, k) => b.setAttribute('aria-pressed', String(list.includes(k + 1)))); changed(); };
    card.append(days, el('div', { class: 'presets' },
      el('button', { type: 'button', onclick: () => setDays([1, 2, 3, 4, 5]) }, 'Weekdays'),
      el('button', { type: 'button', onclick: () => setDays([6, 7]) }, 'Weekends'),
      el('button', { type: 'button', onclick: () => setDays([1, 2, 3, 4, 5, 6, 7]) }, 'Every day')));

    const on = el('input', { type: 'time', value: w.on || '', required: true, 'aria-label': 'From' });
    const off = el('input', { type: 'time', value: w.off || '', 'aria-label': 'Until', disabled: w.type === 'run' && !w.off });
    const cb = el('input', { type: 'checkbox' }); cb.checked = !w.off;
    on.addEventListener('input', () => { w.on = on.value || null; changed(); });
    off.addEventListener('input', () => {
      w.off = off.value || null;
      if (!w.off && w.type === 'run') { cb.checked = true; off.disabled = true; }
      changed();
    });
    card.append(el('div', { class: 'row2' }, el('div', {}, el('label', {}, 'From'), on), el('div', {}, el('label', {}, 'Until'), off)));
    if (w.type === 'run') {
      cb.addEventListener('change', () => {
        if (cb.checked) { w.off = null; off.value = ''; off.disabled = true; }
        else { off.disabled = false; w.off = off.value || '17:00'; off.value = w.off; }
        changed();
      });
      card.append(el('label', { class: 'check' }, cb, 'No stop time (keep mining)'));
    }
    card.append(modeSelect(w.mode || null, w.type === 'run', v => { if (v) w.mode = v; else delete w.mode; changed(); }));
    const summary = el('div', { class: 'summary' });
    const problem = el('div', { class: 'summary problem hidden', role: 'alert' });
    card.append(summary, problem);
    changed();
    return card;
  }

  function renderUpcoming() {
    const ul = $('upcoming'); ul.textContent = '';
    const dirty = isDirty();
    if (!saved.enabled || !upcomingList.length) {
      ul.append(el('li', { class: 'sub' }, saved.enabled ? 'Nothing scheduled.' : 'The schedule is off.'));
    } else {
      for (const u of upcomingList) {
        const p = whenParts(u.time);
        const kind = u.action === 'stop' ? 'stop' : u.action.indexOf('start') === 0 ? 'start' : 'mode';
        const icon = kind === 'mode' ? modeIcon(u.action) : ICON[kind];
        ul.append(el('li', {}, el('span', { class: 'badge b-' + kind, html: icon, style: kind === 'mode' ? '--mc:' + modeColor(u.action) : null }),
          el('span', { class: 'when' }, el('b', {}, p.time), el('span', {}, p.day)), el('span', {}, u.label)));
      }
    }
    if (dirty) ul.append(el('li', { class: 'sub' }, 'Save to update this list.'));
    const tz = draft.tz;
    const tzBox = $('tzText'); tzBox.textContent = '';
    tzBox.append('Times are in ', el('b', {}, tz || (device && device.tz) || 'the Apollo\'s time zone'), '.');
    if (BROWSER_TZ && tz && tz !== BROWSER_TZ) {
      tzBox.append(' ', el('button', { class: 'linkbtn', type: 'button', onclick: () => { draft.tz = BROWSER_TZ; renderSchedule(); } }, 'Use ' + BROWSER_TZ));
    }
  }

  function renderSaveBar() {
    const dirty = isDirty();
    $('saveBar').classList.toggle('hidden', !dirty);
    const problems = draft.windows.map(windowProblem).filter(Boolean);
    $('saveBtn').disabled = problems.length > 0;
    $('saveText').textContent = problems.length ? 'Fix the highlighted window' + (problems.length > 1 ? 's' : '') : 'Unsaved changes';
  }

  $('enabledSwitch').addEventListener('click', () => { draft.enabled = !draft.enabled; renderSchedule(); });
  $('baseSelect').addEventListener('change', () => { draft.base = $('baseSelect').value; renderSchedule(); });
  $('addBtn').addEventListener('click', () => {
    const first = draft.windows.length === 0;
    const fast = modeChoices().filter(m => m !== draft.base && m !== 'custom').pop();
    draft.windows.push({ type: 'mode', days: [1, 2, 3, 4, 5], on: '09:00', off: '17:00', mode: fast });
    if (first) draft.enabled = true;
    renderSchedule();
    const cards = document.querySelectorAll('.win'); const last = cards[cards.length - 1];
    if (last) last.scrollIntoView({ behavior: 'smooth', block: 'center' });
  });
  $('discardBtn').addEventListener('click', () => { draft = clone(saved); renderSchedule(); });
  $('saveBtn').addEventListener('click', saveSchedule);

  async function saveSchedule() {
    const body = { enabled: draft.enabled, base: draft.base, tz: draft.tz || BROWSER_TZ || null,
      windows: draft.windows.map(w => { const o = { type: w.type, days: w.days, on: w.on, off: w.off || null }; if (w.mode) o.mode = w.mode; return o; }) };
    $('saveBtn').disabled = true; $('saveText').textContent = 'Saving…';
    try {
      const j = await rest('PUT', 'api/schedule', body);
      await loadDevice();             // the time zone may have changed
      applyScheduleResponse(j);
      toast(j.schedule.enabled && j.schedule.windows.length ? 'Schedule saved. The Apollo takes it from here.' : 'Saved. The schedule is off.', 'ok');
      await offerApplyNow();
    } catch (e) {
      if (handleAuthError(e)) return;
      toast(e.message, 'err'); renderSaveBar();
    }
  }

  // After saving: if the schedule says something different should be true right now, offer to do it now
  async function offerApplyNow() {
    if (!nowExpected) return;
    await refresh(true);
    const want = nowExpected;
    const curTok = cur.mode === 'custom' ? 'custom:' + cur.hr : cur.mode;
    if (want.running === true && cur.status === 'offline') {
      const label = want.mode && want.mode !== curTok ? 'Start mining in ' + modeName(want.mode) : 'Start mining';
      if (await ask('Start now?', 'Your schedule says the miner should be running right now.', label, { no: 'Wait' })) {
        if (want.mode && want.mode !== curTok) await applyToken(want.mode);
        go('control'); action('start');
      }
      return;
    }
    if (want.running === false && cur.status !== 'offline') {
      if (await ask('Stop now?', 'Your schedule says the miner should be stopped right now.', 'Stop mining', { no: 'Wait', danger: true })) { go('control'); action('stop'); }
      return;
    }
    if (want.mode && curTok && want.mode !== curTok) {
      if (await ask('Switch to ' + modeName(want.mode) + ' now?', 'Your schedule says ' + modeName(want.mode) + ' right now. ' + restartNote(), 'Switch now', { no: 'Wait' })) {
        go('control'); applyToken(want.mode);
      }
    }
  }
  const applyToken = t => t.startsWith('custom:') ? setMode('custom', parseInt(t.slice(7), 10)) : setMode(t);

  // ---------------------------------------------------------------- activity
  function actLabel(a) {
    if (a === 'start') return 'Start mining';
    if (a === 'stop') return 'Stop mining';
    if (a === 'restart') return 'Restart';
    if (a === 'node_start') return 'Start Bitcoin node';
    if (a === 'node_stop') return 'Stop Bitcoin node';
    if (a === 'schedule') return 'Schedule';
    if (a === 'alert') return 'Alert sent';
    if (a === 'automation') return 'Shortcut key';
    if (a === 'update') return 'Apollo software';
    if (a === 'light') return 'Front status light';
    if (a.indexOf('start@') === 0) return 'Start mining in ' + modeName(a.slice(6));
    return modeName(a) + ' mode';
  }
  async function loadActivity() {
    try {
      const items = await rest('GET', 'api/activity');
      const ul = $('actList'); ul.textContent = '';
      $('actEmpty').classList.toggle('hidden', items.length > 0);
      for (const it of items) {
        const a = String(it.action || '');
        const kind = !it.ok ? 'fail' : a === 'alert' ? 'alert' : a === 'update' ? 'update' : a === 'light' ? 'light' : a === 'schedule' || a === 'automation' ? 'saved' : a.indexOf('node_') === 0 ? 'node' : a === 'stop' ? 'stop' : a.indexOf('start') === 0 ? 'start' : a === 'restart' ? 'restart' : 'mode';
        const cls = { fail: 'b-stop', saved: 'b-info', stop: 'b-stop', start: 'b-start', restart: 'b-info', mode: 'b-mode', node: 'b-info', alert: 'b-mode', update: 'b-info', light: 'b-info' }[kind];
        const icon = kind === 'mode' ? modeIcon(a) : ICON[kind];
        const d = new Date(it.time);
        const valid = !isNaN(d);
        ul.append(el('li', { class: it.ok ? '' : 'fail' },
          el('span', { class: 'badge ' + cls, html: icon }),
          el('span', { class: 'txt' }, el('b', {}, actLabel(a) + (it.ok ? '' : ' failed')), el('div', {}, it.message || '')),
          el('span', { class: 'meta' },
            valid ? d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }) : '', el('br'),
            valid ? d.toLocaleDateString([], { month: 'short', day: 'numeric' }) : '', el('br'),
            el('span', { class: 'src' }, { app: 'You', alert: 'Alert', shortcut: 'Shortcut', houston: 'Houston' }[it.source] || 'Schedule'))));
      }
    } catch (e) {
      if (handleAuthError(e)) return;
      toast(e.message, 'err');
    }
  }
  $('actRefresh').addEventListener('click', loadActivity);

  // ---------------------------------------------------------------- Apollo software update
  // FutureBit's own updater does the work (the same one the Apollo dashboard runs); Houston starts
  // it and follows along. Houston runs on the Apollo too, so it goes away while the Apollo reboots.
  let upd = null, updTimer = null, updWasRunning = false, updLost = 0;
  async function loadUpdate(check) {
    clearTimeout(updTimer);
    try {
      const u = await rest('GET', 'api/apollo-update' + (check ? '?check=1' : ''));
      if (updWasRunning && !u.running) {
        if (u.progress != null && u.progress < 0) toast('The Apollo software update failed. See Activity for details; you can try again.', 'err', 12000);
        else toast('Apollo software ' + (u.installed ? 'v' + u.installed + ' ' : '') + 'is installed. Welcome back!', 'ok', 9000);
        if (view === 'control') refresh(true);
      }
      upd = u; updLost = 0; updWasRunning = !!u.running;
      if (check) toast(u.error ? u.error : u.available ? 'New version v' + u.latest + ' is available!' : 'Your Apollo software is up to date.', u.error ? 'err' : u.available ? '' : 'ok');
    } catch (e) {
      if (handleAuthError(e)) return;
      if (updWasRunning) updLost++;            // expected: the Apollo is rebuilding or restarting
      else if (check) toast(e.message, 'err');
    }
    renderUpdate();
    if (updWasRunning) updTimer = setTimeout(() => loadUpdate(false), 5000);
  }

  function renderUpdate() {
    const u = upd, sub = $('updSub'), btn = $('updBtn');
    const running = updWasRunning;
    let text = 'Checking…';
    if (running && updLost) text = 'Restarting… Houston reconnects when the Apollo is back.';
    else if (running) text = 'Updating' + (u && u.run && u.run.to ? ' to v' + u.run.to : '') + '… ' + (u && u.progress > 0 ? u.progress + '%' : 'starting');
    else if (u) {
      const have = u.installed ? 'v' + u.installed : 'Installed version unknown';
      text = !u.installed && u.latest ? 'Latest version: v' + u.latest + ' (Houston can\'t read which one is installed)'
        : u.available ? have + ' · New version v' + u.latest + ' is available!'
        : u.latest && u.installed ? have + ' · Up to date'
        : u.error ? have + ' · Couldn\'t check for updates' : have;
      if (u.progress != null && u.progress < 0) text += ' · Last update failed';
    }
    sub.textContent = text;
    const canRun = u && (u.available || (u.latest && !u.installed));
    btn.classList.toggle('hidden', !canRun || running);
    btn.textContent = u && u.available ? 'Update to v' + u.latest : 'Update';
    $('updCheck').classList.toggle('hidden', running);
    $('updProg').classList.toggle('hidden', !running);
    $('updBar').style.width = running ? (updLost ? 100 : Math.max(5, (u && u.progress) || 5)) + '%' : '0';
    $('updNote').textContent = updLost
      ? 'The Apollo is restarting to finish the update. This page reconnects by itself; keep the Apollo powered on.'
      : 'Mining and the node are paused while FutureBit\'s updater runs (about 10–20 minutes), then the Apollo restarts by itself. Keep it powered on.';
    const card = $('updCard');
    card.classList.toggle('hidden', !(u && (u.available || running)));
    $('updCardText').textContent = running ? (updLost ? 'Apollo is restarting to finish the update…' : 'Updating Apollo software… ' + (u && u.progress > 0 ? u.progress + '%' : ''))
      : u && u.available ? 'New version v' + u.latest + ' is available!' : '';
  }

  $('updCheck').addEventListener('click', () => { $('updSub').textContent = 'Checking…'; loadUpdate(true); });
  $('updCard').addEventListener('click', async () => { await go('settings'); $('apolloCard').scrollIntoView({ block: 'start', behavior: 'smooth' }); });
  $('updBtn').addEventListener('click', async () => {
    if (!upd || !(upd.available || (upd.latest && !upd.installed))) return;
    const ok = await ask('Update Apollo software to v' + upd.latest + '?',
      'This runs FutureBit\'s official update, like the Update button on the Apollo dashboard. It takes about 10–20 minutes: mining and the Bitcoin node pause, then the Apollo restarts by itself. Keep it powered on until it\'s done. Houston will tell you when it\'s back.',
      'Update now');
    if (!ok) return;
    $('updBtn').disabled = true;
    try {
      const j = await rest('POST', 'api/apollo-update');
      upd = j.update; updWasRunning = true; updLost = 0;
      toast('Update started. You can close Houston; it keeps track.', 'ok', 8000);
    } catch (e) {
      if (!handleAuthError(e)) toast(e.message, 'err');
    } finally { $('updBtn').disabled = false; }
    renderUpdate();
    clearTimeout(updTimer); updTimer = setTimeout(() => loadUpdate(false), 4000);
  });

  // ---------------------------------------------------------------- front status light
  // Apollo setting powerLedOff; the miner reads it when it starts, so a running miner restarts.
  let ledOff = null, ledBusy = false;
  async function loadLed() {
    try {
      const d = await gql('query { Settings { read { result { settings { powerLedOff nodeSoftware } } error { message } } } }');
      const st = d.Settings.read.result && d.Settings.read.result.settings;
      if (st) { ledOff = !!st.powerLedOff; cur.node = st.nodeSoftware; }
    } catch (e) { if (handleAuthError(e)) return; }
    renderLed();
  }
  function renderLed() {
    const sw = $('ledSwitch');
    sw.setAttribute('aria-checked', String(ledOff === false));
    sw.disabled = ledOff === null || ledBusy;
  }
  $('ledSwitch').addEventListener('click', async () => {
    if (ledOff === null || ledBusy) return;
    const off = !ledOff;
    await refresh(true);
    const running = cur.status !== 'offline';
    const ok = await ask((off ? 'Turn off' : 'Turn on') + ' the front status light?',
      running ? 'Your miner will be restarted to apply (about a minute).' : 'The miner is stopped; the light follows this setting when it starts.',
      off ? 'Turn off' : 'Turn on');
    if (!ok) return;
    ledBusy = true; busy = true; renderLed(); setStatus(cur.status);
    toast(off ? 'Turning the front light off…' : 'Turning the front light on…', '', 180000);
    try {
      // nodeSoftware goes back unchanged (see setMode)
      const d = await gql('query ($led: Boolean, $n: NodeSoftware) { Settings { update(input: { powerLedOff: $led, nodeSoftware: $n }) { result { settings { powerLedOff } } error { message } } } }',
        { led: off, n: cur.node }, 60000);
      if (d.Settings.update.error) throw new Error(d.Settings.update.error.message);
      ledOff = off; renderLed();
      if (running) {
        $('dot').className = 'dot pending'; $('statusText').textContent = 'Restarting…';
        const r = await gql('query { Miner { restart { error { message } } } }', {}, 180000);
        if (r.Miner.restart.error) throw new Error('Saved, but the restart failed: ' + r.Miner.restart.error.message);
        toast('Front light ' + (off ? 'off' : 'on') + '. The miner restarted; hashing ramps up over the next minute.', 'ok');
      } else toast('Front light set to ' + (off ? 'off' : 'on') + '. It applies when the miner starts.', 'ok');
    } catch (e) {
      if (handleAuthError(e)) { ledBusy = busy = false; return; }
      toast(e.message === 'timeout' ? 'No reply yet. The Apollo may still be working; check again in a minute.' : e.message, 'err');
    } finally {
      ledBusy = false; busy = false; renderLed();
      refresh(true);
    }
  });

  // ---------------------------------------------------------------- system logs
  let actPane = 'activity', logType = 'MINER', logTimer = null, logRaw = '', logBusy = false;
  const ANSI = /\x1b\[[0-9;?]*[ -/]*[@-~]/g;
  function showPane() {
    setSeg($('actSeg'), 'pane', actPane);
    $('actPane').classList.toggle('hidden', actPane !== 'activity');
    $('logPane').classList.toggle('hidden', actPane !== 'logs');
    clearInterval(logTimer);
    if (actPane === 'activity') loadActivity();
    else {
      $('logSolo').classList.toggle('hidden', !node.solo);
      if (logType === 'CKPOOL' && !node.solo) logType = 'MINER';
      if (!node.solo) gql('query { Settings { read { result { settings { nodeEnableSoloMining } } } } }').then(d => {     // opened before Home loaded
        const st = d.Settings.read.result && d.Settings.read.result.settings;
        node.solo = !!(st && st.nodeEnableSoloMining); $('logSolo').classList.toggle('hidden', !node.solo);
      }).catch(() => {});
      setSeg($('logSeg'), 'log', logType);
      loadLog();
      if ($('logLive').getAttribute('aria-checked') === 'true') logTimer = setInterval(() => { if (!document.hidden) loadLog(true); }, 5000);
    }
  }
  async function loadLog(live) {
    if (logBusy) return;
    logBusy = true;
    const want = logType, lines = parseInt($('logLines').value, 10) || 300;
    if (!live) { $('logView').textContent = 'Loading…'; $('logStamp').textContent = ''; }
    try {
      let content, stamp;
      if (want === 'HOUSTON') {
        const j = await rest('GET', 'api/houston-log');
        content = j.content.split('\n').slice(-lines).join('\n'); stamp = j.timestamp;
      } else {
        const d = await gql('query ($t: LogType!, $n: Int) { Logs { read(input: { logType: $t, lines: $n }) { result { content timestamp } error { message } } } }',
          { t: want, n: lines }, 30000);
        const r = d.Logs.read;
        if (r.error) throw new Error(r.error.message);
        content = (r.result && r.result.content) || ''; stamp = r.result && r.result.timestamp;
      }
      if (want !== logType) return;
      logRaw = String(content).replace(ANSI, '').replace(/\r/g, '');
      const d = stamp ? new Date(stamp) : new Date();
      $('logStamp').textContent = 'read ' + (isNaN(d) ? '' : d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' }));
      renderLog();
    } catch (e) {
      if (handleAuthError(e)) return;
      if (want !== logType) return;
      logRaw = '';
      $('logView').textContent = /Cannot query field|Unknown type/.test(e.message) ? 'This Apollo software doesn\'t offer logs to apps. Update it to see them here.' : 'Couldn\'t read this log: ' + e.message;
    } finally { logBusy = false; }
  }
  function renderLog() {
    const box = $('logView');
    const atBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 40;
    const q = $('logFilter').value.trim().toLowerCase();
    let rows = logRaw.split('\n');
    while (rows.length && !rows[rows.length - 1].trim()) rows.pop();
    const total = rows.length;
    if (q) rows = rows.filter(r => r.toLowerCase().indexOf(q) >= 0);
    box.textContent = '';
    const frag = document.createDocumentFragment();
    for (const r of rows) {
      const span = document.createElement('span');
      span.textContent = r || ' ';                         // log text is shown as text, never as markup
      if (/\b(error|err|fail(ed|ure)?|fatal|panic|critical)\b/i.test(r)) span.className = 'le';
      else if (/\bwarn(ing)?\b/i.test(r)) span.className = 'lw';
      frag.append(span);
    }
    if (!rows.length) frag.append(el('span', { class: 'lm' }, q ? 'No lines contain “' + $('logFilter').value.trim() + '”.' : 'This log is empty.'));
    box.append(frag);
    $('logNote').textContent = (q ? rows.length + ' of ' + total + ' lines match. ' : total + ' lines. ') + 'Newest at the bottom. Read from the Apollo through its own API; nothing leaves your network.';
    if (atBottom || !box.dataset.seen) { box.scrollTop = box.scrollHeight; box.dataset.seen = '1'; }
  }
  document.querySelectorAll('#actSeg [data-pane]').forEach(b => b.addEventListener('click', () => { actPane = b.dataset.pane; showPane(); }));
  document.querySelectorAll('#logSeg [data-log]').forEach(b => b.addEventListener('click', () => {
    logType = b.dataset.log; setSeg($('logSeg'), 'log', logType); delete $('logView').dataset.seen; loadLog();
  }));
  $('logLines').addEventListener('change', () => { delete $('logView').dataset.seen; loadLog(); });
  $('logFilter').addEventListener('input', renderLog);
  $('logRefresh').addEventListener('click', () => loadLog());
  $('logLive').addEventListener('click', () => {
    const on = $('logLive').getAttribute('aria-checked') !== 'true';
    $('logLive').setAttribute('aria-checked', String(on));
    clearInterval(logTimer);
    if (on) { loadLog(true); logTimer = setInterval(() => { if (!document.hidden) loadLog(true); }, 5000); }
  });
  const logName = () => ({ MINER: 'miner', NODE: 'node', CKPOOL: 'solo-pool', SYSLOG: 'system', HOUSTON: 'houston' })[logType] || 'log';
  $('logCopy').addEventListener('click', async () => {
    const text = Array.from($('logView').children, c => c.textContent).join('\n');
    try { await navigator.clipboard.writeText(text); toast('Log copied.', 'ok'); }
    catch (e) { const r = document.createRange(); r.selectNodeContents($('logView')); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); toast('Lines selected: copy them with your device\'s copy command.'); }
  });
  $('logSave').addEventListener('click', () => {
    const d = new Date();
    const name = 'apollo-' + logName() + '-' + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + '-' + pad(d.getHours()) + pad(d.getMinutes()) + '.txt';
    const url = URL.createObjectURL(new Blob([logRaw + '\n'], { type: 'text/plain' }));
    const a = el('a', { href: url, download: name }); document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 5000);
  });

  // ---------------------------------------------------------------- settings
  async function loadSettings() {
    try {
      const j = await rest('GET', 'api/settings');
      settings = j.settings; units = settings.units || 'F';
      // Houston keeps a sign-in for the schedule, statsData, alerts and shortcuts
      if (!j.authorized) { try { await rest('PUT', 'api/auth'); } catch (e) {} }
    } catch (e) {
      if (e.code === 'UNAUTHENTICATED') throw e;
      settings = settings || { units: 'F', currency: '$', rate: null, alerts: {}, apollos: [], automation: {} };
    }
  }

  async function saveSettings(part, okMsg) {
    try {
      const j = await rest('PUT', 'api/settings', part);
      settings = j.settings; units = settings.units;
      toast(okMsg || 'Saved.', 'ok');
      renderSettings();
      return true;
    } catch (e) {
      if (handleAuthError(e)) return false;
      toast(e.message, 'err'); return false;
    }
  }

  function setSeg(container, attr, value) {
    container.querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset[attr] === value)));
  }

  function renderSettings() {
    if (!settings) return;
    const view = $('view-settings');
    setSeg(view.querySelector('[aria-label="Temperature unit"]'), 'unit', units);
    const pr = settings.price || { enabled: true, fiat: 'USD' };
    const fs = $('fiatSelect'); if (!fs.options.length) FIATS.forEach(f => fs.append(el('option', { value: f }, f)));
    fs.value = pr.fiat || 'USD'; fs.disabled = pr.enabled === false;
    $('priceSwitch').setAttribute('aria-checked', String(pr.enabled !== false));
    $('marketSwitch').setAttribute('aria-checked', String(!settings.market || settings.market.enabled !== false));
    $('currency').value = settings.currency || '$';
    $('rate').value = settings.rate == null ? '' : settings.rate;
    const a = settings.alerts || {};
    $('alertsSwitch').setAttribute('aria-checked', String(!!a.enabled));
    $('topic').value = a.topic || '';
    document.querySelectorAll('#alertChecks input').forEach(c => { c.checked = a[c.dataset.a] !== false; });
    $('hotLimit').value = a.hotC != null ? Math.round(toUnit(a.hotC)) : '';
    $('hotUnit').textContent = '°' + units;
    $('ntfyServer').value = a.server && a.server !== 'https://ntfy.sh' ? a.server : '';
    renderPeers(settings.apollos || []);
    renderAutomation();
    renderPush();
    $('abVer').textContent = device ? device.version : '–';
    $('abModel').textContent = III ? 'Apollo III' : device ? 'Apollo II' : '–';
    $('abTz').textContent = device && device.tz ? device.tz : '–';
    $('abAuth').textContent = 'On';
    loadUpdate(false); loadLed();
  }

  document.querySelectorAll('#view-settings [data-unit]').forEach(b => b.addEventListener('click', async () => {
    if (b.dataset.unit === units) return;
    if (await saveSettings({ units: b.dataset.unit }, 'Temperatures now in °' + b.dataset.unit + '.')) refresh(true);
  }));
  $('priceSwitch').addEventListener('click', async () => {
    const on = $('priceSwitch').getAttribute('aria-checked') !== 'true';
    if (await saveSettings({ price: { enabled: on } }, on ? 'Bitcoin price on.' : 'Bitcoin price off.')) setTimeout(loadPrice, on ? 2500 : 0);
  });
  $('marketSwitch').addEventListener('click', async () => {
    const on = $('marketSwitch').getAttribute('aria-checked') !== 'true';
    if (await saveSettings({ market: { enabled: on } }, on ? 'Network, market and news on. They appear on Stats in a moment.' : 'Network, market and news off.')) setTimeout(loadMarket, on ? 4000 : 0);
  });
  $('fiatSelect').addEventListener('change', async () => {
    if (await saveSettings({ price: { fiat: $('fiatSelect').value } }, 'Prices now in ' + $('fiatSelect').value + '.')) setTimeout(loadPrice, 2500);
  });
  $('saveRate').addEventListener('click', () => saveSettings({ rate: $('rate').value.trim(), currency: $('currency').value.trim() || '$' }, 'Electricity price saved.'));
  $('alertsSwitch').addEventListener('click', () => { const on = $('alertsSwitch').getAttribute('aria-checked') !== 'true'; $('alertsSwitch').setAttribute('aria-checked', String(on)); });
  $('newTopic').addEventListener('click', () => {
    const b = new Uint8Array(9); crypto.getRandomValues(b);
    $('topic').value = 'houston-' + Array.from(b, x => 'abcdefghijkmnpqrstuvwxyz23456789'[x % 32]).join('');
  });
  function alertsPayload() {
    const a = { enabled: $('alertsSwitch').getAttribute('aria-checked') === 'true', topic: $('topic').value.trim(),
                server: $('ntfyServer').value.trim() || 'https://ntfy.sh' };
    document.querySelectorAll('#alertChecks input').forEach(c => { a[c.dataset.a] = c.checked; });
    const lim = parseFloat($('hotLimit').value);
    if (!isNaN(lim)) a.hotC = Math.round(fromUnit(lim) * 10) / 10;
    return a;
  }
  $('saveAlerts').addEventListener('click', () => saveSettings({ alerts: alertsPayload() }, 'Alert settings saved.'));
  $('testAlert').addEventListener('click', async () => {
    if (!(await saveSettings({ alerts: Object.assign(alertsPayload(), { enabled: alertsPayload().enabled }) }, 'Saved. Sending a test…'))) return;
    try { const j = await rest('POST', 'api/alerts/test', {}); toast('Test sent' + (j.warnings && j.warnings.length ? ' (' + j.warnings.join('; ') + ')' : '') + '. Check your phone.', j.warnings && j.warnings.length ? '' : 'ok'); }
    catch (e) { if (!handleAuthError(e)) toast(e.message, 'err'); }
  });

  // ---------------------------------------------------------------- notifications on this device (Web Push)
  let pushInfo = null, myPushId = null;
  const isIOS = /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const standalone = () => (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches) || navigator.standalone === true;
  const pushCapable = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  const deviceName = () => {
    const u = navigator.userAgent;
    const dev = /iPhone/.test(u) ? 'iPhone' : isIOS ? 'iPad' : /Android/.test(u) ? 'Android' : /Mac/.test(u) ? 'Mac' : /Windows/.test(u) ? 'Windows PC' : /Linux/.test(u) ? 'Linux PC' : 'Device';
    const br = /Edg\//.test(u) ? 'Edge' : /Firefox\//.test(u) ? 'Firefox' : /Chrome\//.test(u) ? (navigator.brave ? 'Brave' : 'Chrome') : /Safari\//.test(u) ? 'Safari' : '';
    return isIOS && standalone() ? dev : dev + (br ? ' · ' + br : '');
  };
  const b64u = buf => btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const unb64u = str => Uint8Array.from(atob((str + '='.repeat((4 - str.length % 4) % 4)).replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
  async function sha16(str) {
    const h = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(str));
    return Array.from(new Uint8Array(h), b => b.toString(16).padStart(2, '0')).join('').slice(0, 16);
  }
  async function currentSub() {
    if (!pushCapable() || !window.isSecureContext) return null;
    try { const r = await navigator.serviceWorker.getRegistration(); return r ? await r.pushManager.getSubscription() : null; } catch (e) { return null; }
  }

  async function renderPush() {
    try { pushInfo = await rest('GET', 'api/push'); } catch (e) { if (handleAuthError(e)) return; pushInfo = null; }
    const sub = await currentSub();
    myPushId = sub ? await sha16(sub.endpoint) : null;
    const devs = (pushInfo && pushInfo.devices) || [];
    const mine = !!myPushId && devs.some(d => d.id === myPushId);
    let why = '';
    if (!pushInfo) why = 'Update Houston on the Apollo to use this.';
    else if (!pushInfo.available) why = 'The Apollo needs one more package for this: run the Houston installer again.';
    else if (!window.isSecureContext) why = 'Needs Houston\'s secure address (https://…): phones only allow notifications on secure pages. See “Notifications without ntfy” in docs/houston.md.';
    else if (isIOS && !standalone()) why = 'On iPhone and iPad: add Houston to your Home Screen (Share › Add to Home Screen), open it from there, then turn this on. Needs iOS 16.4 or later.';
    else if (!pushCapable()) why = 'This browser can\'t show notifications from web apps.';
    else if (Notification.permission === 'denied') why = 'Notifications are blocked for Houston in this browser\'s settings. Allow them there, then try again.';
    $('pushHint').textContent = why || (mine ? 'On: this device gets alerts as notifications.' : 'Regular notifications from the Houston app. No extra app or account.');
    $('pushOn').classList.toggle('hidden', mine); $('pushOn').disabled = !!why;
    $('pushOff').classList.toggle('hidden', !mine); $('pushTest').classList.toggle('hidden', !mine);
    const st = $('pushState');
    st.textContent = mine ? 'On here' : devs.length ? devs.length + ' device' + (devs.length === 1 ? '' : 's') : 'Off';
    st.classList.toggle('on', devs.length > 0);
    const topicOn = !!(settings && settings.alerts && settings.alerts.topic);
    $('ntfyState').textContent = topicOn ? 'On' : 'Off'; $('ntfyState').classList.toggle('on', topicOn);
    const ul = $('pushDevices'); ul.textContent = '';
    for (const d of devs) {
      ul.append(el('li', {}, el('span', {}, d.name + (d.id === myPushId ? ' (this one)' : ''), el('small', {}, 'added ' + new Date(d.added).toLocaleDateString())),
        el('button', { class: 'linkbtn', type: 'button', onclick: () => removeDevice(d) }, 'Remove')));
    }
  }

  async function removeDevice(d) {
    if (!(await ask('Stop notifications on ' + d.name + '?', 'That device stops getting alerts from Houston.', 'Remove', { danger: true }))) return;
    try {
      if (d.id === myPushId) { const sub = await currentSub(); if (sub) await sub.unsubscribe(); }
      await rest('DELETE', 'api/push?id=' + encodeURIComponent(d.id));
      toast('Notifications off for ' + d.name + '.', 'ok');
    } catch (e) { if (!handleAuthError(e)) toast(e.message, 'err'); }
    renderPush();
  }

  $('pushOn').addEventListener('click', async () => {
    try {
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') { toast('Notifications weren\'t allowed. You can allow them in this browser\'s settings.', 'err'); return renderPush(); }
      const reg = await navigator.serviceWorker.register('sw.js', { scope: './' });
      await navigator.serviceWorker.ready;
      let sub = await reg.pushManager.getSubscription();
      // a subscription made for an older Houston key (Houston reinstalled) has to be renewed
      if (sub && sub.options && sub.options.applicationServerKey && b64u(sub.options.applicationServerKey) !== pushInfo.key) { await sub.unsubscribe(); sub = null; }
      if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: unb64u(pushInfo.key) });
      const j = await rest('POST', 'api/push', { subscription: sub.toJSON(), name: deviceName() });
      if (settings && settings.alerts) settings.alerts.enabled = true;
      $('alertsSwitch').setAttribute('aria-checked', 'true');
      await rest('POST', 'api/alerts/test', { device: j.id });
      toast('Notifications on. A test is on its way.', 'ok');
    } catch (e) { if (!handleAuthError(e)) toast(e.message || 'Couldn\'t turn on notifications here.', 'err'); }
    renderPush();
  });
  $('pushOff').addEventListener('click', () => { const d = ((pushInfo && pushInfo.devices) || []).find(x => x.id === myPushId); if (d) removeDevice(d); });
  $('pushTest').addEventListener('click', async () => {
    try { await rest('POST', 'api/alerts/test', { device: myPushId }); toast('Test sent to this device.', 'ok'); }
    catch (e) { if (!handleAuthError(e)) toast(e.message, 'err'); }
  });

  function renderPeers(list) {
    const box = $('peerRows'); box.textContent = '';
    list.forEach(p => box.append(peerRow(p.name, p.host)));
    if (!list.length) box.append(el('div', { class: 'note', style: 'margin-bottom:10px' }, 'No other Apollos added.'));
  }
  function peerRow(name, host) {
    const row = el('div', { class: 'peer-row' },
      el('input', { class: 'nm', type: 'text', placeholder: 'Name', 'aria-label': 'Name', value: name || '' }),
      el('input', { type: 'text', placeholder: '192.168.1.51', 'aria-label': 'Address', value: host || '', spellcheck: 'false' }),
      el('button', { class: 'icon-btn', type: 'button', 'aria-label': 'Remove', html: ICON.trash, onclick: () => row.remove() }));
    return row;
  }
  $('addPeer').addEventListener('click', () => { const n = $('peerRows').querySelector('.note'); if (n) n.remove(); $('peerRows').append(peerRow('', '')); });
  $('savePeers').addEventListener('click', () => {
    const list = [...$('peerRows').querySelectorAll('.peer-row')].map(r => { const i = r.querySelectorAll('input'); return { name: i[0].value.trim(), host: i[1].value.trim() }; }).filter(p => p.host);
    saveSettings({ apollos: list }, list.length ? 'Saved. They show on the Home tab.' : 'Saved.');
  });
  $('findPeers').addEventListener('click', async () => {
    toast('Searching your network (about 10 seconds)…', '', 20000);
    $('findPeers').disabled = true;
    try {
      const j = await rest('POST', 'api/discover', {});
      const known = new Set((settings.apollos || []).map(p => p.host));
      const ul = $('foundList'); ul.textContent = '';
      const others = j.found.filter(f => !f.self);
      if (!others.length) ul.append(el('li', { class: 'sub' }, 'No other Apollos found on this network.'));
      for (const f of others) {
        ul.append(el('li', {}, el('span', {}, f.host + (f.houston ? ' · Houston ' + f.houston : ' · no Houston yet')),
          known.has(f.host) ? el('span', { class: 'sub', style: 'flex:none' }, 'Added') :
          el('button', { class: 'secondary small', type: 'button', onclick: ev => {
            const n = $('peerRows').querySelector('.note'); if (n) n.remove();
            $('peerRows').append(peerRow('Apollo ' + f.host.split('.').pop(), f.host)); ev.target.disabled = true; ev.target.textContent = 'Added (save)';
          } }, 'Add')));
      }
      toast('');
    } catch (e) { if (!handleAuthError(e)) toast(e.message, 'err'); }
    finally { $('findPeers').disabled = false; }
  });

  let autoKey = null;
  async function renderAutomation() {
    const on = !!(settings.automation && settings.automation.enabled);
    $('autoOff').classList.toggle('hidden', on); $('autoOn').classList.toggle('hidden', !on);
    document.querySelectorAll('.iii-txt').forEach(x => x.classList.toggle('hidden', !III));
    if (!on) return;
    if (!autoKey) { try { autoKey = (await rest('GET', 'api/automation')).key; } catch (e) { return; } }
    const base = location.origin;
    $('autoKey').textContent = autoKey || '';
    $('autoSay').textContent = base + '/api/v1/say';
    $('autoAct').textContent = base + '/api/v1/action/turbo';
  }
  async function newKey(confirmFirst) {
    if (confirmFirst && !(await ask('Make a new key?', 'Shortcuts using the old key stop working until you paste in the new one.', 'New key', { danger: true }))) return;
    try { autoKey = (await rest('POST', 'api/automation', {})).key; settings.automation = { enabled: true }; renderAutomation(); toast('Key ready. Copy it into your shortcut.', 'ok'); }
    catch (e) { if (!handleAuthError(e)) toast(e.message, 'err'); }
  }
  $('makeKey').addEventListener('click', () => newKey(false));
  $('rotateKey').addEventListener('click', () => newKey(true));
  $('killKey').addEventListener('click', async () => {
    if (!(await ask('Turn off shortcut access?', 'Shortcuts and voice assistants stop working with Houston until you create a new key.', 'Turn off', { danger: true }))) return;
    try { await rest('DELETE', 'api/automation'); autoKey = null; settings.automation = { enabled: false }; renderAutomation(); toast('Shortcut access is off.', 'ok'); }
    catch (e) { if (!handleAuthError(e)) toast(e.message, 'err'); }
  });
  $('copyKey').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(autoKey); toast('Key copied.', 'ok'); }
    catch (e) { const r = document.createRange(); r.selectNodeContents($('autoKey')); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); toast('Key selected: copy it with your device\'s copy command.'); }
  });

  $('copyTip').addEventListener('click', async () => {
    const addr = $('tipAddr').textContent.trim();
    try { await navigator.clipboard.writeText(addr); toast('Tip jar address copied. Thank you!', 'ok'); }
    catch (e) { const r = document.createRange(); r.selectNodeContents($('tipAddr')); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); toast('Address selected: copy it with your device\'s copy command.'); }
  });

  // ---------------------------------------------------------------- bitcoin price
  const FIATS = ['USD', 'EUR', 'GBP', 'CAD', 'AUD', 'JPY', 'CHF'];
  let price = null, priceTimer = null;
  const fmtFiat = (v, fiat, digits) => { try { return new Intl.NumberFormat(undefined, { style: 'currency', currency: fiat, maximumFractionDigits: digits || 0, minimumFractionDigits: digits || 0 }).format(v); } catch (e) { return Math.round(v).toLocaleString() + ' ' + fiat; } };
  const fiatSymbol = fiat => { try { return new Intl.NumberFormat(undefined, { style: 'currency', currency: fiat, currencyDisplay: 'narrowSymbol' }).formatToParts(1).find(p => p.type === 'currency').value; } catch (e) { return fiat; } };
  function chgPill(node, ch) {
    if (ch == null) { node.className = 'chg flat'; node.textContent = '–'; node.removeAttribute('aria-label'); return; }
    const dir = ch > 0.005 ? 'up' : ch < -0.005 ? 'down' : 'flat';
    node.className = 'chg ' + dir;
    node.textContent = (dir === 'up' ? '▲ +' : dir === 'down' ? '▼ −' : '') + Math.abs(ch).toFixed(2) + '%';
    node.setAttribute('aria-label', (dir === 'down' ? 'down ' : 'up ') + Math.abs(ch).toFixed(2) + ' percent in 24 hours');
  }
  function sparkline(host, pts, up) {
    host.textContent = '';
    if (!pts || pts.length < 2) return;
    const W = Math.max(120, host.clientWidth || 300), H = 56, P = 4;
    const ys = pts.map(p => p[1]), lo = Math.min(...ys), hi = Math.max(...ys), t0 = pts[0][0], t1 = pts[pts.length - 1][0];
    const x = t => P + (t - t0) / Math.max(1, t1 - t0) * (W - 2 * P), y = v => P + (1 - (v - lo) / Math.max(1e-9, hi - lo)) * (H - 2 * P);
    const color = 'var(--btc)';
    const d = pts.map((p, i) => (i ? 'L' : 'M') + x(p[0]).toFixed(1) + ' ' + y(p[1]).toFixed(1)).join(' ');
    const svg = sv('svg', { viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: 'none', role: 'img', 'aria-label': 'Price over the last 24 hours, from ' + fmtFiat(pts[0][1], price.fiat) + ' to ' + fmtFiat(ys[ys.length - 1], price.fiat) });
    const gid = 'spk' + Math.random().toString(36).slice(2, 7);
    const defs = sv('defs', {}); const g = sv('linearGradient', { id: gid, x1: 0, y1: 0, x2: 0, y2: 1 });
    g.append(sv('stop', { offset: 0, style: 'stop-color:' + color + ';stop-opacity:.22' }), sv('stop', { offset: 1, style: 'stop-color:' + color + ';stop-opacity:0' }));
    defs.append(g); svg.append(defs);
    svg.append(sv('path', { d: d + ` L${x(t1).toFixed(1)} ${H} L${x(t0).toFixed(1)} ${H} Z`, fill: `url(#${gid})` }));
    svg.append(sv('path', { d, fill: 'none', style: 'stroke:' + color, 'stroke-width': 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', 'vector-effect': 'non-scaling-stroke' }));
    host.append(svg);
  }
  async function loadPrice() {
    if (settings && settings.price && settings.price.enabled === false) { price = null; renderPrice(); return; }
    try {
      const r = await fetch('api/price', { cache: 'no-store' });
      price = r.ok ? await r.json() : null;
    } catch (e) { /* keep the last one */ }
    renderPrice();
  }
  function renderPrice() {
    const on = !!(price && price.enabled && price.price);
    $('ticker').classList.toggle('hidden', !on);
    $('hdrPrice').classList.toggle('on', on);
    if (!on) { $('hdrPrice').textContent = ''; return; }
    $('tkPrice').textContent = fmtFiat(price.price, price.fiat);
    chgPill($('tkChg'), price.change24);
    const ageMin = Math.max(0, Math.round((Date.now() / 1000 - price.updated) / 60));
    const range = price.high24 != null ? '24h low ' + fmtFiat(price.low24, price.fiat) + ' · high ' + fmtFiat(price.high24, price.fiat) + ' · ' : '';
    $('tkMeta').textContent = range + price.source + ', ' + (ageMin < 1 ? 'just now' : ageMin + ' min ago') + (price.error && ageMin > 5 ? ' (can\'t update right now)' : '');
    sparkline($('tkSpark'), price.points, (price.change24 || 0) >= 0);
    const hp = $('hdrPrice'); hp.textContent = '';
    const chg = el('span', {}); chgPill(chg, price.change24);
    hp.append(el('span', { class: 'b' }, '₿'), fmtFiat(price.price, price.fiat), chg);
    hp.setAttribute('aria-label', 'Bitcoin ' + fmtFiat(price.price, price.fiat) + ', open price chart');
  }
  $('hdrPrice').addEventListener('click', () => go('stats'));
  $('ticker').addEventListener('click', () => go('stats'));
  $('ticker').style.cursor = 'pointer';
  window.addEventListener('resize', () => { if (price && view === 'control') sparkline($('tkSpark'), price.points, (price.change24 || 0) >= 0); });

  // ---------------------------------------------------------------- network, market, Fear & Greed, news (Stats)
  let market = null, marketSkew = 0, sinceTimer = null;
  const compactMoney = (v, fiat) => { try { return new Intl.NumberFormat(undefined, { style: 'currency', currency: fiat, notation: 'compact', maximumFractionDigits: 2 }).format(v); } catch (e) { return shortNum(v) + ' ' + fiat; } };
  const mmss = sec => { sec = Math.max(0, Math.round(sec)); const m = Math.floor(sec / 60), s = sec % 60; return m >= 60 ? Math.floor(m / 60) + 'h ' + (m % 60) + 'm' : m + 'm ' + String(s).padStart(2, '0') + 's'; };
  async function loadMarket() {
    try {
      const r = await fetch('api/market', { cache: 'no-store' });
      market = r.ok ? await r.json() : null;
    } catch (e) { market = null; }
    renderMarket();
  }
  function renderSince() {
    const n = market && market.network;
    $('mSince').textContent = n && n.lastBlockTime ? mmss(Date.now() / 1000 + marketSkew - n.lastBlockTime) : '–';
  }
  function renderMarket() {
    const on = !!(market && market.enabled);
    $('marketSection').classList.toggle('hidden', !on);
    clearInterval(sinceTimer);
    if (!on) return;
    marketSkew = (market.now || Date.now() / 1000) - Date.now() / 1000;
    const f = market.fng, n = market.network, m = market.market || {}, fiat = market.fiat || 'USD';
    $('fngVal').textContent = f ? String(f.value) : '–';
    $('fngLabel').textContent = f ? f.label : 'Not available right now';
    $('fngNeedle').style.transform = 'rotate(' + ((f ? f.value : 50) * 1.8 - 90) + 'deg)';
    $('fngNeedle').style.visibility = f ? 'visible' : 'hidden';
    $('mHeight').textContent = n ? n.height.toLocaleString() : '–';
    $('mSpeed').textContent = n && n.blockMinutes ? n.blockMinutes.toFixed(1) + ' min' : '–';
    $('mRetarget').textContent = n && n.retargetChange != null ? (n.retargetChange >= 0 ? '+' : '−') + Math.abs(n.retargetChange).toFixed(2) + '% in ' + (n.retargetBlocks || 0).toLocaleString() + ' blocks' : '–';
    renderSince(); sinceTimer = setInterval(() => { if (view === 'stats' && !document.hidden) renderSince(); }, 1000);
    $('mCap').textContent = m.marketCap ? (m.capEstimated ? '≈ ' : '') + compactMoney(m.marketCap, fiat) : '–';
    $('mDom').textContent = m.dominance != null ? m.dominance.toFixed(1) + '%' : '–';
    $('mVol').textContent = m.volume24 ? compactMoney(m.volume24, fiat) : '–';
    $('mSatsLbl').textContent = 'Sats per ' + (fiat === 'USD' ? 'dollar' : fiat);
    $('mSats').textContent = m.satsPer ? m.satsPer.toLocaleString() + ' sats' : '–';
    const ul = $('newsList'); ul.textContent = '';
    const items = (market.news && market.news.items) || [];
    if (!items.length) ul.append(el('li', { class: 'sub' }, 'No headlines right now.'));
    const now = Date.now() / 1000 + marketSkew;
    for (const it of items) {
      if (!/^https:\/\//.test(it.link)) continue;             // the server only sends https links; checked again here
      ul.append(el('li', {}, el('a', { href: it.link, target: '_blank', rel: 'noopener noreferrer' }, it.title),
        el('span', {}, market.news.source + (it.time ? ' · ' + ago(Math.max(0, now - it.time)) : ''))));
    }
  }

  // ---------------------------------------------------------------- your other Apollos
  async function loadFleet() {
    if (!settings || !(settings.apollos || []).length) { $('fleetCard').classList.add('hidden'); return; }
    try {
      const j = await rest('GET', 'api/fleet');
      const ul = $('fleetList'); ul.textContent = '';
      const rows = [Object.assign({ name: 'This Apollo', self: true }, j.self)].concat(j.apollos);
      for (const a of rows) {
        const st = a.status || 'unknown';
        const bits = st === 'online' ? [((a.ghs || 0) / 1000).toFixed(2) + ' TH/s', a.watts ? Math.round(a.watts) + ' W' : null, a.tempC != null ? fmtTemp(a.tempC) : null].filter(Boolean).join(' · ')
                   : st === 'offline' ? 'Stopped' : st === 'unreachable' ? 'Not reachable' : st;
        ul.append(el('li', {}, el('span', { class: 'dot ' + (st === 'unreachable' ? '' : st) }),
          el('span', { class: 'nm' }, el('b', {}, a.name || a.host), el('span', {}, bits)),
          a.self ? null : el('a', { href: a.url, target: a.houston ? '_self' : '_blank', rel: 'noopener' }, a.houston ? 'Open Houston' : 'Dashboard')));
      }
      $('fleetCard').classList.remove('hidden');
    } catch (e) { handleAuthError(e); }
  }

  // ---------------------------------------------------------------- stats
  document.querySelectorAll('#view-stats [data-range]').forEach(b => b.addEventListener('click', () => {
    statsRange = b.dataset.range; setSeg(b.parentNode, 'range', statsRange); loadStats();
  }));
  let resizeTimer = null;
  window.addEventListener('resize', () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => { if (view === 'stats' && statsData) drawCharts(); }, 150); });

  async function loadStats(quiet) {
    document.querySelectorAll('#view-stats .chart').forEach(c => c.style.opacity = statsData ? .55 : 1);
    try {
      statsData = await rest('GET', 'api/history?range=' + statsRange);
      drawTiles(); drawCharts(); drawEnergy(); drawSystem();
    } catch (e) { if (!handleAuthError(e) && !quiet) toast(e.message, 'err'); }
    document.querySelectorAll('#view-stats .chart').forEach(c => c.style.opacity = 1);
    loadNodeStats(); loadPriceChart(); loadMarket();
  }

  async function loadPriceChart() {
    if (!settings || !settings.price || settings.price.enabled === false) { $('priceCard').classList.add('hidden'); return; }
    try {
      const r = await fetch('api/price?range=' + statsRange, { cache: 'no-store' });
      const pv = r.ok ? await r.json() : null;
      if (!pv || !pv.points || pv.points.length < 2) { $('priceCard').classList.add('hidden'); return; }
      $('priceCard').classList.remove('hidden');
      $('chPriceUnit').textContent = pv.fiat;
      const pts = pv.points.map(p => ({ t: p[0], v: p[1] }));
      const now = Date.now() / 1000, span = statsRange === '7d' ? 7 * 86400 : 86400;
      lineChart($('chPrice'), pts, { x0: now - span, x1: now, series: [{ f: 'v', name: 'Bitcoin', color: 'var(--btc)', fmt: v => fmtFiat(v, pv.fiat) }], area: true, gap: 3 * 3600 });
    } catch (e) {}
  }

  function drawTiles() {
    const pts = statsData.points, e = statsData.energy;
    const hs = pts.map(p => p.h).filter(v => v != null);
    const avg = hs.length ? hs.reduce((a, b) => a + b, 0) / hs.length : null;
    $('tHash').textContent = avg != null ? (avg / 1000).toFixed(2) + ' TH/s' : '–';
    $('tHashSub').textContent = avg != null ? 'while mining, last ' + (statsRange === '7d' ? '7 days' : '24 hours') : 'No data yet';
    const on = pts.length ? pts.reduce((a, p) => a + (p.on || 0), 0) / pts.length : null;
    $('tUp').textContent = on != null ? Math.round(on * 100) + '%' : '–';
    $('tUpSub').textContent = on != null ? 'of the time Houston was watching' : ' ';
    $('tKwh').textContent = e.perDay != null ? e.perDay.toFixed(2) + ' kWh' : '–';
    $('tKwhSub').textContent = e.days < 1 ? 'estimate from ' + Math.max(1, Math.round(e.days * 24)) + ' h of readings' : 'average over ' + e.days.toFixed(1) + ' days';
    if (e.rate == null) {
      $('tCost').textContent = '–'; $('tCostSub').textContent = '';
      $('tCostSub').append(el('button', { class: 'linkbtn', type: 'button', onclick: () => go('settings') }, 'Add your electricity price'));
    } else {
      $('tCost').textContent = money(e.costPerMonth) + '/mo';
      let sats = '';
      if (price && price.price && e.costPerDay != null && fiatSymbol(price.fiat) === ((settings && settings.currency) || '$'))
        sats = ' ≈ ' + Math.round(e.costPerDay / price.price * 1e8).toLocaleString() + ' sats';
      $('tCostSub').textContent = money(e.costPerDay) + sats + ' per day at ' + money(e.rate) + '/kWh';
    }
    $('statsNote').textContent = statsData.points.length ? '' : 'Houston saves a reading every minute; charts fill in as it runs.';
  }

  function drawCharts() {
    const pts = statsData.points;
    const span = statsRange === '7d' ? 7 * 86400 : 86400;
    const now = Date.now() / 1000;
    const lim = settings && settings.alerts && settings.alerts.enabled && settings.alerts.hot !== false ? settings.alerts.hotC : null;
    lineChart($('chHash'), pts, { x0: now - span, x1: now, series: [{ f: 'h', name: 'Hashrate', color: 'var(--text)', scale: v => v / 1000, fmt: v => v.toFixed(2) + ' TH/s' }], zero: true, area: true, modes: true });
    lineChart($('chPower'), pts, { x0: now - span, x1: now, series: [{ f: 'w', name: 'Power', color: 'var(--m-balanced)', fmt: v => Math.round(v) + ' W' }], zero: true, area: true });
    lineChart($('chTemp'), pts, { x0: now - span, x1: now, series: [
      { f: 'tb', name: 'Hashboard', color: 'var(--m-turbo)', scale: toUnit, fmt: v => Math.round(v) + '°' + units },
      { f: 'ts', name: 'System', color: 'var(--m-balanced)', scale: toUnit, fmt: v => Math.round(v) + '°' + units }], ref: lim != null ? toUnit(lim) : null });
    $('chTempUnit').textContent = '°' + units;
    $('limitKey').classList.toggle('hidden', lim == null);
    const seen = [...new Set(pts.map(p => p.m).filter(Boolean))];
    const lg = $('modeLegend'); lg.textContent = '';
    if (seen.length) seen.forEach(m => lg.append(el('span', {}, el('i', { style: 'background:' + modeColor(m) }), modeName(m))));
  }

  function niceTicks(lo, hi, n) {
    if (hi <= lo) hi = lo + 1;
    const raw = (hi - lo) / n, mag = Math.pow(10, Math.floor(Math.log10(raw)));
    const step = [1, 2, 2.5, 5, 10].map(x => x * mag).find(x => x >= raw) || raw;
    const a = Math.floor(lo / step) * step, b = Math.ceil(hi / step) * step, out = [];
    for (let v = a; v <= b + step / 2; v += step) out.push(+v.toFixed(6));
    return out;
  }

  const SVGNS = 'http://www.w3.org/2000/svg';
  const sv = (tag, attrs) => { const n = document.createElementNS(SVGNS, tag); for (const k in attrs) n.setAttribute(k, attrs[k]); return n; };

  function lineChart(host, pts, o) {
    host.textContent = '';
    const W = Math.max(260, host.clientWidth || 320), stripH = o.modes ? 12 : 0, H = 170 + stripH;
    const L = 40, R = 10, T = 10, B = 22 + stripH;
    const vals = [];
    o.series.forEach(s => pts.forEach(p => { if (p[s.f] != null) vals.push((s.scale || (v => v))(p[s.f])); }));
    if (o.ref != null) vals.push(o.ref);
    if (!vals.length) {
      const old = host.parentElement.querySelector('details.table[data-for="' + host.id + '"]'); if (old) old.remove();
      host.append(el('div', { class: 'chart-empty' }, 'No readings yet for this period.')); return;
    }
    let lo = Math.min(...vals), hi = Math.max(...vals);
    if (o.zero) lo = 0; else { const pad = Math.max(2, (hi - lo) * 0.15); lo -= pad; hi += pad; }
    const ticks = niceTicks(lo, hi, 4); lo = ticks[0]; hi = ticks[ticks.length - 1];
    const x = t => L + (t - o.x0) / (o.x1 - o.x0) * (W - L - R);
    const y = v => T + (1 - (v - lo) / (hi - lo)) * (H - T - B);
    const svg = sv('svg', { viewBox: `0 0 ${W} ${H}`, height: H, role: 'img', 'aria-label': host.getAttribute('aria-label') || '' });
    // grid + y labels
    ticks.forEach(v => {
      svg.append(sv('line', { x1: L, x2: W - R, y1: y(v), y2: y(v), style: 'stroke:var(--line)', 'stroke-width': 1 }));
      const t = sv('text', { x: L - 6, y: y(v) + 4, 'text-anchor': 'end', style: 'fill:var(--muted)', 'font-size': 10.5 }); t.textContent = Math.abs(v) >= 10000 ? Math.round(v / 1000) + 'K' : +v.toFixed(2); svg.append(t);
    });
    // x labels: every 6 h (24 h) or each day (7 d)
    const step = (o.x1 - o.x0) > 2 * 86400 ? 86400 : 6 * 3600;
    const first = Math.ceil(o.x0 / step) * step;
    for (let t = first; t <= o.x1; t += step) {
      const d = new Date(t * 1000);
      const lab = step === 86400 ? d.toLocaleDateString([], { weekday: 'short' }) : d.toLocaleTimeString([], { hour: 'numeric' });
      const tx = sv('text', { x: x(t), y: H - 6, 'text-anchor': 'middle', style: 'fill:var(--muted)', 'font-size': 10.5 }); tx.textContent = lab; svg.append(tx);
    }
    // mode strip (which mode the miner was in)
    if (o.modes) {
      const bw = pts.length > 1 ? (pts[1].t - pts[0].t) : 300;
      pts.forEach(p => { if (p.m && p.on > 0) svg.append(sv('rect', { x: x(p.t), y: H - B + 6, width: Math.max(1, x(p.t + bw) - x(p.t)), height: 6, style: 'fill:' + modeColor(p.m) })); });
    }
    if (o.ref != null) {
      svg.append(sv('line', { x1: L, x2: W - R, y1: y(o.ref), y2: y(o.ref), style: 'stroke:var(--muted)', 'stroke-width': 1, 'stroke-dasharray': '4 4' }));
    }
    // lines (broken where there's no reading, e.g. while stopped)
    const gapLimit = o.gap || (pts.length > 1 ? (pts[1].t - pts[0].t) : 300) * 1.5;
    o.series.forEach((s, si) => {
      const sc = s.scale || (v => v);
      let d = '', area = '', run = [], prevT = null;
      const flush = () => {
        if (!run.length) return;
        d += run.map((p, i) => (i ? 'L' : 'M') + x(p.t).toFixed(1) + ' ' + y(sc(p[s.f])).toFixed(1)).join(' ') + ' ';
        if (o.area && o.series.length === 1) area += 'M' + x(run[0].t).toFixed(1) + ' ' + y(lo) + ' ' + run.map(p => 'L' + x(p.t).toFixed(1) + ' ' + y(sc(p[s.f])).toFixed(1)).join(' ') + ' L' + x(run[run.length - 1].t).toFixed(1) + ' ' + y(lo) + ' Z ';
        run = [];
      };
      pts.forEach(p => { if (p[s.f] == null || (prevT != null && p.t - prevT > gapLimit)) flush(); if (p[s.f] != null) run.push(p); prevT = p.t; });
      flush();
      if (area) {
        const gid = 'g' + host.id + si;
        const grad = sv('linearGradient', { id: gid, x1: 0, y1: 0, x2: 0, y2: 1 });
        grad.append(sv('stop', { offset: 0, style: 'stop-color:' + s.color + ';stop-opacity:.18' }), sv('stop', { offset: 1, style: 'stop-color:' + s.color + ';stop-opacity:0' }));
        const defs = sv('defs', {}); defs.append(grad); svg.append(defs);
        svg.append(sv('path', { d: area, fill: 'url(#' + gid + ')' }));
      }
      if (d) svg.append(sv('path', { d, fill: 'none', style: 'stroke:' + s.color, 'stroke-width': 1.75, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }));
      // end dot + value on the latest reading
      const last = [...pts].reverse().find(p => p[s.f] != null);
      if (last) svg.append(sv('circle', { cx: x(last.t), cy: y(sc(last[s.f])), r: 4, style: 'fill:' + s.color + ';stroke:var(--card)', 'stroke-width': 2 }));
    });
    // crosshair + tooltip
    const cross = sv('line', { y1: T, y2: H - B, style: 'stroke:var(--muted)', 'stroke-width': 1, visibility: 'hidden' });
    const dots = o.series.map(s => sv('circle', { r: 4, style: 'fill:' + s.color + ';stroke:var(--card)', 'stroke-width': 2, visibility: 'hidden' }));
    svg.append(cross); dots.forEach(c => svg.append(c));
    const hit = sv('rect', { x: L, y: 0, width: W - L - R, height: H - B + stripH, fill: 'transparent' }); svg.append(hit);
    host.append(svg);
    const tip = el('div', { class: 'tip hidden' }); host.append(tip);
    let idx = -1;
    const show = i => {
      if (i < 0 || i >= pts.length) return; idx = i;
      const p = pts[i], cx = x(p.t);
      cross.setAttribute('x1', cx); cross.setAttribute('x2', cx); cross.setAttribute('visibility', 'visible');
      tip.textContent = '';
      const d = new Date(p.t * 1000);
      tip.append(el('div', { class: 'tt' }, (statsRange === '7d' ? d.toLocaleDateString([], { weekday: 'short' }) + ' ' : '') + d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }) + (p.m ? ' · ' + modeName(p.m) : '')));
      o.series.forEach((s, si) => {
        const v = p[s.f];
        if (v == null) { dots[si].setAttribute('visibility', 'hidden'); tip.append(el('div', { class: 'row' }, el('span', { class: 'key', style: 'background:' + s.color }), el('b', {}, '–'), ' ', s.name)); return; }
        const sv2 = (s.scale || (q => q))(v);
        dots[si].setAttribute('cx', cx); dots[si].setAttribute('cy', y(sv2)); dots[si].setAttribute('visibility', 'visible');
        tip.append(el('div', { class: 'row' }, el('span', { class: 'key', style: 'background:' + s.color }), el('b', {}, s.fmt(sv2)), o.series.length > 1 ? ' ' + s.name : ''));
      });
      tip.classList.remove('hidden');
      const tw = tip.offsetWidth, px = cx / W * host.clientWidth;
      tip.style.left = Math.min(host.clientWidth - tw, Math.max(0, px - tw / 2)) + 'px'; tip.style.top = '-6px'; tip.style.transform = 'translateY(-100%)';
    };
    const hide = () => { cross.setAttribute('visibility', 'hidden'); dots.forEach(c => c.setAttribute('visibility', 'hidden')); tip.classList.add('hidden'); };
    const nearest = ev => {
      const r = svg.getBoundingClientRect(); const t = o.x0 + ((ev.clientX - r.left) / r.width * W - L) / (W - L - R) * (o.x1 - o.x0);
      let best = -1, bd = Infinity; pts.forEach((p, i) => { const dd = Math.abs(p.t - t); if (dd < bd) { bd = dd; best = i; } }); return best;
    };
    hit.addEventListener('pointermove', ev => show(nearest(ev)));
    hit.addEventListener('pointerdown', ev => show(nearest(ev)));
    hit.addEventListener('pointerleave', hide);
    host.onkeydown = ev => {
      if (ev.key === 'ArrowLeft') { show(idx < 0 ? pts.length - 1 : Math.max(0, idx - 1)); ev.preventDefault(); }
      else if (ev.key === 'ArrowRight') { show(idx < 0 ? pts.length - 1 : Math.min(pts.length - 1, idx + 1)); ev.preventDefault(); }
      else if (ev.key === 'Escape') hide();
    };
    host.onblur = hide;
    // table view (hourly, or daily for 7 days)
    const tbl = el('details', { class: 'table' }, el('summary', {}, 'Show as a table'));
    const tb = el('table', {}, el('tr', {}, el('th', {}, 'Time'), ...o.series.map(s => el('th', {}, s.name))));
    const every = statsRange === '7d' ? 6 : 12;
    pts.filter((p, i) => i % every === 0).forEach(p => {
      const d = new Date(p.t * 1000);
      tb.append(el('tr', {}, el('td', {}, (statsRange === '7d' ? d.toLocaleDateString([], { weekday: 'short' }) + ' ' : '') + d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })),
        ...o.series.map(s => el('td', {}, p[s.f] == null ? '–' : s.fmt((s.scale || (q => q))(p[s.f]))))));
    });
    tbl.append(tb); tbl.dataset.for = host.id;
    const card = host.parentElement, old = card.querySelector('details.table[data-for="' + host.id + '"]');
    if (old) { tbl.open = old.open; old.remove(); }
    card.append(tbl);
  }

  function drawEnergy() {
    const e = statsData.energy, ul = $('energyBars'); ul.textContent = '';
    const rows = Object.entries(e.byMode || {}).filter(([m, v]) => v.kwh > 0).sort((a, b) => b[1].kwh - a[1].kwh);
    if (!rows.length) { ul.append(el('li', { class: 'sub', style: 'display:block' }, 'Fills in as Houston records power readings.')); $('energyNote').textContent = ''; return; }
    const max = Math.max(...rows.map(r => r[1].kwh));
    for (const [m, v] of rows) {
      const cost = e.rate != null ? ' · ' + money(v.kwh * e.rate) : '';
      ul.append(el('li', {}, el('span', { class: 'lbl' }, el('i', { style: 'background:' + modeColor(m) }), m === 'unknown' ? 'Other' : modeName(m)),
        el('span', { class: 'trk' }, el('span', { class: 'bar', style: `width:${Math.max(1, v.kwh / max * 70)}%;background:${modeColor(m)}` }),
          el('span', { class: 'val' }, v.kwh.toFixed(2) + ' kWh · ' + (v.hours < 10 ? v.hours.toFixed(1) : Math.round(v.hours)) + ' h' + cost))));
    }
    const x = e.extraVsNormal;
    $('energyNote').textContent = x && x.kwh > 0.01
      ? 'Running faster than ' + modeName(x.base) + ' used ' + x.kwh.toFixed(2) + ' kWh extra' + (x.cost != null ? ' (' + money(x.cost) + ')' : '') + ' over the last ' + (e.days >= 1 ? e.days.toFixed(1) + ' days' : Math.round(e.days * 24) + ' hours') + '.'
      : 'Last ' + (e.days >= 1 ? Math.min(7, e.days).toFixed(1) + ' days' : Math.max(1, Math.round(e.days * 24)) + ' hours') + '.';
  }

  function drawSystem() {
    renderMeters(statsData.last || {});
    loadSystemInfo();
  }

  function renderMeters(L) {
    const box = $('meters'); box.textContent = '';
    const meter = (name, used, total, unit) => {
      if (used == null || !total) return;
      const pct = used / total * 100;
      box.append(el('div', { class: 'meter' }, el('div', { class: 'mtop' }, name, el('span', {}, unit ? unit : Math.round(pct) + '%')),
        el('div', { class: 'trk' }, el('div', { class: 'fill' + (pct >= 95 ? ' bad' : pct >= 85 ? ' warn' : ''), style: 'width:' + Math.min(100, pct).toFixed(1) + '%' }))));
    };
    const gb = k => (k / 1048576).toFixed(k > 1e8 ? 0 : 1) + ' GB';
    if (L.cpu != null) meter('CPU', L.cpu, 100);
    if (L.mem != null) meter('Memory', L.mem, 100);
    if (L.disk) meter('System drive', L.disk.used, L.disk.total, gb(L.disk.used) + ' of ' + gb(L.disk.total) + ' · ' + Math.round(100 * L.disk.used / L.disk.total) + '%');
    if (L.nodeDisk) meter('Node drive', L.nodeDisk.used, L.nodeDisk.total, gb(L.nodeDisk.used) + ' of ' + gb(L.nodeDisk.total) + ' · ' + Math.round(100 * L.nodeDisk.used / L.nodeDisk.total) + '%');
    $('sTemp').textContent = fmtTemp(L.ts);
  }

  async function loadSystemInfo() {
    try {
      const d = await gql('query { Mcu { stats { result { stats { hostname operatingSystem uptime temperature cpu { usedPercent } memory { total available } disks { total used mountPoint } } } } } }');
      const s = d.Mcu.stats.result && d.Mcu.stats.result.stats;
      if (!s) return;
      const disks = (s.disks || []).filter(x => x.total);
      const root = disks.find(x => x.mountPoint === '/');
      const others = disks.filter(x => !['/', '/boot', '/boot/efi'].includes(x.mountPoint)).sort((a, b) => b.total - a.total);
      const nd = others.find(x => /nvme|node/.test(x.mountPoint || '')) || others[0];
      const t = s.temperature != null ? (s.temperature > 1000 ? s.temperature / 1000 : s.temperature) : null;
      renderMeters({ cpu: s.cpu && s.cpu.usedPercent, mem: s.memory && s.memory.total ? 100 * (1 - s.memory.available / s.memory.total) : null,
        disk: root && { used: root.used, total: root.total }, nodeDisk: nd && { used: nd.used, total: nd.total }, ts: t });
      $('sHost').textContent = s.hostname || '–';
      $('sOs').textContent = s.operatingSystem || '–';
      const up = s.uptime ? new Date(s.uptime.replace(' ', 'T')) : null;
      $('sUp').textContent = up && !isNaN(up) ? up.toLocaleDateString([], { month: 'short', day: 'numeric' }) + ', ' + up.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }) : (s.uptime || '–');
    } catch (e) { handleAuthError(e); }
  }

  async function loadNodeStats() {
    const card = $('nodeStatsCard');
    if (node.available === false) { card.classList.add('hidden'); return; }
    try {
      const d = await gql(`query { Node { stats { result { stats { connectionCount blockchainInfo { blocks blockTime sizeOnDisk }
        miningInfo { difficulty networkhashps } networkInfo { subversion connections_in connections_out } } } } } }`);
      const s = d.Node.stats.result && d.Node.stats.result.stats;
      const bi = s && s.blockchainInfo, mi = s && s.miningInfo, ni = s && s.networkInfo;
      const nowS = device && device.time ? Date.parse(device.time) / 1000 + (Date.now() - loadedAt) / 1000 : Date.now() / 1000;
      $('nLast').textContent = bi && bi.blockTime ? ago(nowS - bi.blockTime) : '–';
      $('nSize').textContent = bi && bi.sizeOnDisk ? fmtBytes(bi.sizeOnDisk) : '–';
      $('nNet').textContent = mi && mi.networkhashps ? (mi.networkhashps / 1e21 >= 1 ? (mi.networkhashps / 1e21).toFixed(2) + ' ZH/s' : (mi.networkhashps / 1e18).toFixed(0) + ' EH/s') : '–';
      $('nDiff').textContent = mi && mi.difficulty ? bigWords(mi.difficulty) : '–';
      $('nConn').textContent = ni ? (ni.connections_in || 0) + ' / ' + (ni.connections_out || 0) : (s && s.connectionCount != null ? String(s.connectionCount) : '–');
      $('nVer').textContent = ni && ni.subversion ? ni.subversion.replace(/^\/|\/$/g, '').replace(/\(.*\)/, '').replace(':', ' ') : '–';
      card.classList.remove('hidden');
      stats.difficulty = mi && mi.difficulty;
    } catch (e) { handleAuthError(e); }
    try {
      const d = await gql('query { Node { recentBlocks(count: 10) { result { blocks { height timestamp extras { reward totalFees pool { name } } } } } } }');
      const blocks = (d.Node.recentBlocks.result && d.Node.recentBlocks.result.blocks) || [];
      const box = $('blocks'); box.textContent = '';
      const nowS = Date.now() / 1000;
      for (const b of blocks) {
        box.append(el('div', { class: 'blk' }, el('div', { class: 'h' }, '#' + b.height.toLocaleString()),
          el('b', {}, b.extras ? b.extras.reward.toFixed(3) + ' BTC' : '–'),
          el('div', { class: 'p' }, (b.extras && b.extras.pool && b.extras.pool.name) || 'Unknown'),
          el('div', { class: 'a' }, ago(nowS - b.timestamp))));
      }
      box.previousElementSibling.classList.toggle('hidden', !blocks.length);
    } catch (e) { $('blocks').textContent = ''; $('blocks').previousElementSibling.classList.add('hidden'); }
    loadSolo();
  }

  const stats = { difficulty: null };
  const parseRate = s => { if (s == null) return null; const m = String(s).match(/^([\d.]+)\s*([KMGTPE]?)/i); if (!m) return null;
    return parseFloat(m[1]) * Math.pow(1000, ' KMGTPE'.indexOf((m[2] || ' ').toUpperCase())); };

  async function loadSolo() {
    try {
      const d = await gql('query { Miner { stats { result { ckpool { pool { hashrate1hr accepted rejected bestshare } users { bestever } } } } } }');
      const ck = d.Miner.stats.result && d.Miner.stats.result.ckpool;
      if (!ck || !ck.pool) { $('soloCard').classList.add('hidden'); return; }
      const best = Math.max(ck.pool.bestshare || 0, ...((ck.users || []).map(u => u.bestever || 0)));
      const hr = parseRate(ck.pool.hashrate1hr);
      $('soloBest').textContent = bigWords(best).replace(/(\.\d)\d /, '$1 ');
      const diff = stats.difficulty;
      $('soloBestSub').textContent = diff ? (best / diff * 100).toFixed(best / diff < 0.001 ? 5 : 3) + '% of the difficulty needed for a block' : '';
      $('soloHash').textContent = hr ? (hr / 1e12).toFixed(2) + ' TH/s' : '–';
      $('soloShares').textContent = bigWords(ck.pool.accepted).replace(' billion', 'B').replace(' million', 'M') + ' / ' + bigWords(ck.pool.rejected).replace(' billion', 'B').replace(' million', 'M');
      if (hr && diff) {
        const pDay = hr * 86400 / (diff * 4294967296);
        $('soloOdds').textContent = '1 in ' + Math.round(1 / pDay).toLocaleString();
        const years = 1 / pDay / 365.25;
        $('soloEta').textContent = years >= 1 ? Math.round(years).toLocaleString() + ' years' : Math.round(1 / pDay) + ' days';
      } else { $('soloOdds').textContent = '–'; $('soloEta').textContent = '–'; }
      $('soloCard').classList.remove('hidden');
    } catch (e) { handleAuthError(e); }
  }

  // ---------------------------------------------------------------- start up
  // One-tap links (Siri Shortcuts, Android shortcuts, bookmarks): #start #stop #status
  // #eco #balanced #turbo, Apollo III #super_eco #custom-14, #node-start #node-stop. Also #schedule and #activity.
  const hash = location.hash.slice(1).toLowerCase().replace(/-/g, '_').replace(/^supereco$/, 'super_eco');
  const hm = hash.match(/^custom_?(\d{1,2})$/);
  let pendingAction = ['start', 'stop', 'super_eco', 'eco', 'balanced', 'turbo', 'node_start', 'node_stop'].includes(hash) ? hash : (hm ? 'custom:' + hm[1] : null);
  let pendingTab = ['schedule', 'activity', 'logs'].includes(hash) ? hash : null;
  if (hash) history.replaceState(null, '', location.pathname + location.search);

  window.addEventListener('beforeunload', e => { if (isDirty()) { e.preventDefault(); e.returnValue = ''; } });
  document.addEventListener('visibilitychange', () => { if (!document.hidden && token && !busy && view === 'control') refresh(true); });

  (async () => {
    await loadDevice();
    III = !!(device && device.chassis === 'apollo-iii');
    $('modelChip').textContent = III ? 'Apollo III' : device ? 'Apollo II' : '';
    $('modelChip').classList.toggle('hidden', !device);
    $('foot').textContent = 'Houston' + (device ? ' ' + device.version : '') + ' · connected via ' + location.hostname + ' · unofficial, not affiliated with FutureBit';
    buildModes();
    token = store.get();
    if (pendingAction && !token) toast('Sign in to run “' + pendingAction.replace('custom:', 'custom ').replace('_', ' ') + '”.');
    token ? showApp() : showLogin();
  })();
})();
