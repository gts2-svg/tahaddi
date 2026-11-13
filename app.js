/* تحدّي — مسابقة ثقافية للفرق */
'use strict';
const VERSION = '1.0.0';

const CATS = {
  religion:  { name: 'الدين',            icon: '🕌', file: 'data/religion.txt',  color: '#2fb47c' },
  history:   { name: 'التاريخ الإسلامي', icon: '📜', file: 'data/history.txt',   color: '#e0a13c' },
  geography: { name: 'الجغرافيا',        icon: '🌍', file: 'data/geography.txt', color: '#3a9be0' },
  poetry:    { name: 'الشعر',            icon: '🪶', file: 'data/poetry.txt',    color: '#b06ee0' },
};
const TEAM_COLORS = ['#e0b44c', '#3a9be0', '#e05a8a', '#2fb47c', '#b06ee0', '#e07a3a', '#4cd0d0', '#c8c8c8'];
const DIFF_NAME = { 1: 'سهل', 2: 'متوسط', 3: 'صعب' };
const LETTERS = ['أ', 'ب', 'ج', 'د'];
const LS = { settings: 'tahaddi_settings', used: 'tahaddi_used', game: 'tahaddi_game', reports: 'tahaddi_reports' };

const $ = s => document.querySelector(s);
const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const load = (k, d) => { try { const v = JSON.parse(localStorage.getItem(k)); return v ?? d; } catch { return d; } };
const save = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} };
const shuffle = a => { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const toAr = n => String(n); // أرقام إنجليزية: الصفر العربي (٠) يشبه النقطة
function hash(s) { let h = 5381; for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0; return (h >>> 0).toString(36); }

/* ---------- البيانات ---------- */
let BANK = {}; // cat -> [{id,cat,d,q,a,w:[]}]

function parseBank(cat, text) {
  const out = [];
  text.split(/\r?\n/).forEach(line => {
    line = line.trim();
    if (!line || line.startsWith('#')) return;
    const p = line.split('|').map(x => x.trim());
    if (p.length < 6) return;
    const d = parseInt(p[0], 10);
    if (![1, 2, 3].includes(d)) return;
    const q = p[1].replace(/\\n/g, '\n');
    out.push({ id: cat + ':' + hash(q), cat, d, q, a: p[2], w: p.slice(3, 6) });
  });
  return out;
}

async function loadBank() {
  await Promise.all(Object.entries(CATS).map(async ([k, c]) => {
    try { const r = await fetch(c.file + '?v=' + VERSION); BANK[k] = parseBank(k, await r.text()); }
    catch { BANK[k] = []; }
  }));
}

/* ---------- الإعدادات ---------- */
const DEFAULTS = {
  teams: ['الفريق الأول', 'الفريق الثاني'],
  cats: Object.keys(CATS), difficulty: 0, perTeam: 10, timer: 30,
  steal: true, fifty: true, sound: true,
};
let S = Object.assign({}, DEFAULTS, load(LS.settings, {}));
const saveSettings = () => save(LS.settings, S);

/* ---------- الصوت ---------- */
let actx;
function beep(type) {
  if (!S.sound) return;
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const seq = { ok: [[660, .09], [880, .16]], bad: [[220, .25]], tick: [[1000, .04]], win: [[523, .12], [659, .12], [784, .12], [1046, .3]] }[type];
    let t = actx.currentTime;
    seq.forEach(([f, d]) => {
      const o = actx.createOscillator(), g = actx.createGain();
      o.type = type === 'bad' ? 'sawtooth' : 'sine'; o.frequency.value = f;
      g.gain.setValueAtTime(.18, t); g.gain.exponentialRampToValueAtTime(.001, t + d);
      o.connect(g).connect(actx.destination); o.start(t); o.stop(t + d); t += d;
    });
  } catch {}
}

/* ---------- الشاشات ---------- */
function show(id) { document.querySelectorAll('.screen').forEach(s => s.classList.toggle('active', s.id === 'screen-' + id)); window.scrollTo(0, 0); }
function toast(msg) { const t = $('#toast'); t.textContent = msg; t.classList.remove('hidden'); clearTimeout(t._h); t._h = setTimeout(() => t.classList.add('hidden'), 1800); }
function modal(html, actions) {
  $('#modal-body').innerHTML = html;
  const a = $('#modal-actions'); a.innerHTML = '';
  (actions || [{ t: 'إغلاق' }]).forEach(x => {
    const b = el('button', 'btn ' + (x.primary ? 'primary' : 'ghost'), x.t);
    b.onclick = () => { $('#modal').classList.add('hidden'); x.f && x.f(); };
    a.appendChild(b);
  });
  $('#modal').classList.remove('hidden');
}

/* ---------- الرئيسية ---------- */
function renderHome() {
  const tl = $('#teams-list'); tl.innerHTML = '';
  S.teams.forEach((n, i) => {
    const row = el('div', 'team-input');
    const dot = el('span', 'dot'); dot.style.background = TEAM_COLORS[i];
    const inp = el('input'); inp.value = n; inp.maxLength = 24; inp.placeholder = 'اسم الفريق';
    inp.oninput = () => { S.teams[i] = inp.value; saveSettings(); };
    row.append(dot, inp); tl.appendChild(row);
  });
  $('#btn-remove-team').disabled = S.teams.length <= 1;
  $('#btn-add-team').disabled = S.teams.length >= 8;

  const cl = $('#cats-list'); cl.innerHTML = '';
  const used = new Set(load(LS.used, []));
  Object.entries(CATS).forEach(([k, c]) => {
    const total = (BANK[k] || []).length;
    const left = (BANK[k] || []).filter(q => !used.has(q.id)).length;
    const d = el('div', 'cat' + (S.cats.includes(k) ? ' on' : ''),
      `<div class="ic">${c.icon}</div><div class="nm">${c.name}</div><div class="ct">${toAr(left)} متبقٍ من ${toAr(total)}</div>`);
    d.style.setProperty('--c', c.color);
    d.onclick = () => {
      if (S.cats.includes(k)) { if (S.cats.length > 1) S.cats = S.cats.filter(x => x !== k); else return toast('اختر قسماً واحداً على الأقل'); }
      else S.cats.push(k);
      saveSettings(); renderHome();
    };
    cl.appendChild(d);
  });

  document.querySelectorAll('.seg').forEach(seg => {
    const key = seg.dataset.key;
    seg.querySelectorAll('button').forEach(b => {
      b.classList.toggle('on', +b.dataset.v === +S[key]);
      b.onclick = () => { S[key] = +b.dataset.v; saveSettings(); renderHome(); };
    });
  });
  document.querySelectorAll('.switch').forEach(sw => {
    sw.checked = !!S[sw.dataset.key];
    sw.onchange = () => { S[sw.dataset.key] = sw.checked; saveSettings(); };
  });

  const total = Object.values(BANK).reduce((a, b) => a + b.length, 0);
  $('#stats').textContent = `مجموع الأسئلة: ${toAr(total)}`;
  const reps = load(LS.reports, []);
  $('#reports-count').textContent = reps.length ? `(${toAr(reps.length)})` : '';
  $('#resume-box').classList.toggle('hidden', !load(LS.game, null));
}

/* ---------- بناء المسابقة ---------- */
function pickQuestions(n, exclude = new Set()) {
  let used = new Set(load(LS.used, []));
  const matches = q => S.cats.includes(q.cat) && (!S.difficulty || q.d === S.difficulty) && !exclude.has(q.id);
  const pools = {};
  S.cats.forEach(c => { pools[c] = shuffle((BANK[c] || []).filter(q => matches(q) && !used.has(q.id))); });
  let avail = Object.values(pools).reduce((a, p) => a + p.length, 0);
  if (avail < n) { // نفدت الأسئلة: نعيد تدوير المستعمل في الأقسام المختارة
    const ids = new Set(S.cats.flatMap(c => (BANK[c] || []).map(q => q.id)));
    used = new Set([...used].filter(id => !ids.has(id)));
    save(LS.used, [...used]);
    S.cats.forEach(c => { pools[c] = shuffle((BANK[c] || []).filter(matches)); });
    toast('تمت إعادة تدوير الأسئلة');
  }
  // توزيع متناوب بين الأقسام
  const out = []; const keys = shuffle([...S.cats]);
  while (out.length < n && keys.some(k => pools[k].length)) {
    for (const k of keys) { if (out.length >= n) break; if (pools[k].length) out.push(pools[k].pop()); }
  }
  return out;
}

let G = null; // حالة اللعبة

function startGame() {
  const names = S.teams.map((n, i) => n.trim() || `فريق ${toAr(i + 1)}`);
  const total = names.length * S.perTeam;
  const qs = pickQuestions(total);
  if (!qs.length) return toast('لا توجد أسئلة بهذه الإعدادات');
  G = {
    teams: names.map((n, i) => ({ name: n, color: TEAM_COLORS[i], score: 0, ok: 0, bad: 0, fifty: S.fifty })),
    qs: qs.map(q => q.id), idx: 0, opts: null, answered: false, settings: { ...S },
  };
  newOptions(); persist(); show('game'); renderQ();
}

const qById = id => { const c = id.split(':')[0]; return (BANK[c] || []).find(q => q.id === id); };
function newOptions() { const q = qById(G.qs[G.idx]); G.opts = shuffle([q.a, ...q.w]); G.gone = []; G.answered = false; G.pick = null; G.stolen = null; }
function persist() { save(LS.game, G); }
function markUsed(id) { const u = new Set(load(LS.used, [])); u.add(id); save(LS.used, [...u]); }

/* ---------- عرض السؤال ---------- */
let timerH = null;
function renderScore(bumpIdx) {
  const sb = $('#scoreboard'); sb.innerHTML = '';
  const cur = G.idx % G.teams.length;
  G.teams.forEach((t, i) => {
    const d = el('div', 'sc' + (i === cur ? ' cur' : '') + (i === bumpIdx ? ' bump' : ''),
      `<div class="n">${esc(t.name)}</div><div class="s">${toAr(t.score)}</div>${G.settings.fifty ? `<div class="f">${t.fifty ? '½ متاحة' : '&nbsp;'}</div>` : ''}`);
    d.style.setProperty('--c', t.color); d.style.borderTopColor = t.color;
    sb.appendChild(d);
  });
}

function renderQ() {
  const q = qById(G.qs[G.idx]);
  if (!q) { G.qs.splice(G.idx, 1); if (G.idx >= G.qs.length) return endGame(); newOptions(); return renderQ(); }
  const team = G.teams[G.idx % G.teams.length];
  $('#q-num').textContent = toAr(G.idx + 1); $('#q-total').textContent = toAr(G.qs.length);
  renderScore();
  $('#turn').innerHTML = `دور <span style="--c:${team.color}">${esc(team.name)}</span>`;
  const c = CATS[q.cat];
  $('#q-cat').textContent = c.icon + ' ' + c.name; $('#q-cat').style.borderColor = c.color;
  $('#q-diff').textContent = `${DIFF_NAME[q.d]} (${q.d === 1 ? 'نقطة' : q.d === 2 ? 'نقطتان' : '3 نقاط'})`;
  const qt = $('#q-text'); qt.textContent = q.q; qt.classList.toggle('poem', q.q.includes('\n'));

  const box = $('#options'); box.innerHTML = ''; box.classList.remove('locked');
  G.opts.forEach((o, i) => {
    const b = el('button', 'opt', `<span class="k">${LETTERS[i]}</span><span>${esc(o)}</span>`);
    if (G.gone.includes(i)) b.classList.add('gone');
    b.onclick = () => answer(i);
    box.appendChild(b);
  });

  $('#btn-fifty').classList.toggle('hidden', !G.settings.fifty);
  $('#btn-fifty').disabled = !team.fifty || G.answered;
  $('#btn-swap').disabled = G.answered;
  $('#tools').classList.toggle('hidden', G.answered);
  $('#after').classList.add('hidden');

  if (G.answered) { reveal(true); return; }
  startTimer();
}

function startTimer() {
  stopTimer();
  const T = G.settings.timer; const tw = $('#timer');
  if (!T) { tw.classList.add('hidden'); return; }
  tw.classList.remove('hidden', 'warn');
  let left = T; const bar = $('#timer-bar'); const num = $('#timer-num');
  const draw = () => { num.textContent = toAr(left); bar.style.strokeDashoffset = 100.5 * (1 - left / T); tw.classList.toggle('warn', left <= 5); };
  bar.style.transition = 'none'; draw(); void bar.offsetWidth; bar.style.transition = '';
  timerH = setInterval(() => {
    left--; draw();
    if (left <= 5 && left > 0) beep('tick');
    if (left <= 0) { stopTimer(); answer(-1); }
  }, 1000);
}
function stopTimer() { clearInterval(timerH); timerH = null; }

function answer(i) {
  if (G.answered) return;
  stopTimer();
  const q = qById(G.qs[G.idx]);
  const team = G.teams[G.idx % G.teams.length];
  G.answered = true; G.pick = i;
  const ok = i >= 0 && G.opts[i] === q.a;
  if (ok) { team.score += q.d; team.ok++; beep('ok'); } else { team.bad++; beep('bad'); }
  markUsed(q.id); persist();
  reveal(false, ok ? G.idx % G.teams.length : null);
}

function reveal(restoring, bumpIdx) {
  const q = qById(G.qs[G.idx]);
  const box = $('#options'); box.classList.add('locked');
  [...box.children].forEach((b, j) => {
    b.disabled = true;
    if (G.opts[j] === q.a) b.classList.add('ok');
    else if (j === G.pick) b.classList.add('bad');
  });
  const ok = G.pick >= 0 && G.opts[G.pick] === q.a;
  const v = $('#verdict');
  v.className = 'verdict ' + (ok ? 'ok' : 'bad');
  v.textContent = ok ? `صح! +${toAr(q.d)}` : (G.pick === -1 ? 'انتهى الوقت ⏱' : 'خطأ');
  const st = $('#steal');
  const canSteal = !ok && G.settings.steal && G.teams.length > 1 && G.stolen == null;
  st.classList.toggle('hidden', !canSteal);
  if (canSteal) {
    const sb = $('#steal-btns'); sb.innerHTML = '';
    const pts = Math.ceil(q.d / 2);
    G.teams.forEach((t, k) => {
      if (k === G.idx % G.teams.length) return;
      const b = el('button', 'btn sm', `${esc(t.name)} +${toAr(pts)}`); b.style.setProperty('--c', t.color);
      b.onclick = () => { t.score += pts; G.stolen = k; persist(); beep('ok'); st.classList.add('hidden'); renderScore(k); toast(`سرقة ناجحة لـ ${t.name}`); };
      sb.appendChild(b);
    });
  }
  $('#tools').classList.add('hidden');
  $('#after').classList.remove('hidden');
  $('#btn-next').textContent = G.idx + 1 >= G.qs.length ? 'النتيجة' : 'التالي';
  renderScore(restoring ? undefined : bumpIdx);
}

function next() {
  if (G.idx + 1 >= G.qs.length) return endGame();
  G.idx++; newOptions(); persist(); renderQ();
}

function useFifty() {
  const team = G.teams[G.idx % G.teams.length];
  if (!team.fifty || G.answered) return;
  const q = qById(G.qs[G.idx]);
  const wrong = G.opts.map((o, i) => o === q.a ? -1 : i).filter(i => i >= 0);
  G.gone = shuffle(wrong).slice(0, 2); team.fifty = false; persist();
  G.gone.forEach(i => $('#options').children[i].classList.add('gone'));
  $('#btn-fifty').disabled = true; renderScore();
}

function swapQ() {
  if (G.answered) return;
  const cur = G.qs[G.idx];
  const [rep] = pickQuestions(1, new Set(G.qs));
  if (!rep) return toast('لا يوجد بديل');
  markUsed(cur); G.qs[G.idx] = rep.id; newOptions(); persist(); renderQ(); toast('تم تبديل السؤال');
}

function reportQ() {
  const q = qById(G.qs[G.idx]); if (!q) return;
  modal(`<h3>الإبلاغ عن السؤال</h3><p>${esc(q.q)}</p><p><small>الإجابة المعتمدة: ${esc(q.a)}</small></p><textarea class="copy" id="rep-note" placeholder="ملاحظتك (اختياري): ما الخطأ؟"></textarea>`,
    [{ t: 'حفظ', primary: true, f: () => {
      const reps = load(LS.reports, []);
      reps.push({ cat: CATS[q.cat].name, q: q.q, a: q.a, note: ($('#rep-note') || {}).value || '', at: new Date().toISOString().slice(0, 10) });
      save(LS.reports, reps); toast('تم الحفظ');
    } }, { t: 'إلغاء' }]);
  setTimeout(() => { const n = $('#rep-note'); if (n) n.value = ''; }, 0);
}

/* ---------- النهاية ---------- */
function endGame() {
  stopTimer();
  const ranked = G.teams.map((t, i) => ({ ...t, i })).sort((a, b) => b.score - a.score);
  const top = ranked[0].score; const winners = ranked.filter(t => t.score === top);
  $('#winner').textContent = G.teams.length === 1 ? `نتيجتك: ${toAr(top)}` :
    winners.length > 1 ? 'تعادل! 🤝' : `🏆 الفائز: ${ranked[0].name}`;
  const rk = $('#ranking'); rk.innerHTML = '';
  const medals = ['🥇', '🥈', '🥉'];
  let place = 0, prev = null;
  ranked.forEach((t, k) => {
    if (t.score !== prev) place = k; prev = t.score;
    const d = el('div', 'rk' + (t.score === top ? ' first' : ''),
      `<div class="m">${medals[place] || toAr(place + 1)}</div><div class="nm">${esc(t.name)}<div class="dt">صح ${toAr(t.ok)} · خطأ ${toAr(t.bad)}</div></div><div class="pt" style="color:${t.color}">${toAr(t.score)}</div>`);
    rk.appendChild(d);
  });
  localStorage.removeItem(LS.game);
  show('result'); beep('win'); confetti();
}

function confetti() {
  const c = $('#confetti'); c.innerHTML = '';
  for (let i = 0; i < 80; i++) {
    const p = el('i'); p.style.left = Math.random() * 100 + '%';
    p.style.background = TEAM_COLORS[i % TEAM_COLORS.length];
    p.style.animationDuration = 2 + Math.random() * 2.5 + 's'; p.style.animationDelay = Math.random() * .8 + 's';
    c.appendChild(p);
  }
  setTimeout(() => c.innerHTML = '', 5500);
}

/* ---------- البلاغات ---------- */
function showReports() {
  const reps = load(LS.reports, []);
  if (!reps.length) return modal('<h3>الأسئلة المُبلَّغ عنها</h3><p>لا يوجد بلاغات. أثناء اللعب اضغط «⚑ فيه خطأ» على أي سؤال تشك فيه.</p>');
  const txt = reps.map((r, i) => `${i + 1}) [${r.cat}] ${r.q}\nالإجابة المعتمدة: ${r.a}${r.note ? '\nالملاحظة: ' + r.note : ''}`).join('\n\n');
  modal(`<h3>الأسئلة المُبلَّغ عنها (${toAr(reps.length)})</h3>` +
    reps.map(r => `<div class="rep">[${esc(r.cat)}] ${esc(r.q)}<br><small>المعتمد: ${esc(r.a)}${r.note ? ' — ' + esc(r.note) : ''}</small></div>`).join('') +
    `<p><small>انسخ القائمة وأرسلها لتصحيحها:</small></p><textarea class="copy" readonly>${esc(txt)}</textarea>`,
    [{ t: 'نسخ', primary: true, f: () => { navigator.clipboard?.writeText(txt).then(() => toast('تم النسخ')); } },
     { t: 'مسح الكل', f: () => modal('<p>مسح كل البلاغات؟</p>', [{ t: 'نعم امسح', primary: true, f: () => { save(LS.reports, []); renderHome(); } }, { t: 'لا' }]) },
     { t: 'إغلاق' }]);
}

/* ---------- الربط ---------- */
function bind() {
  document.querySelectorAll('.ver').forEach(e => e.textContent = VERSION);
  $('#btn-add-team').onclick = () => { if (S.teams.length < 8) { S.teams.push(`الفريق ${['الأول','الثاني','الثالث','الرابع','الخامس','السادس','السابع','الثامن'][S.teams.length]}`); saveSettings(); renderHome(); } };
  $('#btn-remove-team').onclick = () => { if (S.teams.length > 1) { S.teams.pop(); saveSettings(); renderHome(); } };
  $('#btn-start').onclick = () => { if (load(LS.game, null)) modal('<p>عندك مسابقة لم تكتمل. تبدأ واحدة جديدة؟</p>', [{ t: 'جديدة', primary: true, f: startGame }, { t: 'إلغاء' }]); else startGame(); };
  $('#btn-resume').onclick = () => { G = load(LS.game, null); if (!G) return renderHome(); show('game'); renderQ(); };
  $('#btn-discard').onclick = () => { localStorage.removeItem(LS.game); renderHome(); };
  $('#btn-next').onclick = next;
  $('#btn-fifty').onclick = useFifty;
  $('#btn-swap').onclick = swapQ;
  $('#btn-report').onclick = reportQ;
  $('#btn-again').onclick = () => { startGame(); };
  $('#btn-home').onclick = () => { show('home'); renderHome(); };
  $('#btn-reports').onclick = showReports;
  $('#btn-reset-used').onclick = () => modal('<p>تصفير سجل الأسئلة المستعملة؟ ستعود كل الأسئلة متاحة.</p>', [{ t: 'نعم', primary: true, f: () => { save(LS.used, []); renderHome(); toast('تم التصفير'); } }, { t: 'إلغاء' }]);
  $('#btn-menu').onclick = () => modal('<h3>القائمة</h3>', [
    { t: 'إنهاء وعرض النتيجة', primary: true, f: endGame },
    { t: 'الخروج للرئيسية (تحفظ المسابقة)', f: () => { stopTimer(); persist(); show('home'); renderHome(); } },
    { t: 'متابعة' , f: () => { if (!G.answered) startTimer(); } },
  ]);
  $('#btn-menu').addEventListener('click', stopTimer, true);
}

(async function init() {
  bind();
  await loadBank();
  renderHome();
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
})();
