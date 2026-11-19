/* تحدّي — مسابقة ثقافية للفرق (الواجهة). منطق اللعب الخالص في logic.js */
'use strict';
const VERSION = '1.4.0';
const T = window.TL;

// سجل الأقسام في data/cats.json. هذه نسخة احتياطية تُستعمل فقط إذا تعذّر تحميله.
const FALLBACK_CATS = [
  { key: 'religion', name: 'الدين', icon: '🕌', file: 'data/religion.txt', color: '#2fb47c', prefix: 'r' },
  { key: 'seerah', name: 'السيرة النبوية', icon: '🌙', file: 'data/seerah.txt', color: '#4cc9a0', prefix: 's' },
  { key: 'history', name: 'التاريخ الإسلامي', icon: '📜', file: 'data/history.txt', color: '#e0a13c', prefix: 'h' },
  { key: 'geography', name: 'الجغرافيا', icon: '🌍', file: 'data/geography.txt', color: '#3a9be0', prefix: 'g' },
  { key: 'poetry', name: 'الشعر', icon: '🪶', file: 'data/poetry.txt', color: '#b06ee0', prefix: 'p' },
  { key: 'arabic', name: 'اللغة العربية', icon: '✒️', file: 'data/arabic.txt', color: '#e07a5f', prefix: 'a' },
  { key: 'saudi', name: 'السعودية', icon: '🌴', file: 'data/saudi.txt', color: '#3fae5a', prefix: 'k' },
  { key: 'whoami', name: 'من أنا؟', icon: '🕵️', file: 'data/whoami.txt', color: '#e05a8a', prefix: 'w', clues: true },
];
let CATS = {}; let CAT_ORDER = [];
const TEAM_COLORS = ['#e0b44c', '#3a9be0', '#e05a8a', '#2fb47c', '#b06ee0', '#e07a3a', '#4cd0d0', '#c8c8c8'];
const DIFF_NAME = { 1: 'سهل', 2: 'متوسط', 3: 'صعب', 4: 'صعب جداً' };
const LETTERS = ['أ', 'ب', 'ج', 'د'];
const ORD = ['الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس', 'السابع', 'الثامن'];
const LS = { settings: 'tahaddi_settings', used: 'tahaddi_used', game: 'tahaddi_game', reports: 'tahaddi_reports', stats: 'tahaddi_stats' };

const $ = s => document.querySelector(s);
const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const shuffle = a => T.shuffle(a);
// الأرقام ذات النصف (1½) تُعزل باتجاه اليسار-لليمين، وإلا ظهرت في السطر العربي «½1»
const iso = x => '\u2066' + x + '\u2069';
const fmt = x => iso(T.fmtPts(x));
const plus = x => iso('+' + T.fmtPts(x));
const ptsWord = x => (x === Math.floor(x) || x === 0.5) && x >= 0 ? T.ptsWord(x) : `${fmt(x)} نقطة`;
const qName = s => `«${esc(s)}»`;

/* ---------- التخزين ---------- */
// القيم التالفة لا تعطّل التطبيق، وفشل الحفظ يُعلَن للمستخدم
const isObj = v => v && typeof v === 'object' && !Array.isArray(v);
function load(k, d) {
  try {
    const v = JSON.parse(localStorage.getItem(k));
    if (v == null) return d;
    if (Array.isArray(d) && !Array.isArray(v)) return d;
    if (isObj(d) && !isObj(v)) return d;
    return v;
  } catch { return d; }
}
let saveFailAt = 0, saveFailed = false;
function save(k, v) {
  try { localStorage.setItem(k, JSON.stringify(v)); return true; }
  catch (e) {
    saveFailed = true; console.error('تعذّر الحفظ', k, e);
    if (Date.now() - saveFailAt > 15000) {
      saveFailAt = Date.now();
      toast('تعذّر الحفظ في ذاكرة المتصفح (قد تكون ممتلئة أو في التصفح الخاص). صدّروا السجل احتياطاً.', 5000);
    }
    return false;
  }
}

/* ---------- البيانات ---------- */
let BANK = {}; let INDEX = { byId: new Map(), byLegacy: new Map() };
let USED = new Set(); let USED_KEYS = new Set(); let STATS = {};
let READY = false;
const DIAG = { registry: 'cats.json', failed: [], problems: [] };

async function loadRegistry() {
  let list = null;
  try {
    const r = await fetch('data/cats.json?v=' + VERSION, { cache: 'no-cache' });
    if (r.ok) { const j = await r.json(); if (Array.isArray(j.categories) && j.categories.length) list = j.categories; }
  } catch {}
  if (!list) { list = FALLBACK_CATS; DIAG.registry = 'النسخة الاحتياطية داخل app.js'; }
  CATS = {}; CAT_ORDER = [];
  list.forEach(c => { if (c && c.key && c.file) { CATS[c.key] = c; CAT_ORDER.push(c.key); } });
}

async function loadBank() {
  await loadRegistry();
  BANK = {}; DIAG.failed = []; DIAG.problems = [];
  await Promise.all(CAT_ORDER.map(async k => {
    const c = CATS[k];
    try {
      const r = await fetch(c.file + '?v=' + VERSION, { cache: 'no-cache' });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const res = T.parseBank(k, await r.text(), { clues: !!c.clues });
      BANK[k] = res.items; DIAG.problems.push(...res.problems);
    } catch (e) { BANK[k] = []; DIAG.failed.push(c.name); console.error('تعذّر تحميل', c.file, e); }
  }));
  INDEX = T.buildIndex(BANK);
  const errs = DIAG.problems.filter(p => p.level === 'error');
  if (DIAG.problems.length) console.warn(`تحدّي: في ملفات الأسئلة أسطر مرفوضة: ${errs.length}، وتنبيهات: ${DIAG.problems.length - errs.length}`, DIAG.problems);
  // ترحيل سجل المستعمل من المعرّفات القديمة إلى الثابتة
  const raw = load(LS.used, []).filter(x => typeof x === 'string');
  USED = T.migrateIds(raw, INDEX);
  if (USED.size !== raw.length || raw.some(id => !USED.has(id))) save(LS.used, [...USED]);
  USED_KEYS = T.usedKeySet(USED, INDEX);
  STATS = load(LS.stats, {});
  READY = Object.values(BANK).some(l => l.length);
}
const qById = id => INDEX.byId.get(id);
function markUsed(id) {
  if (USED.has(id)) return;
  USED.add(id); const q = qById(id); if (q) q.keys.forEach(k => USED_KEYS.add(k));
  save(LS.used, [...USED]);
}
function setUsed(ids) { USED = new Set(ids); USED_KEYS = T.usedKeySet(USED, INDEX); save(LS.used, [...USED]); }
// سياق الاختيار: المستعمل، ومفاتيحه، وما في المسابقة الحالية
function ctx(matchIds) {
  const ids = matchIds || [];
  return { used: USED, usedKeys: USED_KEYS, facts: T.factsOf(ids, INDEX), exclude: new Set(ids) };
}

/* ---------- الإعدادات ---------- */
const DEFAULTS = {
  teams: ['الفريق الأول', 'الفريق الثاني'],
  cats: ['religion', 'history', 'geography', 'poetry'], diffMode: 'mixed', level: 2, perTeam: 10, timer: 30, mode: 0,
  steal: true, fifty: true, sound: true, host: false,
};
const SAVED = load(LS.settings, {});
let S = Object.assign({}, DEFAULTS, SAVED);
if (SAVED.diffMode == null && SAVED.difficulty != null) { // إعدادات الإصدارات السابقة: difficulty 0 = مختلط
  S.diffMode = SAVED.difficulty ? 'fixed' : 'mixed'; if (SAVED.difficulty) S.level = SAVED.difficulty;
}
delete S.difficulty;
if (!['fixed', 'mixed', 'team'].includes(S.diffMode)) S.diffMode = 'mixed';
if (![1, 2, 3, 4].includes(S.level)) S.level = 2;
if (!Array.isArray(S.teams) || !S.teams.length) S.teams = [...DEFAULTS.teams];
S.teams = S.teams.slice(0, 8).map(x => String(x ?? ''));
if (!Array.isArray(S.cats)) S.cats = [...DEFAULTS.cats];
const saveSettings = () => save(LS.settings, S);
const levelFilter = () => S.diffMode === 'fixed' ? S.level : 0;

/* ---------- الصوت ---------- */
let actx;
function beep(type) {
  if (!S.sound) return;
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    if (actx.state === 'suspended') actx.resume(); // يعود الصوت بعد مكالمة أو خروج
    const seq = { ok: [[660, .09], [880, .16]], bad: [[220, .25]], tick: [[1000, .06]], clue: [[520, .08]], win: [[523, .12], [659, .12], [784, .12], [1046, .3]] }[type];
    let t = actx.currentTime;
    seq.forEach(([f, d]) => {
      const o = actx.createOscillator(), g = actx.createGain();
      o.type = type === 'bad' ? 'sawtooth' : type === 'tick' ? 'square' : 'sine'; o.frequency.value = f;
      g.gain.setValueAtTime(type === 'tick' ? .12 : .18, t); g.gain.exponentialRampToValueAtTime(.001, t + d);
      o.connect(g).connect(actx.destination); o.start(t); o.stop(t + d); t += d;
    });
  } catch {}
}

/* ---------- عام ---------- */
const screenIs = id => $('#screen-' + id).classList.contains('active');
function show(id) {
  document.querySelectorAll('.screen').forEach(s => s.classList.toggle('active', s.id === 'screen-' + id));
  document.body.classList.toggle('in-game', id === 'game');
  window.scrollTo(0, 0);
  wake(id === 'game');
}
function toast(msg, ms = 2200) { const t = $('#toast'); t.textContent = msg; t.classList.remove('hidden'); clearTimeout(t._h); t._h = setTimeout(() => t.classList.add('hidden'), ms); }
let modalClose = null;
// نافذة: actions = [{t, f, primary, danger, keep}] ، و opts.onClose يُستدعى إذا أُغلقت ولم تُفتح غيرها
function modal(html, actions, opts = {}) {
  $('#modal-body').innerHTML = html;
  const a = $('#modal-actions'); a.innerHTML = '';
  modalClose = opts.onClose || null;
  (actions || [{ t: 'إغلاق' }]).forEach(x => {
    const b = el('button', 'btn ' + (x.primary ? 'primary' : x.danger ? 'danger' : 'ghost'), x.t);
    b.onclick = () => {
      const oc = modalClose;
      if (!x.keep) $('#modal').classList.add('hidden');
      x.f && x.f();
      if (!x.keep && $('#modal').classList.contains('hidden') && modalClose === oc) { modalClose = null; oc && oc(); }
    };
    a.appendChild(b);
  });
  $('#modal').classList.remove('hidden');
  const first = $('#modal-body input, #modal-body textarea:not([readonly])');
  if (first && !opts.noFocus) setTimeout(() => first.focus(), 50);
}
const modalOpen = () => !$('#modal').classList.contains('hidden');
function confirmBox(html, yes, f, opts = {}) { modal(html, [{ t: yes, danger: true, f }, { t: 'إلغاء', primary: true }], opts); }

/* ---------- الرئيسية ---------- */
function renderHome() {
  const tl = $('#teams-list'); tl.innerHTML = '';
  S.teams.forEach((n, i) => {
    const row = el('div', 'team-input');
    const dot = el('span', 'dot'); dot.style.background = TEAM_COLORS[i];
    const inp = el('input'); inp.value = n; inp.maxLength = 24; inp.placeholder = 'اسم الفريق';
    inp.setAttribute('aria-label', `اسم الفريق ${ORD[i]}`);
    inp.oninput = () => { S.teams[i] = inp.value; saveSettings(); };
    row.append(dot, inp); tl.appendChild(row);
  });
  $('#btn-remove-team').disabled = S.teams.length <= 1;
  $('#btn-add-team').disabled = S.teams.length >= 8;

  const cl = $('#cats-list'); cl.innerHTML = '';
  const lvl = levelFilter();
  if (CAT_ORDER.length) { S.cats = S.cats.filter(c => CATS[c]); if (!S.cats.length) S.cats = CAT_ORDER.slice(0, 4); }
  CAT_ORDER.forEach(k => {
    const c = CATS[k];
    const all = (BANK[k] || []).filter(q => !lvl || q.d === lvl);
    const left = all.filter(q => T.isFresh(q, USED, USED_KEYS)).length;
    const d = el('button', 'cat' + (S.cats.includes(k) ? ' on' : ''),
      `<div class="ic">${c.icon}</div><div class="nm">${esc(c.name)}</div><div class="ct">بقي ${left} من ${all.length}${lvl ? ' · ' + DIFF_NAME[lvl] : ''}</div>`);
    d.setAttribute('aria-pressed', S.cats.includes(k));
    d.style.setProperty('--c', c.color);
    d.onclick = () => {
      if (S.cats.includes(k)) { if (S.cats.length > 1) S.cats = S.cats.filter(x => x !== k); else return toast('اختر قسماً واحداً على الأقل'); }
      else S.cats = CAT_ORDER.filter(x => x === k || S.cats.includes(x));
      saveSettings(); renderHome();
    };
    cl.appendChild(d);
  });

  document.querySelectorAll('.seg').forEach(seg => {
    const key = seg.dataset.key; const str = seg.dataset.type === 'str';
    seg.querySelectorAll('button').forEach(b => {
      b.classList.toggle('on', String(S[key]) === b.dataset.v);
      b.setAttribute('aria-pressed', String(S[key]) === b.dataset.v);
      b.onclick = () => { S[key] = str ? b.dataset.v : +b.dataset.v; saveSettings(); renderHome(); };
    });
  });
  document.querySelectorAll('.switch').forEach(sw => {
    sw.checked = !!S[sw.dataset.key];
    sw.onchange = () => { S[sw.dataset.key] = sw.checked; saveSettings(); renderHome(); };
  });
  $('#level-row').classList.toggle('hidden', S.diffMode !== 'fixed');
  $('#mode-hint').textContent = S.mode
    ? 'كل فريق في دوره يختار القسم والمستوى من اللوحة. عدد الخانات = عدد الفرق × الأسئلة لكل فريق، فلكل فريق عدد الأدوار نفسه.'
    : 'تأتي الأسئلة بالجولات: في كل جولة يأخذ كل فريق سؤالاً من القسم نفسه، والأقسام تتناوب.';
  $('#diff-hint').textContent = {
    fixed: 'كل الأسئلة من المستوى المختار.',
    mixed: S.mode ? 'في اللوحة كل المستويات.' : 'في كل جولة مستوى واحد لكل الفرق، ويتغير من جولة إلى أخرى.',
    team: S.mode ? 'في اللوحة يختار الفريق القسم والمستوى أصلاً.' : 'في بداية كل دور يختار الفريق مستوى سؤاله ونقاطه قبل أن يظهر السؤال، والقسم واحد لكل الفرق في الجولة.',
  }[S.diffMode];
  $('#host-hint').classList.toggle('hidden', !S.host);

  const total = Object.values(BANK).reduce((a, b) => a + b.length, 0);
  $('#stats').textContent = READY ? `مجموع الأسئلة: ${total} · المستعمل منها: ${[...USED].filter(id => INDEX.byId.has(id)).length}` : '';
  const errs = DIAG.problems.filter(p => p.level === 'error').length;
  $('#diag-badge').textContent = errs || DIAG.failed.length ? `⚠ ${errs + DIAG.failed.length}` : '';
  const reps = load(LS.reports, []);
  $('#reports-count').textContent = reps.length ? `(${reps.length})` : '';

  const st = $('#btn-start');
  st.disabled = !READY;
  st.textContent = READY ? 'ابدأ المسابقة' : (DIAG.failed.length ? 'تعذّر تحميل الأسئلة' : 'جارٍ تحميل الأسئلة…');
  $('#load-error').classList.toggle('hidden', !DIAG.failed.length);
  if (DIAG.failed.length) $('#load-error-text').textContent = `تعذّر تحميل: ${DIAG.failed.join('، ')}. تحقّق من الاتصال ثم أعد المحاولة.`;
  renderResumeBox();
}

function renderResumeBox() {
  const g = load(LS.game, null);
  const box = $('#resume-box');
  box.classList.toggle('hidden', !g || !Array.isArray(g.teams));
  if (!g || !Array.isArray(g.teams)) return;
  const prog = g.v === 2 ? (g.mode === 1
    ? `اللوحة: تمّ ${g.board.reduce((a, r) => a + r.cells.filter(c => c.used).length, 0)} من ${g.board.reduce((a, r) => a + r.cells.length, 0)}`
    : `الجولة ${((g.turns[g.ti] || {}).round || 0) + 1} من ${g.rounds}`) : '';
  $('#resume-info').innerHTML = `<div class="resume-teams">${g.teams.map(t => `<span style="--c:${t.color}"><b>${esc(t.name)}</b> ${fmt(t.score || 0)}</span>`).join('')}</div>${prog ? `<div class="hint">${prog}</div>` : ''}`;
}

/* ---------- حالة اللعبة ---------- */
let G = null;
const UNDO = [];
const curTeamIdx = () => G.mode === 1 ? G.turn : (G.turns[G.ti] || {}).team || 0;
const curTeam = () => G.teams[curTeamIdx()];
const curQ = () => G.qid ? qById(G.qid) : null;
const isHost = () => !!G.settings.host;
const optsHidden = () => isHost() && !G.optsShown;
const canSteal = () => G.settings.steal && G.teams.length > 1;
const ptsState = () => ({ shown: G.shown, optsShown: G.optsShown, host: isHost() });
const optText = (q, k) => k === 0 ? q.a : q.w[k - 1];
function frozen() { return G.timer ? T.tPause(G.timer, Date.now()) : null; }
function persist() { if (G) save(LS.game, { ...G, timer: frozen() }); }

function newTeams(names) {
  return names.map((n, i) => ({ name: n, color: TEAM_COLORS[i], score: 0, ok: 0, steals: 0, bad: 0, fifty: S.fifty, swap: true }));
}
function startGame() {
  if (!READY) return;
  const names = S.teams.map((n, i) => n.trim() || `الفريق ${ORD[i]}`);
  const n = names.length;
  const base = { v: 2, mode: S.mode, settings: { ...S }, teams: newTeams(names), seen: [], qid: null, phase: null, paused: false };
  if (S.mode === 1) {
    const levels = S.diffMode === 'fixed' ? [S.level] : T.LEVELS;
    const b = T.buildBoard({ bank: BANK, cats: S.cats, nTeams: n, perTeam: S.perTeam, levels, ctx: ctx() });
    if (!b.total) return exhaustedModal();
    const go = () => { G = { ...base, board: b.rows, turn: 0 }; G.seen = b.rows.flatMap(r => r.cells.map(c => c.id)); beginGame(); };
    if (b.total < b.wanted) return shortModal(b.total / n, go);
    go();
  } else {
    const d = T.dealRounds({ bank: BANK, cats: S.cats, nTeams: n, rounds: S.perTeam, diffMode: S.diffMode, level: S.level, ctx: ctx() });
    if (!d.rounds) return exhaustedModal();
    const go = () => { G = { ...base, turns: d.turns, ti: 0, rounds: d.rounds }; G.seen = d.turns.filter(t => t.id).map(t => t.id); beginTurn(); beginGame(); };
    if (d.rounds < S.perTeam) return shortModal(d.rounds, go);
    go();
  }
}
function beginGame() { UNDO.length = 0; persist(); show('game'); renderGame(); }
function shortModal(per, go) {
  const lvl = S.diffMode === 'fixed' ? ` من مستوى «${DIFF_NAME[S.level]}»` : '';
  modal(`<h3>الأسئلة المتاحة لا تكفي</h3><p>طلبتم ${T.qsWord(S.perTeam)} لكل فريق، والمتاح${lvl} في الأقسام المختارة يكفي ${T.qsWord(per)} لكل فريق فقط، حتى يتساوى عدد الأدوار.</p><p>تبدؤون بهذا العدد، أو تختارون أقساماً أو مستوى آخر؟</p>`,
    [{ t: `ابدؤوا بـ${T.qsWord(per)} لكل فريق`, primary: true, f: go }, { t: 'تغيير الإعدادات' }]);
}
function exhaustedModal() {
  const lvl = levelFilter();
  modal(`<h3>انتهت الأسئلة</h3><p>لعبتم كل الأسئلة المتاحة${lvl ? ` في مستوى «${DIFF_NAME[lvl]}»` : ''} في الأقسام المختارة، أو لم يبقَ منها ما يكفي جولة واحدة لكل الفرق. ولن يتكرر أي سؤال إلا إذا صفّرتم السجل.</p><p>اختاروا أقساماً أو مستوى آخر، أو صفّروا سجل هذه الأقسام.</p>`,
    [{ t: 'تصفير هذه الأقسام', danger: true, f: () => {
      const ids = new Set(S.cats.flatMap(c => (BANK[c] || []).filter(q => !lvl || q.d === lvl).map(q => q.id)));
      setUsed([...USED].filter(id => !ids.has(id))); renderHome(); toast('تم التصفير');
    } }, { t: 'إغلاق', primary: true }]);
}

// الطريقة المتتابعة: بداية الدور
function beginTurn() {
  const t = G.turns[G.ti];
  if (t.id == null) { G.qid = null; G.phase = 'choose'; G.timer = null; return; }
  openQuestion(t.id);
}
function openQuestion(id) {
  const q = qById(id);
  Object.assign(G, {
    qid: id, phase: 'q', order: shuffle([0, 1, 2, 3]), gone: [], pick: null, stealer: null, stealPick: null, res: null,
    shown: q && q.clues ? 1 : 0, optsShown: false, timedOut: false, statDone: false, paused: false,
    timer: G.settings.timer ? T.tNew(G.settings.timer) : null,
  });
  if (!G.seen.includes(id)) G.seen.push(id);
  markUsed(id); // السؤال الذي ظهر يُعدّ مستعملاً ولو انتهت المسابقة قبل إجابته
  UNDO.length = 0;
}
// تحويل مسابقة محفوظة من إصدار سابق
function convertOld(g) {
  const teams = g.teams.map(t => ({ name: t.name, color: t.color, score: t.score || 0, ok: t.ok || 0, steals: 0, bad: t.bad || 0, fifty: !!t.fifty, swap: true }));
  const old = g.settings || {};
  const settings = { ...DEFAULTS, ...old };
  if (old.diffMode == null) { settings.diffMode = old.difficulty ? 'fixed' : 'mixed'; settings.level = old.difficulty || 2; }
  const n = teams.length;
  const out = { v: 2, mode: g.mode || 0, settings, teams, seen: [], qid: null, phase: null, paused: false };
  if (out.mode === 1) {
    out.board = (g.board || []).map(r => ({ cat: r.cat, cells: r.cells.map(c => ({ id: c.id, d: c.d, used: !!c.used, by: c.by ?? null })) }));
    out.turn = g.turn || 0;
    out.seen = out.board.flatMap(r => r.cells.map(c => c.id));
    if (g.qid && g.answered) out.turn = (out.turn + 1) % n;
    else if (g.qid && g.cell) { out.cell = g.cell; openQuestionOn(out, g.qid); }
  } else {
    const qs = g.qs || [];
    out.turns = qs.map((id, i) => ({ round: Math.floor(i / n), team: i % n, cat: id.split(':')[0], d: (qById(id) || {}).d || 1, id }));
    out.rounds = Math.ceil(qs.length / n);
    out.seen = [...qs];
    out.ti = (g.idx || 0) + (g.answered ? 1 : 0);
    if (out.ti >= out.turns.length) return null;
    openQuestionOn(out, out.turns[out.ti].id);
  }
  return out;
}
function openQuestionOn(g, id) { const keep = G; G = g; openQuestion(id); G = keep; }

/* ---------- المؤقت ---------- */
let tickH = null, lastSec = null, autoPaused = false;
function timerRun() {
  if (!G || !G.timer || G.phase !== 'q' || G.timedOut || G.paused) return;
  G.timer = T.tStart(G.timer, Date.now());
  if (!tickH) tickH = setInterval(tick, 200);
  drawTimer();
}
function timerHalt() {
  clearInterval(tickH); tickH = null;
  if (G && G.timer && G.timer.since != null) G.timer = T.tPause(G.timer, Date.now());
}
function tick() {
  if (!G || !G.timer) return timerHalt();
  const now = Date.now(); const s = T.tSeconds(G.timer, now);
  if (s !== lastSec) { lastSec = s; drawTimer(); if (s <= 5 && s > 0) beep('tick'); persist(); }
  if (T.tExpired(G.timer, now)) { timerHalt(); onTimeout(); }
}
function drawTimer() {
  const tw = $('#timer');
  if (!G || !G.timer) { tw.classList.add('hidden'); return; }
  tw.classList.remove('hidden');
  const s = T.tSeconds(G.timer, Date.now()); const total = G.timer.total;
  $('#timer-num').textContent = s;
  $('#timer-bar').style.strokeDashoffset = 100.5 * (1 - s / total);
  tw.classList.toggle('warn', s <= 5);
  tw.setAttribute('aria-label', `بقي ${s} ثانية`);
}
function pauseGame() {
  if (!G || !G.timer || G.phase !== 'q' || G.timedOut) return;
  timerHalt(); G.paused = true; persist(); renderQ();
}
function resumeGame() {
  if (!G || G.phase !== 'q') return;
  G.paused = false; persist(); renderQ();
}
function togglePause() { if (!G) return; if (G.paused) resumeGame(); else pauseGame(); }
// إيقاف تلقائي أثناء النوافذ (القائمة وتعديل الفرق)، ويُستأنف عند إغلاقها
function autoPause() { if (tickH) { timerHalt(); autoPaused = true; persist(); } }
function autoResume() {
  if (!autoPaused) return; autoPaused = false;
  if (G && G.phase === 'q' && !G.paused && screenIs('game')) timerRun();
}
function onTimeout() {
  beep('bad');
  if (optsHidden()) { G.timedOut = true; persist(); return renderQ(); }
  answer(-1);
}

/* ---------- التراجع ---------- */
function pushUndo() {
  UNDO.push(JSON.stringify({ ...G, timer: frozen() }));
  if (UNDO.length > 15) UNDO.shift();
}
function undo() {
  if (!UNDO.length) return;
  timerHalt();
  G = JSON.parse(UNDO.pop());
  if (G.phase === 'q' && G.timer) G.paused = true; // يعود السؤال متوقفاً حتى يستأنفه المقدِّم
  persist(); renderGame(); toast('تم التراجع عن آخر إجراء');
}

/* ---------- الإجابة والسرقة ---------- */
function answer(i) {
  if (!G) return;
  const q = curQ(); if (!q) return;
  let bump;
  if (G.phase === 'q') {
    if (G.paused || (i >= 0 && G.gone.includes(i))) return;
    pushUndo(); timerHalt();
    const ti = curTeamIdx(); const team = G.teams[ti];
    G.pick = i; const ok = i >= 0 && G.order[i] === 0;
    if (ok) {
      const p = T.turnPoints(q, ptsState());
      team.score += p; team.ok++; G.res = { type: 'ok', team: ti, pts: p }; G.phase = 'done'; beep('ok'); bump = ti;
    } else {
      team.bad++; if (i >= 0) beep('bad');
      if (canSteal()) { G.phase = 'steal'; G.stealer = null; }
      else { G.res = { type: 'none' }; G.phase = 'done'; }
    }
  } else if (G.phase === 'steal' && G.stealer != null) {
    if (i < 0 || i === G.pick || G.gone.includes(i)) return;
    pushUndo();
    const k = G.stealer; const t = G.teams[k];
    G.stealPick = i;
    if (G.order[i] === 0) {
      const p = T.stealPoints(T.turnPoints(q, ptsState()));
      t.score += p; t.steals++; G.res = { type: 'steal', team: k, pts: p }; beep('ok'); bump = k;
      toast(`سرقة ناجحة: ${t.name} ${plus(p)}`);
    } else { G.res = { type: 'none', failed: k }; beep('bad'); }
    G.phase = 'done';
  } else return;
  persist(); renderQ(bump);
}
function chooseStealer(k) { if (G.phase !== 'steal') return; G.stealer = k; persist(); renderQ(); }
function noSteal() {
  if (G.phase !== 'steal') return;
  pushUndo(); G.res = { type: 'none' }; G.phase = 'done'; persist(); renderQ();
}
// وضع المضيف
function showOptions() { if (G.phase !== 'q' || !isHost() || G.optsShown) return; G.optsShown = true; persist(); renderQ(); }
function hostReveal() { if (G.phase !== 'q') return; timerHalt(); G.phase = 'judge'; persist(); renderQ(); }
function judge(kind, k) {
  if (G.phase !== 'judge') return;
  pushUndo();
  const q = curQ(); const ti = curTeamIdx(); const team = G.teams[ti];
  const p = T.turnPoints(q, ptsState()); let bump;
  if (kind === 'ok') { team.score += p; team.ok++; G.res = { type: 'ok', team: ti, pts: p }; bump = ti; beep('ok'); }
  else if (kind === 'steal') {
    team.bad++; const sp = T.stealPoints(p); G.teams[k].score += sp; G.teams[k].steals++;
    G.res = { type: 'steal', team: k, pts: sp }; bump = k; beep('ok');
  } else { team.bad++; G.res = { type: 'none' }; beep('bad'); }
  G.phase = 'done'; persist(); renderQ(bump);
}

function commitStats() {
  if (!G || !G.qid || G.statDone || G.phase !== 'done' || !G.res) return;
  const s = Array.isArray(STATS[G.qid]) ? STATS[G.qid] : [0, 0, 0];
  if (G.res.type === 'ok') s[0]++; else s[1]++;
  if (G.res.type === 'steal') s[2]++;
  STATS[G.qid] = s; G.statDone = true; save(LS.stats, STATS);
}

function next() {
  if (!G || G.phase !== 'done') return;
  commitStats(); UNDO.length = 0;
  if (G.mode === 1) {
    const [r, k] = G.cell; const cell = G.board[r].cells[k];
    cell.used = true; cell.by = G.res && G.res.type !== 'none' ? G.res.team : null;
    G.turn = (G.turn + 1) % G.teams.length; G.qid = null; G.phase = null; G.cell = null; G.timer = null;
    persist(); return renderGame();
  }
  if (G.ti + 1 >= G.turns.length) return endGame();
  G.ti++; beginTurn(); persist(); renderGame();
}

/* ---------- الوسائل ---------- */
function useFifty() {
  const team = curTeam();
  if (G.phase !== 'q' || !team.fifty || optsHidden() || G.paused) return;
  const wrong = G.order.map((k, i) => k === 0 ? -1 : i).filter(i => i >= 0);
  G.gone = shuffle(wrong).slice(0, 2); team.fifty = false; persist(); renderQ();
}
function moreClue() {
  const q = curQ(); if (!q || !q.clues || G.phase !== 'q' || G.shown >= q.clues.length || G.paused) return;
  G.shown++; persist(); beep('clue'); renderQ();
}
function swapQ() {
  if (G.phase !== 'q' || G.paused) return;
  const team = curTeam(); if (!team.swap) return toast('استعمل هذا الفريق تبديل السؤال من قبل');
  const q = curQ(); const c = ctx(G.seen);
  const [rep] = T.takeN(T.freshPool(BANK, q.cat, q.d, c), 1, c.facts);
  if (!rep) return toast('لا يوجد سؤال بديل من القسم والمستوى نفسيهما');
  timerHalt(); team.swap = false;
  if (G.mode === 1) { const [r, k] = G.cell; G.board[r].cells[k].id = rep.id; } else G.turns[G.ti].id = rep.id;
  openQuestion(rep.id); persist(); renderQ(); toast('تم تبديل السؤال');
}

/* ---------- اختيار المستوى (يختاره الفريق) ---------- */
function levelCounts(cat) { const c = ctx(G.seen); return T.LEVELS.map(d => T.countFresh(BANK, cat, d, c)); }
function renderChooser() {
  timerHalt(); drawTimer();
  $('#board').classList.add('hidden'); $('#qview').classList.add('hidden');
  const box = $('#chooser'); box.classList.remove('hidden');
  const t = G.turns[G.ti]; const team = curTeam();
  progressText(); renderScore();
  $('#turn').innerHTML = `دور <span style="--c:${team.color}">${esc(team.name)}</span>`;
  setTurnColor(team.color);
  let cat = t.cat; let counts = levelCounts(cat);
  if (!counts.some(Boolean)) { // نفد القسم: نأخذ قسماً آخر فيه أسئلة
    const alt = G.settings.cats.find(c => levelCounts(c).some(Boolean));
    if (alt) { t.cat = cat = alt; counts = levelCounts(alt); persist(); }
  }
  const c = CATS[cat];
  box.innerHTML = '';
  box.appendChild(el('div', 'choose-head', `<span class="badge" style="border-color:${c.color}">${c.icon} ${esc(c.name)}</span><div class="choose-title">اختاروا مستوى سؤالكم</div>`));
  const grid = el('div', 'levels');
  T.LEVELS.forEach((d, i) => {
    const extra = c.clues ? ' + التلميحات' : '';
    const b = el('button', `lvl d${d}`, `<span class="ln">${DIFF_NAME[d]}</span><span class="lp">${ptsWord(d)}${extra}</span><span class="lc">${counts[i] ? `بقي ${counts[i]}` : 'نفدت'}</span>`);
    b.disabled = !counts[i];
    b.onclick = () => pickLevel(d);
    grid.appendChild(b);
  });
  box.appendChild(grid);
  if (!counts.some(Boolean)) {
    box.appendChild(el('p', 'hint', 'انتهت الأسئلة المتاحة في كل الأقسام المختارة.'));
    const e = el('button', 'btn primary', 'عرض النتيجة'); e.onclick = endGame; box.appendChild(e);
  }
  updateTopbar();
}
function pickLevel(d) {
  const t = G.turns[G.ti]; const c = ctx(G.seen);
  const [q] = T.takeN(T.freshPool(BANK, t.cat, d, c), 1, c.facts);
  if (!q) { toast('نفدت أسئلة هذا المستوى'); return renderChooser(); }
  t.d = d; t.id = q.id; openQuestion(q.id); persist(); renderGame();
}

/* ---------- لوحة الأسئلة ---------- */
function renderBoard() {
  timerHalt(); G.timer = null; drawTimer();
  $('#board').classList.remove('hidden'); $('#qview').classList.add('hidden'); $('#chooser').classList.add('hidden');
  renderScore();
  const left = G.board.reduce((a, r) => a + r.cells.filter(c => !c.used).length, 0);
  progressText();
  if (!left) return endGame();
  const t = curTeam();
  $('#turn').innerHTML = `دور <span style="--c:${t.color}">${esc(t.name)}</span> — اختاروا سؤالاً`;
  setTurnColor(t.color);
  const b = $('#board'); b.innerHTML = '';
  G.board.forEach((row, r) => {
    const c = CATS[row.cat] || { icon: '', name: row.cat, color: '#888' };
    const div = el('div', 'brow', `<div class="bt">${c.icon} ${esc(c.name)}</div>`);
    div.style.setProperty('--c', c.color);
    const cells = el('div', 'cells');
    row.cells.forEach((cell, k) => {
      const btn = el('button', `cell d${cell.d}${cell.used ? ' used ' + (cell.by != null ? 'ok' : 'bad') : ''}`, String(cell.d));
      if (cell.used && cell.by != null) btn.style.setProperty('--tc', G.teams[cell.by].color);
      btn.setAttribute('aria-label', `${c.name}، ${DIFF_NAME[cell.d]}` + (cell.used ? (cell.by != null ? `، كسبه ${G.teams[cell.by].name}` : '، لم يُجب') : ''));
      if (cell.used) btn.disabled = true; else btn.onclick = () => openCell(r, k);
      cells.appendChild(btn);
    });
    div.appendChild(cells); b.appendChild(div);
  });
  b.appendChild(el('div', 'board-legend', '1 سهل · 2 متوسط · 3 صعب · 4 صعب جداً · الخانة الملونة كسبها الفريق صاحب اللون'));
  updateTopbar();
}
function openCell(r, k) {
  const cell = G.board[r].cells[k];
  if (!qById(cell.id)) { cell.used = true; persist(); return renderBoard(); }
  G.cell = [r, k]; openQuestion(cell.id); persist(); renderQ();
}

/* ---------- العرض ---------- */
function progressText() {
  const p = $('.progress');
  if (G.mode === 1) {
    const all = G.board.reduce((a, r) => a + r.cells.length, 0);
    const done = G.board.reduce((a, r) => a + r.cells.filter(c => c.used).length, 0);
    p.textContent = G.qid ? `سؤال ${done + 1} من ${all}` : `تمّ ${done} من ${all}`;
  } else {
    const t = G.turns[G.ti] || {};
    p.textContent = `الجولة ${(t.round || 0) + 1} من ${G.rounds}`;
  }
}
function setTurnColor(c) { document.documentElement.style.setProperty('--turn', c); }
function renderScore(bumpIdx) {
  const sb = $('#scoreboard'); sb.innerHTML = '';
  sb.dataset.n = G.teams.length;
  const cur = curTeamIdx();
  G.teams.forEach((t, i) => {
    const life = [];
    if (G.settings.fifty) life.push(`<span class="life${t.fifty ? '' : ' off'}" title="حذف إجابتين">✂</span>`);
    life.push(`<span class="life${t.swap ? '' : ' off'}" title="تبديل السؤال">⇄</span>`);
    const d = el('button', 'sc' + (i === cur ? ' cur' : '') + (i === bumpIdx ? ' bump' : ''),
      `<div class="n">${esc(t.name)}</div><div class="s">${fmt(t.score)}</div><div class="f">${life.join('')}</div>`);
    d.style.setProperty('--c', t.color);
    d.setAttribute('aria-label', `${t.name}: ${fmt(t.score)}. اضغط لتعديل الاسم أو النقاط`);
    d.onclick = () => teamModal(i);
    sb.appendChild(d);
  });
}
function renderGame(bump) {
  if (!G) return;
  if (G.mode === 1 && !G.qid) return renderBoard();
  if (G.mode === 0 && G.phase === 'choose') return renderChooser();
  renderQ(bump);
}

function renderQ(bump) {
  const q = curQ();
  if (!q) return skipMissing();
  $('#board').classList.add('hidden'); $('#chooser').classList.add('hidden'); $('#qview').classList.remove('hidden');
  const ti = curTeamIdx(); const team = G.teams[ti]; const ph = G.phase;
  progressText(); renderScore(bump);
  const stealT = ph === 'steal' && G.stealer != null ? G.teams[G.stealer] : null;
  const tt = stealT || team;
  $('#turn').innerHTML = stealT ? `محاولة سرقة: <span style="--c:${stealT.color}">${esc(stealT.name)}</span>` : `دور <span style="--c:${team.color}">${esc(team.name)}</span>`;
  setTurnColor(tt.color);
  const c = CATS[q.cat];
  $('#q-cat').textContent = c.icon + ' ' + c.name; $('#q-cat').style.borderColor = c.color;
  const p = T.turnPoints(q, ptsState());
  $('#q-diff').textContent = `${DIFF_NAME[q.d]} · ${q.clues && ph === 'q' ? 'الآن ' : ''}${ptsWord(p)}`;

  // السؤال أو التلميحات
  const qt = $('#q-text'); const cl = $('#clues');
  const open = ph === 'judge' || ph === 'done';
  if (q.clues) {
    qt.classList.add('hidden'); cl.innerHTML = ''; cl.classList.remove('hidden');
    q.clues.forEach((t, i) => {
      if (i < G.shown || open) cl.appendChild(el('div', 'clue' + (i >= G.shown ? ' late' : ''), `<b>${i + 1}</b>${esc(t)}`));
      else cl.appendChild(el('div', 'clue locked', `<b>${i + 1}</b>تلميح مخفي`));
    });
    cl.classList.toggle('compact', open || ph === 'steal');
  } else {
    cl.classList.add('hidden'); qt.classList.remove('hidden');
    qt.textContent = q.q; qt.classList.toggle('poem', q.q.includes('\n'));
  }

  // الخيارات
  const box = $('#options'); box.innerHTML = '';
  const hidden = optsHidden();
  box.classList.toggle('locked', open || (ph === 'steal' && G.stealer == null));
  if (hidden) {
    if (ph === 'q') box.appendChild(el('div', 'opts-hidden', G.timedOut ? 'انتهى الوقت. لغير الفريق أن يقول جوابه الآن قبل الكشف.' : 'الخيارات مخفية: يجيب الفريق شفهياً، ثم يكشف المقدِّم الإجابة.'));
  } else {
    G.order.forEach((k, i) => {
      const b = el('button', 'opt', `<span class="k">${LETTERS[i]}</span><span>${esc(optText(q, k))}</span>`);
      if (G.gone.includes(i)) b.classList.add('gone');
      if (ph === 'steal' && i === G.pick) { b.classList.add('bad'); b.disabled = true; }
      if (open) {
        b.disabled = true;
        if (k === 0) b.classList.add('ok');
        else if (i === G.pick || i === G.stealPick) b.classList.add('bad');
      }
      if (ph === 'steal' && G.stealer == null) b.disabled = true;
      b.onclick = () => answer(i);
      box.appendChild(b);
    });
  }
  const al = $('#answer-line');
  al.classList.toggle('hidden', !open);
  al.innerHTML = open ? `الإجابة: <b>${esc(q.a)}</b>` : '';

  // الأدوات
  const inQ = ph === 'q';
  $('#tools').classList.toggle('hidden', !inQ);
  $('#btn-fifty').classList.toggle('hidden', !G.settings.fifty || hidden || G.timedOut);
  $('#btn-fifty').disabled = !team.fifty || G.gone.length > 0;
  $('#btn-clue').classList.toggle('hidden', !(q.clues && G.shown < q.clues.length) || G.timedOut);
  $('#btn-swap').classList.toggle('hidden', G.timedOut);
  $('#btn-swap').disabled = !team.swap;
  $('#btn-showopts').classList.toggle('hidden', !hidden || G.timedOut);
  $('#btn-showopts').textContent = `أظهر الخيارات (بنصف النقاط: ${fmt(T.halve(T.basePoints(q, G.shown)))})`;
  $('#btn-reveal').classList.toggle('hidden', !isHost());

  // لوحة ما بعد الإجابة
  const after = $('#after'); after.classList.toggle('hidden', inQ);
  const v = $('#verdict'); const st = $('#steal'); const jd = $('#judge');
  st.classList.add('hidden'); jd.classList.add('hidden'); v.classList.remove('hidden');
  $('#after-row').classList.toggle('hidden', ph !== 'done');
  if (ph === 'steal') {
    v.className = 'verdict bad'; v.textContent = G.pick === -1 ? 'انتهى الوقت ⏱' : `خطأ من ${team.name}`;
    st.classList.remove('hidden');
    const sp = T.stealPoints(p); const sb = $('#steal-btns'); sb.innerHTML = '';
    if (G.stealer == null) {
      $('#steal-title').textContent = `هل يحاول فريق آخر قبل كشف الإجابة؟ للسرقة ${plus(sp)}`;
      G.teams.forEach((t, k) => {
        if (k === ti) return;
        const b = el('button', 'btn sm team-btn', esc(t.name)); b.style.setProperty('--c', t.color);
        b.onclick = () => chooseStealer(k); sb.appendChild(b);
      });
      const nb = el('button', 'btn ghost sm', 'لا أحد — اكشف الإجابة'); nb.onclick = noSteal; sb.appendChild(nb);
    } else {
      $('#steal-title').textContent = `${G.teams[G.stealer].name}: اختاروا جوابكم من الخيارات (${plus(sp)})`;
      const cb = el('button', 'btn ghost sm', 'تغيير الفريق'); cb.onclick = () => { G.stealer = null; persist(); renderQ(); }; sb.appendChild(cb);
      const nb = el('button', 'btn ghost sm', 'لا أحد — اكشف الإجابة'); nb.onclick = noSteal; sb.appendChild(nb);
    }
  } else if (ph === 'judge') {
    v.classList.add('hidden'); jd.classList.remove('hidden');
    const jb = $('#judge-btns'); jb.innerHTML = '';
    if (!G.timedOut) { const b = el('button', 'btn ok', `✓ أصاب ${esc(team.name)} ${plus(p)}`); b.onclick = () => judge('ok'); jb.appendChild(b); }
    if (canSteal()) {
      const sp = T.stealPoints(p);
      G.teams.forEach((t, k) => {
        if (k === ti) return;
        const b = el('button', 'btn sm team-btn', `سرقة: ${esc(t.name)} ${plus(sp)}`); b.style.setProperty('--c', t.color);
        b.onclick = () => judge('steal', k); jb.appendChild(b);
      });
    }
    const nb = el('button', 'btn bad', '✗ لم يُصب أحد'); nb.onclick = () => judge('none'); jb.appendChild(nb);
    $('#judge-title').textContent = canSteal() ? 'من أصاب؟ (السرقة لمن قال جوابه قبل الكشف)' : 'هل أصاب الفريق؟';
  } else if (ph === 'done') {
    const r = G.res || { type: 'none' };
    v.className = 'verdict ' + (r.type === 'none' ? 'bad' : 'ok');
    v.textContent = r.type === 'ok' ? `صح! ${G.teams[r.team].name} ${plus(r.pts)}`
      : r.type === 'steal' ? `سرقة ناجحة: ${G.teams[r.team].name} ${plus(r.pts)}`
      : G.pick === -1 && !isHost() ? 'انتهى الوقت ⏱' : canSteal() ? 'لم يُصب أحد' : 'خطأ';
    const last = G.mode === 1 ? G.board.reduce((a, row) => a + row.cells.filter(x => !x.used).length, 0) <= 1 : G.ti + 1 >= G.turns.length;
    $('#btn-next').textContent = last ? 'النتيجة' : (G.mode === 1 ? 'إلى اللوحة' : 'التالي');
  }

  // الإيقاف والمؤقت
  const canPause = inQ && G.timer && !G.timedOut;
  $('#qcard').classList.toggle('paused', !!(canPause && G.paused));
  $('#btn-pause').classList.toggle('hidden', !canPause);
  $('#btn-pause').textContent = G.paused ? '▶' : '⏸';
  $('#btn-pause').setAttribute('aria-label', G.paused ? 'متابعة' : 'إيقاف مؤقت');
  drawTimer(); if (!inQ) $('#timer').classList.add('hidden');
  updateTopbar();
  if (inQ && !G.paused && !G.timedOut) timerRun(); else if (tickH) timerHalt();
}

function skipMissing() { // سؤال حُذف من الملفات بعد بدء المسابقة
  if (G.mode === 1) { const [r, k] = G.cell || [0, 0]; if (G.board[r]) G.board[r].cells[k].used = true; G.qid = null; G.cell = null; persist(); return renderBoard(); }
  const t = G.turns[G.ti]; const c = ctx(G.seen);
  const [rep] = t.d ? T.takeN(T.freshPool(BANK, t.cat, t.d, c), 1, c.facts) : [];
  if (rep) { t.id = rep.id; openQuestion(rep.id); persist(); return renderQ(); }
  if (t.d == null || G.settings.diffMode === 'team') { t.id = null; t.d = null; G.phase = 'choose'; G.qid = null; persist(); return renderChooser(); }
  G.turns.splice(G.ti, 1);
  if (G.ti >= G.turns.length) return endGame();
  beginTurn(); persist(); renderGame();
}

function updateTopbar() { $('#btn-undo').disabled = !UNDO.length; }

/* ---------- الفرق أثناء اللعب ---------- */
function teamModal(i) {
  const t = G.teams[i]; let delta = 0;
  autoPause();
  modal(`<h3>تعديل الفريق</h3><label class="fld">الاسم<input id="tm-name" maxlength="24" value="${esc(t.name)}"></label>
    <div class="adj-title">تعديل النقاط يدوياً</div>
    <div class="adj"><button class="btn ghost" data-d="-1">${fmt(-1)}</button><button class="btn ghost" data-d="-0.5">${fmt(-0.5)}</button><span id="tm-score">${fmt(t.score)}</span><button class="btn ghost" data-d="0.5">${plus(0.5)}</button><button class="btn ghost" data-d="1">${plus(1)}</button></div>`,
    [{ t: 'حفظ', primary: true, f: () => {
      const name = ($('#tm-name').value || '').trim() || t.name;
      if (delta || name !== t.name) {
        pushUndo();
        t.name = name; t.score += delta;
        if (S.teams[i] != null) { S.teams[i] = name; saveSettings(); }
        persist(); renderGame(delta ? i : undefined);
        if (delta) toast(`${name}: ${delta > 0 ? plus(delta) : fmt(delta)}`);
      }
    } }, { t: 'إلغاء' }], { onClose: autoResume, noFocus: true });
  document.querySelectorAll('#modal-body .adj button').forEach(b => b.onclick = () => {
    delta += +b.dataset.d; $('#tm-score').textContent = fmt(t.score + delta);
  });
}

function menu() {
  autoPause();
  const fs = fullscreenSupported();
  const acts = [{ t: 'متابعة', primary: true }];
  if (fs) acts.push({ t: document.fullscreenElement || document.webkitFullscreenElement ? 'الخروج من ملء الشاشة' : 'ملء الشاشة', f: toggleFullscreen });
  acts.push({ t: 'الخروج للرئيسية (تُحفظ المسابقة)', f: leaveToHome });
  acts.push({ t: 'إنهاء المسابقة…', danger: true, f: () => confirmBox('<h3>إنهاء المسابقة؟</h3><p>تنتهي المسابقة الآن وتظهر النتيجة، ولا يمكن متابعتها بعد ذلك.</p>', 'نعم، أنهِها', endGame, { onClose: autoResume }) });
  modal(`<h3>القائمة</h3><p class="hint left">للتعديل على اسم فريق أو نقاطه اضغط بطاقته في لوحة النقاط. الإصدار ${VERSION}</p>`, acts, { onClose: autoResume });
}
function leaveToHome() { autoPaused = false; timerHalt(); if (G && G.phase === 'q' && G.timer) G.paused = true; persist(); show('home'); renderHome(); }

/* ---------- البلاغات ---------- */
function qDisplay(q) { return q.clues ? q.clues.map((c, i) => `${i + 1}) ${c}`).join('\n') : q.q; }
function reportQ() {
  const q = curQ(); if (!q) return;
  const reps = load(LS.reports, []);
  const prev = reps.find(r => r.id === q.id);
  modal(`<h3>الإبلاغ عن السؤال</h3><p class="rep-q">${esc(qDisplay(q))}</p><p><small>الإجابة المعتمدة: ${esc(q.a)} · المعرّف: ${esc(q.id.split(':')[1] || q.id)}</small></p>${prev ? '<p class="hint left">أُبلغ عن هذا السؤال من قبل، وستُحدَّث ملاحظته.</p>' : ''}<textarea class="copy" id="rep-note" placeholder="ملاحظتك (اختياري): ما الخطأ؟">${prev ? esc(prev.note || '') : ''}</textarea>`,
    [{ t: 'حفظ', primary: true, f: () => {
      const note = ($('#rep-note') || {}).value || '';
      const r = { id: q.id, cat: CATS[q.cat].name, q: qDisplay(q), a: q.a, note, at: new Date().toISOString().slice(0, 10) };
      const i = reps.findIndex(x => x.id === q.id);
      if (i >= 0) reps[i] = r; else reps.push(r);
      if (save(LS.reports, reps)) toast(i >= 0 ? 'حُدِّث البلاغ' : 'حُفظ البلاغ');
    } }, { t: 'إلغاء' }], { noFocus: true });
}
function showReports() {
  const reps = load(LS.reports, []);
  if (!reps.length) return modal('<h3>الأسئلة المُبلَّغ عنها</h3><p>لا يوجد بلاغات. أثناء اللعب اضغط «⚑ فيه خطأ» على أي سؤال تشك فيه.</p>');
  const sid = r => r.id ? ` (${r.id.split(':')[1] || r.id})` : '';
  const txt = reps.map((r, i) => `${i + 1}) [${r.cat}]${sid(r)} ${r.q}\nالإجابة المعتمدة: ${r.a}${r.note ? '\nالملاحظة: ' + r.note : ''}`).join('\n\n');
  modal(`<h3>الأسئلة المُبلَّغ عنها (${reps.length})</h3>` +
    reps.map(r => `<div class="rep">[${esc(r.cat)}]${esc(sid(r))} <span class="rep-q">${esc(r.q)}</span><br><small>المعتمد: ${esc(r.a)}${r.note ? ' — ' + esc(r.note) : ''}</small></div>`).join('') +
    `<p><small>انسخ القائمة وأرسلها لتصحيحها:</small></p><textarea class="copy" readonly>${esc(txt)}</textarea>`,
    [{ t: 'نسخ', primary: true, f: () => copyText(txt) },
     { t: 'مسح الكل', danger: true, f: () => confirmBox('<p>مسح كل البلاغات نهائياً؟</p>', 'نعم، امسحها', () => { save(LS.reports, []); renderHome(); }) },
     { t: 'إغلاق' }], { noFocus: true });
}
function copyText(txt) {
  if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(txt).then(() => toast('تم النسخ'), () => toast('تعذّر النسخ تلقائياً: حدّد النص وانسخه'));
  else toast('حدّد النص وانسخه');
}

/* ---------- نقل السجل بين الأجهزة ---------- */
function historyObj() {
  return { app: 'tahaddi', format: 1, version: VERSION, at: new Date().toISOString(), used: [...USED], reports: load(LS.reports, []), stats: STATS };
}
const b64 = u8 => { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000)); return btoa(s); };
const unb64 = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
async function encodeCode(obj) {
  const bytes = new TextEncoder().encode(JSON.stringify(obj));
  if (window.CompressionStream) {
    try {
      const st = new Blob([bytes]).stream().pipeThrough(new CompressionStream('deflate'));
      return 'TAHADDI1Z:' + b64(new Uint8Array(await new Response(st).arrayBuffer()));
    } catch {}
  }
  return 'TAHADDI1:' + b64(bytes);
}
async function decodeAny(text) {
  text = String(text).trim();
  if (text.startsWith('{')) return JSON.parse(text);
  const m = text.replace(/\s+/g, '').match(/^TAHADDI1(Z?):(.+)$/);
  if (!m) throw new Error('ليس رمز سجل من «تحدّي»');
  let bytes = unb64(m[2]);
  if (m[1]) {
    if (!window.DecompressionStream) throw new Error('هذا المتصفح لا يفك الرمز المضغوط؛ استعملوا الملف بدلاً منه');
    const st = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate'));
    bytes = new Uint8Array(await new Response(st).arrayBuffer());
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}
function importHistory(obj) {
  if (!obj || obj.app !== 'tahaddi' || !Array.isArray(obj.used)) throw new Error('الملف ليس سجلاً من «تحدّي»');
  const inc = { used: [...T.migrateIds(obj.used.filter(x => typeof x === 'string'), INDEX)], reports: Array.isArray(obj.reports) ? obj.reports : [], stats: isObj(obj.stats) ? obj.stats : {} };
  const m = T.mergeHistory({ used: [...USED], reports: load(LS.reports, []), stats: STATS }, inc);
  setUsed(m.used); save(LS.reports, m.reports); STATS = m.stats; save(LS.stats, STATS);
  renderHome();
  modal(`<h3>تم الاستيراد</h3><p>أُضيف ${T.qsWord(m.addedUsed)} إلى المستعمل، و${m.addedReports} بلاغاً جديداً، ودُمج إحصاء الأسئلة. لم يُحذف شيء من سجل هذا الجهاز.</p>`);
}
function historyModal() {
  const reps = load(LS.reports, []);
  modal(`<h3>نقل السجل بين الأجهزة</h3><p>في السجل ${T.qsWord(USED.size)} مستعملاً، و${reps.length} بلاغاً، وإحصاء الصواب والخطأ لـ${T.qsWord(Object.keys(STATS).length)}.</p><p class="hint left">انقلوه إلى الجوال الآخر أو الآيباد أو التطبيق حتى لا تتكرر عليكم الأسئلة. الاستيراد يدمج السجلين ولا يحذف شيئاً. وصدّروه احتياطاً من حين لآخر، فبعض المتصفحات تمسح بيانات المواقع التي لا تُفتح مدة.</p>`,
    [{ t: 'تنزيل ملف', primary: true, f: () => {
      const blob = new Blob([JSON.stringify(historyObj(), null, 1)], { type: 'application/json' });
      const a = el('a'); a.href = URL.createObjectURL(blob); a.download = `tahaddi-history-${new Date().toISOString().slice(0, 10)}.json`;
      document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
      toast('نُزّل ملف السجل');
    } },
    { t: 'نسخ رمز', f: async () => {
      const code = await encodeCode(historyObj());
      modal(`<h3>رمز السجل</h3><p class="hint left">انسخ الرمز كله وأرسله إلى الجهاز الآخر، ثم الصقه هناك في «لصق رمز».</p><textarea class="copy code" readonly>${esc(code)}</textarea>`,
        [{ t: 'نسخ', primary: true, keep: true, f: () => copyText(code) }, { t: 'إغلاق' }], { noFocus: true });
    } },
    { t: 'استيراد ملف', f: () => $('#import-file').click() },
    { t: 'لصق رمز', f: () => {
      modal('<h3>لصق رمز السجل</h3><textarea class="copy code" id="imp-code" placeholder="الصق الرمز أو محتوى الملف هنا"></textarea>',
        [{ t: 'استيراد', primary: true, f: async () => {
          try { importHistory(await decodeAny($('#imp-code').value)); } catch (e) { modal(`<h3>تعذّر الاستيراد</h3><p>${esc(e.message || e)}</p>`); }
        } }, { t: 'إلغاء' }]);
    } },
    { t: 'إغلاق' }], { noFocus: true });
}

/* ---------- التشخيص ---------- */
async function diagModal() {
  let persisted = 'غير معروف';
  try { if (navigator.storage && navigator.storage.persisted) persisted = (await navigator.storage.persisted()) ? 'نعم' : 'لا'; } catch {}
  const rows = CAT_ORDER.map(k => {
    const pr = DIAG.problems.filter(p => p.cat === k);
    return `<tr><td>${esc(CATS[k].name)}</td><td>${(BANK[k] || []).length}</td><td>${pr.filter(p => p.level === 'error').length}</td><td>${pr.filter(p => p.level === 'warn').length}</td></tr>`;
  }).join('');
  const list = DIAG.problems.slice().sort((a, b) => (a.level === b.level ? 0 : a.level === 'error' ? -1 : 1)).slice(0, 60)
    .map(p => `<div class="rep"><b class="${p.level === 'error' ? 'bad-t' : 'warn-t'}">${p.level === 'error' ? 'مرفوض' : 'تنبيه'}</b> ${esc(CATS[p.cat].name)}: السطر ${p.line} — ${esc(p.msg)}<br><small>${esc(p.text)}</small></div>`).join('');
  modal(`<h3>التشخيص</h3><p>الإصدار ${VERSION} · الأقسام من: ${esc(DIAG.registry)}</p>
    ${DIAG.failed.length ? `<p class="bad-t">تعذّر تحميل: ${esc(DIAG.failed.join('، '))}</p>` : ''}
    <table class="diag"><tr><th>القسم</th><th>الأسئلة</th><th>مرفوض</th><th>تنبيهات</th></tr>${rows}</table>
    <p class="hint left">«مرفوض»: سطر لا يدخل اللعب لخطأ في صيغته. «تنبيه»: يدخل اللعب لكن فيه ما يستحق التصحيح.</p>
    ${list}
    <p>التخزين: ${USED.size} مستعملاً، و${load(LS.reports, []).length} بلاغاً، وإحصاء ${Object.keys(STATS).length} سؤالاً · حفظ دائم: ${persisted}${saveFailed ? ' · <b class="bad-t">حدث فشل في الحفظ</b>' : ''}</p>`,
    [{ t: 'إغلاق', primary: true }], { noFocus: true });
}

/* ---------- النهاية ---------- */
function joinNames(ns) { return ns.length <= 1 ? ns.join('') : ns.slice(0, -1).join('، ') + ' و' + ns[ns.length - 1]; }
function endGame() {
  if (!G) return;
  commitStats(); timerHalt(); UNDO.length = 0;
  const ranked = G.teams.map((t, i) => ({ ...t, i })).sort((a, b) => b.score - a.score);
  const top = ranked[0].score; const winners = ranked.filter(t => t.score === top);
  $('#winner').textContent = G.teams.length === 1 ? `نتيجتك: ${ptsWord(top) === 'نقطة' ? 'نقطة واحدة' : ptsWord(top)}` :
    winners.length > 1 ? `تعادل بين ${joinNames(winners.map(w => `«${w.name}»`))} 🤝` : `🏆 الفائز: ${ranked[0].name}`;
  const rk = $('#ranking'); rk.innerHTML = '';
  const medals = ['🥇', '🥈', '🥉'];
  let place = 0, prev = null;
  ranked.forEach((t, k) => {
    if (t.score !== prev) place = k; prev = t.score;
    rk.appendChild(el('div', 'rk' + (t.score === top ? ' first' : ''),
      `<div class="m">${medals[place] || place + 1}</div><div class="nm">${esc(t.name)}<div class="dt">صح ${t.ok} · سرقة ${t.steals || 0} · خطأ ${t.bad}</div></div><div class="pt" style="color:${t.color}">${fmt(t.score)}</div>`));
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

/* ---------- الشاشة: ملء الشاشة ومنع الإطفاء ---------- */
const fullscreenSupported = () => !!(document.documentElement.requestFullscreen || document.documentElement.webkitRequestFullscreen);
function toggleFullscreen() {
  const d = document;
  try {
    if (d.fullscreenElement || d.webkitFullscreenElement) (d.exitFullscreen || d.webkitExitFullscreen).call(d);
    else (d.documentElement.requestFullscreen || d.documentElement.webkitRequestFullscreen).call(d.documentElement);
  } catch {}
}
let wakeLock = null;
async function wake(on) {
  try {
    if (on && !wakeLock && 'wakeLock' in navigator && document.visibilityState === 'visible') {
      wakeLock = await navigator.wakeLock.request('screen');
      wakeLock.addEventListener('release', () => { wakeLock = null; });
    } else if (!on && wakeLock) { const w = wakeLock; wakeLock = null; await w.release(); }
  } catch {}
}

/* ---------- الربط ---------- */
function resumeSaved() {
  if (!READY) return toast('انتظر حتى تُحمَّل الأسئلة');
  let g = load(LS.game, null);
  if (!g || !Array.isArray(g.teams)) return renderHome();
  if (g.v !== 2) { g = convertOld(g); if (!g) { localStorage.removeItem(LS.game); toast('لم يبقَ في المسابقة المحفوظة شيء'); return renderHome(); } }
  G = g; UNDO.length = 0;
  if (G.phase === 'q' && G.timer) G.paused = true; // يعود متوقفاً بالوقت المتبقي نفسه
  persist(); show('game'); renderGame();
}
function onKey(e) {
  if (!screenIs('game') || !G || modalOpen()) return;
  if (/^(INPUT|TEXTAREA)$/.test((e.target || {}).tagName)) return;
  const k = T.toWestern(e.key);
  if (/^[1-4]$/.test(k)) { const b = $('#options').children[+k - 1]; if (b && b.tagName === 'BUTTON' && !b.disabled) { e.preventDefault(); b.click(); } return; }
  if ((k === ' ' || k === 'Enter') && G.phase === 'done') { e.preventDefault(); next(); return; }
  if (k === 'p' || k === 'P' || k === 'ح') { togglePause(); return; }
  if (k === 'Escape') menu();
}
function bind() {
  document.querySelectorAll('.ver').forEach(e => e.textContent = VERSION);
  $('#btn-add-team').onclick = () => { if (S.teams.length < 8) { S.teams.push(`الفريق ${ORD[S.teams.length]}`); saveSettings(); renderHome(); } };
  $('#btn-remove-team').onclick = () => { if (S.teams.length > 1) { S.teams.pop(); saveSettings(); renderHome(); } };
  $('#btn-start').onclick = () => {
    if (!READY) return;
    if (load(LS.game, null)) confirmBox('<h3>مسابقة جديدة؟</h3><p>عندك مسابقة لم تكتمل، وستُحذف إذا بدأت واحدة جديدة.</p>', 'ابدأ جديدة', startGame);
    else startGame();
  };
  $('#btn-resume').onclick = resumeSaved;
  $('#btn-discard').onclick = () => confirmBox('<h3>حذف المسابقة المحفوظة؟</h3><p>تُحذف نهائياً ولا يمكن متابعتها.</p>', 'نعم، احذفها', () => { localStorage.removeItem(LS.game); renderHome(); });
  $('#btn-retry').onclick = async () => { $('#btn-start').textContent = 'جارٍ تحميل الأسئلة…'; await loadBank(); renderHome(); };
  $('#btn-next').onclick = next;
  $('#btn-fifty').onclick = useFifty;
  $('#btn-clue').onclick = moreClue;
  $('#btn-swap').onclick = swapQ;
  $('#btn-showopts').onclick = showOptions;
  $('#btn-reveal').onclick = hostReveal;
  $('#btn-report').onclick = reportQ;
  $('#btn-pause').onclick = togglePause;
  $('#pause-cover').onclick = resumeGame;
  $('#btn-undo').onclick = undo;
  $('#btn-fs').onclick = toggleFullscreen;
  $('#btn-fs').classList.toggle('hidden', !fullscreenSupported());
  $('#btn-again').onclick = startGame;
  $('#btn-home').onclick = () => { show('home'); renderHome(); };
  $('#btn-reports').onclick = showReports;
  $('#btn-history').onclick = historyModal;
  $('#btn-diag').onclick = diagModal;
  $('#btn-menu').onclick = menu;
  $('#btn-reset-used').onclick = () => confirmBox('<h3>تصفير السجل؟</h3><p>تعود كل الأسئلة المستعملة متاحة، وقد تتكرر عليكم. ننصح بتصدير السجل قبل ذلك.</p>', 'نعم، صفّر', () => { setUsed([]); renderHome(); toast('تم التصفير'); });
  $('#import-file').onchange = async e => {
    const f = e.target.files && e.target.files[0]; e.target.value = '';
    if (!f) return;
    try { importHistory(await decodeAny(await f.text())); } catch (err) { modal(`<h3>تعذّر الاستيراد</h3><p>${esc(err.message || err)}</p>`); }
  };
  document.addEventListener('keydown', onKey);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') { if (G && tickH) { timerHalt(); G.paused = true; persist(); renderQ(); } }
    else if (screenIs('game')) wake(true);
  });
  const fsBtn = () => { $('#btn-fs').textContent = document.fullscreenElement || document.webkitFullscreenElement ? '🗗' : '⛶'; };
  document.addEventListener('fullscreenchange', fsBtn); document.addEventListener('webkitfullscreenchange', fsBtn);
}

(async function init() {
  bind();
  renderHome();
  await loadBank();
  renderHome();
  try { if (navigator.storage && navigator.storage.persist) navigator.storage.persist(); } catch {}
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js?v=' + VERSION).catch(() => {});
})();
