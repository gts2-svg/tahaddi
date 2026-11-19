/* تحدّي — مسابقة ثقافية للفرق */
'use strict';
const VERSION = '1.3.0';

const CATS = {
  religion:  { name: 'الدين',            icon: '🕌', file: 'data/religion.txt',  color: '#2fb47c' },
  seerah:    { name: 'السيرة النبوية',   icon: '🌙', file: 'data/seerah.txt',    color: '#4cc9a0' },
  history:   { name: 'التاريخ الإسلامي', icon: '📜', file: 'data/history.txt',   color: '#e0a13c' },
  geography: { name: 'الجغرافيا',        icon: '🌍', file: 'data/geography.txt', color: '#3a9be0' },
  poetry:    { name: 'الشعر',            icon: '🪶', file: 'data/poetry.txt',    color: '#b06ee0' },
  arabic:    { name: 'اللغة العربية',    icon: '✒️', file: 'data/arabic.txt',    color: '#e07a5f' },
  saudi:     { name: 'السعودية',         icon: '🌴', file: 'data/saudi.txt',     color: '#3fae5a' },
  whoami:    { name: 'من أنا؟',          icon: '🕵️', file: 'data/whoami.txt',    color: '#e05a8a', clues: true },
};
const TEAM_COLORS = ['#e0b44c', '#3a9be0', '#e05a8a', '#2fb47c', '#b06ee0', '#e07a3a', '#4cd0d0', '#c8c8c8'];
const DIFF_NAME = { 1: 'سهل', 2: 'متوسط', 3: 'صعب', 4: 'صعب جداً' };
const LETTERS = ['أ', 'ب', 'ج', 'د'];
const LS = { settings: 'tahaddi_settings', used: 'tahaddi_used', game: 'tahaddi_game', reports: 'tahaddi_reports' };

const $ = s => document.querySelector(s);
const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const load = (k, d) => { try { const v = JSON.parse(localStorage.getItem(k)); return v ?? d; } catch { return d; } };
const save = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch {} };
const shuffle = a => { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const ptsWord = n => n === 1 ? 'نقطة' : n === 2 ? 'نقطتان' : `${n} نقاط`;
function hash(s) { let h = 5381; for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0; return (h >>> 0).toString(36); }

/* ---------- البيانات ---------- */
// تطبيع الإجابة لمنع تكرار نفس المعلومة في المسابقة الواحدة
function normAns(s) {
  return String(s).replace(/[\u064B-\u0652\u0670\u0640]/g, '').replace(/[«»"()]/g, '')
    .replace(/[أإآ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه').replace(/^ال/, '').replace(/\s+/g, ' ').trim();
}
let BANK = {}; // cat -> [{id,cat,d,q,clues,a,w}]

function parseBank(cat, text) {
  const out = [];
  text.split(/\r?\n/).forEach(line => {
    line = line.trim();
    if (!line || line.startsWith('#')) return;
    const p = line.split('|').map(x => x.trim());
    if (p.length < 6) return;
    const d = parseInt(p[0], 10);
    if (![1, 2, 3, 4].includes(d)) return;
    const q = p[1].replace(/\\n/g, '\n');
    const legacy = cat + ':' + hash(q + '|' + p[2]);
    const item = { id: p[6] ? cat + ':' + p[6] : legacy, legacy, cat, d, q, a: p[2], w: p.slice(3, 6), key: normAns(p[2]) };
    if (CATS[cat].clues) item.clues = q.split(';;').map(x => x.trim()).filter(Boolean);
    out.push(item);
  });
  return out;
}

async function loadBank() {
  await Promise.all(Object.entries(CATS).map(async ([k, c]) => {
    try { const r = await fetch(c.file + '?v=' + VERSION); BANK[k] = r.ok ? parseBank(k, await r.text()) : []; }
    catch { BANK[k] = []; }
  }));
  migrateUsed();
}
// ترحيل سجل المستعمل من المعرفات القديمة (المأخوذة من النص) إلى المعرفات الثابتة
function migrateUsed() {
  const used = load(LS.used, []); if (!used.length) return;
  const map = {}; Object.values(BANK).flat().forEach(q => { map[q.legacy] = q.id; map[q.id] = q.id; });
  const out = new Set(used.map(id => map[id] || id));
  save(LS.used, [...out]);
}
const qById = id => { const c = id.split(':')[0]; return (BANK[c] || []).find(q => q.id === id); };

/* ---------- الإعدادات ---------- */
const DEFAULTS = {
  teams: ['الفريق الأول', 'الفريق الثاني'],
  cats: ['religion', 'history', 'geography', 'poetry'], difficulty: 0, perTeam: 10, timer: 30, mode: 0,
  steal: true, fifty: true, sound: true,
};
let S = Object.assign({}, DEFAULTS, load(LS.settings, {}));
S.cats = S.cats.filter(c => CATS[c]); if (!S.cats.length) S.cats = [...DEFAULTS.cats];
const saveSettings = () => save(LS.settings, S);

/* ---------- الصوت ---------- */
let actx;
function beep(type) {
  if (!S.sound) return;
  try {
    actx = actx || new (window.AudioContext || window.webkitAudioContext)();
    const seq = { ok: [[660, .09], [880, .16]], bad: [[220, .25]], tick: [[1000, .04]], clue: [[520, .08]], win: [[523, .12], [659, .12], [784, .12], [1046, .3]] }[type];
    let t = actx.currentTime;
    seq.forEach(([f, d]) => {
      const o = actx.createOscillator(), g = actx.createGain();
      o.type = type === 'bad' ? 'sawtooth' : 'sine'; o.frequency.value = f;
      g.gain.setValueAtTime(.18, t); g.gain.exponentialRampToValueAtTime(.001, t + d);
      o.connect(g).connect(actx.destination); o.start(t); o.stop(t + d); t += d;
    });
  } catch {}
}

/* ---------- عام ---------- */
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
    const all = (BANK[k] || []).filter(q => !S.difficulty || q.d === S.difficulty);
    const left = all.filter(q => !used.has(q.id)).length;
    const d = el('div', 'cat' + (S.cats.includes(k) ? ' on' : ''),
      `<div class="ic">${c.icon}</div><div class="nm">${c.name}</div><div class="ct">${left} متبقٍ من ${all.length}${S.difficulty ? ' · ' + DIFF_NAME[S.difficulty] : ''}</div>`);
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
  $('#mode-hint').textContent = S.mode ? 'كل فريق في دوره يختار القسم والصعوبة من اللوحة. في اللوحة خانة واحدة على الأقل لكل قسم ومستوى، فقلّل الأقسام إذا أردت لوحة أصغر.' : 'تأتي الأسئلة متتالية بالتناوب بين الأقسام.';

  const total = Object.values(BANK).reduce((a, b) => a + b.length, 0);
  $('#stats').textContent = `مجموع الأسئلة: ${total}`;
  const reps = load(LS.reports, []);
  $('#reports-count').textContent = reps.length ? `(${reps.length})` : '';
  $('#resume-box').classList.toggle('hidden', !load(LS.game, null));
}

/* ---------- اختيار الأسئلة ---------- */
// الأسئلة لا تتكرر أبداً: لا يُعاد سؤال مستعمل إلا بعد «تصفير» يدوي
// ولا تجتمع في المسابقة الواحدة إجابتان متماثلتان (keys)
function availPool(cat, d, excludeIds, keys) {
  const used = new Set(load(LS.used, []));
  return shuffle((BANK[cat] || []).filter(q => (!d || q.d === d) && !used.has(q.id) && !excludeIds.has(q.id) && !keys.has(q.key)));
}
function takeFrom(pool, keys) {
  while (pool.length) { const q = pool.pop(); if (!keys.has(q.key)) { keys.add(q.key); return q; } }
  return null;
}
function pickFrom(cat, d, n, excludeIds, keys = new Set()) {
  const pool = availPool(cat, d, excludeIds, keys); const out = [];
  while (out.length < n) { const q = takeFrom(pool, keys); if (!q) break; out.push(q); }
  return out;
}

function pickSequence(n) {
  const d = S.difficulty || 0; const keys = new Set(); const none = new Set();
  const pools = {}; S.cats.forEach(c => { pools[c] = availPool(c, d, none, keys); });
  const out = []; const order = shuffle([...S.cats]);
  let progress = true;
  while (out.length < n && progress) {
    progress = false;
    for (const c of order) {
      if (out.length >= n) break;
      const q = takeFrom(pools[c], keys); if (q) { out.push(q); progress = true; }
    }
  }
  return out;
}

function buildBoard(total) {
  const levels = S.difficulty ? [S.difficulty] : [1, 2, 3, 4];
  const per = Math.max(1, Math.ceil(total / (S.cats.length * levels.length)));
  const rows = []; const keys = new Set(); const none = new Set();
  S.cats.forEach(c => {
    const cells = [];
    levels.forEach(d => pickFrom(c, d, per, none, keys).forEach(q => cells.push({ id: q.id, d, used: false })));
    if (cells.length) rows.push({ cat: c, cells });
  });
  return rows;
}
function availableCount() {
  const used = new Set(load(LS.used, []));
  return S.cats.reduce((a, c) => a + (BANK[c] || []).filter(q => (!S.difficulty || q.d === S.difficulty) && !used.has(q.id)).length, 0);
}
function exhaustedModal() {
  const lvl = S.difficulty ? ` في مستوى «${DIFF_NAME[S.difficulty]}»` : '';
  modal(`<h3>انتهت الأسئلة</h3><p>لعبتم كل الأسئلة المتاحة${lvl} في الأقسام المختارة، ولن يتكرر أي سؤال إلا إذا صفّرتم السجل.</p><p>اختاروا أقساماً أو مستوى آخر، أو صفّروا سجل هذه الأقسام.</p>`,
    [{ t: 'تصفير هذه الأقسام', primary: true, f: () => {
      const ids = new Set(S.cats.flatMap(c => (BANK[c] || []).filter(q => !S.difficulty || q.d === S.difficulty).map(q => q.id)));
      save(LS.used, load(LS.used, []).filter(id => !ids.has(id))); renderHome(); toast('تم التصفير');
    } }, { t: 'إغلاق' }]);
}

/* ---------- حالة اللعبة ---------- */
let G = null;
const curTeamIdx = () => G.mode === 1 ? G.turn : G.idx % G.teams.length;
const curTeam = () => G.teams[curTeamIdx()];
const curQ = () => G.qid ? qById(G.qid) : null;
function persist() { save(LS.game, G); }
function markUsed(id) { const u = new Set(load(LS.used, [])); u.add(id); save(LS.used, [...u]); }

function startGame() {
  const names = S.teams.map((n, i) => n.trim() || `فريق ${i + 1}`);
  const total = names.length * S.perTeam;
  G = {
    mode: S.mode, teams: names.map((n, i) => ({ name: n, color: TEAM_COLORS[i], score: 0, ok: 0, bad: 0, fifty: S.fifty })),
    settings: { ...S }, idx: 0, turn: 0, qid: null,
  };
  if (G.mode === 1) {
    G.board = buildBoard(total);
    if (!G.board.length) { G = null; return exhaustedModal(); }
    persist(); show('game'); renderBoard();
  } else {
    const qs = pickSequence(total);
    if (!qs.length) { G = null; return exhaustedModal(); }
    if (qs.length < total) toast(`بقي ${qs.length} سؤالاً فقط بهذه الإعدادات`);
    G.qs = qs.map(q => q.id); G.qid = G.qs[0];
    newOptions(); persist(); show('game'); renderQ();
  }
}

function newOptions() {
  const q = curQ();
  G.opts = shuffle([q.a, ...q.w]); G.gone = []; G.answered = false; G.pick = null; G.stolen = null;
  G.shown = q.clues ? 1 : 0;
}
// نقاط السؤال الحالي (مع مكافأة التلميحات غير المكشوفة)
function qPoints(q) { return q.clues ? q.d + Math.max(0, q.clues.length - G.shown) : q.d; }

/* ---------- لوحة الأسئلة ---------- */
function renderBoard() {
  stopTimer();
  G.qid = null; persist();
  $('#board').classList.remove('hidden'); $('#qview').classList.add('hidden');
  renderScore();
  const left = G.board.reduce((a, r) => a + r.cells.filter(c => !c.used).length, 0);
  const all = G.board.reduce((a, r) => a + r.cells.length, 0);
  $('.progress').textContent = `تمّ ${all - left} من ${all}`;
  if (!left) return endGame();
  const t = curTeam();
  $('#turn').innerHTML = `دور <span style="--c:${t.color}">${esc(t.name)}</span> — اختر سؤالاً`;
  const b = $('#board'); b.innerHTML = '';
  G.board.forEach((row, r) => {
    const c = CATS[row.cat];
    const div = el('div', 'brow', `<div class="bt">${c.icon} ${c.name}</div>`);
    div.style.setProperty('--c', c.color);
    const cells = el('div', 'cells');
    row.cells.forEach((cell, k) => {
      const btn = el('button', `cell d${cell.d}${cell.used ? ' used ' + (cell.by != null ? 'ok' : 'bad') : ''}`, String(cell.d));
      if (cell.used && cell.by != null) btn.style.setProperty('--tc', G.teams[cell.by].color);
      btn.title = DIFF_NAME[cell.d];
      if (!cell.used) btn.onclick = () => openCell(r, k);
      cells.appendChild(btn);
    });
    div.appendChild(cells); b.appendChild(div);
  });
  b.appendChild(el('div', 'board-legend', '1 سهل · 2 متوسط · 3 صعب · 4 صعب جداً'));
}

function openCell(r, k) {
  const cell = G.board[r].cells[k];
  if (!qById(cell.id)) { cell.used = true; persist(); return renderBoard(); }
  G.cell = [r, k]; G.qid = cell.id; newOptions(); persist(); renderQ();
}

/* ---------- عرض السؤال ---------- */
let timerH = null;
function renderScore(bumpIdx) {
  const sb = $('#scoreboard'); sb.innerHTML = '';
  const cur = curTeamIdx();
  G.teams.forEach((t, i) => {
    const d = el('div', 'sc' + (i === cur ? ' cur' : '') + (i === bumpIdx ? ' bump' : ''),
      `<div class="n">${esc(t.name)}</div><div class="s">${t.score}</div>${G.settings.fifty ? `<div class="f">${t.fifty ? '½ متاحة' : '&nbsp;'}</div>` : ''}`);
    d.style.setProperty('--c', t.color); d.style.borderTopColor = t.color;
    sb.appendChild(d);
  });
}

function renderQ() {
  const q = curQ();
  if (!q) return skipMissing();
  $('#board').classList.add('hidden'); $('#qview').classList.remove('hidden');
  const team = curTeam();
  if (G.mode === 1) {
    const all = G.board.reduce((a, r) => a + r.cells.length, 0);
    const done = G.board.reduce((a, r) => a + r.cells.filter(c => c.used).length, 0);
    $('.progress').textContent = `سؤال ${done + 1} من ${all}`;
  } else $('.progress').textContent = `سؤال ${G.idx + 1} من ${G.qs.length}`;
  renderScore();
  $('#turn').innerHTML = `دور <span style="--c:${team.color}">${esc(team.name)}</span>`;
  const c = CATS[q.cat];
  $('#q-cat').textContent = c.icon + ' ' + c.name; $('#q-cat').style.borderColor = c.color;

  const qt = $('#q-text'); const cl = $('#clues');
  if (q.clues) {
    qt.textContent = 'من أنا؟'; qt.classList.remove('poem');
    renderClues(q);
  } else {
    cl.classList.add('hidden');
    qt.textContent = q.q; qt.classList.toggle('poem', q.q.includes('\n'));
  }
  updateDiffBadge(q);

  const box = $('#options'); box.innerHTML = ''; box.classList.remove('locked');
  G.opts.forEach((o, i) => {
    const b = el('button', 'opt', `<span class="k">${LETTERS[i]}</span><span>${esc(o)}</span>`);
    if (G.gone.includes(i)) b.classList.add('gone');
    b.onclick = () => answer(i);
    box.appendChild(b);
  });

  $('#btn-fifty').classList.toggle('hidden', !G.settings.fifty);
  $('#btn-fifty').disabled = !team.fifty || G.answered;
  $('#btn-clue').classList.toggle('hidden', !(q.clues && G.shown < q.clues.length));
  $('#btn-swap').disabled = G.answered;
  $('#tools').classList.toggle('hidden', G.answered);
  $('#after').classList.add('hidden');

  if (G.answered) { reveal(true); return; }
  startTimer();
}

function updateDiffBadge(q) {
  $('#q-diff').textContent = q.clues ? `${DIFF_NAME[q.d]} · الآن ${ptsWord(qPoints(q))}` : `${DIFF_NAME[q.d]} (${ptsWord(q.d)})`;
}

function renderClues(q) {
  const cl = $('#clues'); cl.innerHTML = ''; cl.classList.remove('hidden');
  q.clues.forEach((t, i) => {
    if (i < G.shown || G.answered) cl.appendChild(el('div', 'clue', `<b>${i + 1}</b>${esc(t)}`));
    else cl.appendChild(el('div', 'clue locked', `<b>${i + 1}</b>تلميح مخفي`));
  });
}

function moreClue() {
  const q = curQ(); if (!q || !q.clues || G.answered || G.shown >= q.clues.length) return;
  G.shown++; persist(); beep('clue');
  renderClues(q); updateDiffBadge(q);
  $('#btn-clue').classList.toggle('hidden', G.shown >= q.clues.length);
}

function skipMissing() { // سؤال حُذف من الملفات بعد بدء اللعبة
  if (G.mode === 1) { const [r, k] = G.cell || [0, 0]; if (G.board[r]) G.board[r].cells[k].used = true; return renderBoard(); }
  G.qs.splice(G.idx, 1); if (G.idx >= G.qs.length) return endGame();
  G.qid = G.qs[G.idx]; newOptions(); renderQ();
}

function startTimer() {
  stopTimer();
  const T = G.settings.timer; const tw = $('#timer');
  if (!T) { tw.classList.add('hidden'); return; }
  tw.classList.remove('hidden', 'warn');
  let left = T; const bar = $('#timer-bar'); const num = $('#timer-num');
  const draw = () => { num.textContent = left; bar.style.strokeDashoffset = 100.5 * (1 - left / T); tw.classList.toggle('warn', left <= 5); };
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
  const q = curQ(); const ti = curTeamIdx(); const team = G.teams[ti];
  G.answered = true; G.pick = i;
  const ok = i >= 0 && G.opts[i] === q.a;
  G.earned = ok ? qPoints(q) : 0;
  if (ok) { team.score += G.earned; team.ok++; beep('ok'); } else { team.bad++; beep('bad'); }
  if (G.mode === 1) { const [r, k] = G.cell; const cell = G.board[r].cells[k]; cell.used = true; cell.by = ok ? ti : null; }
  markUsed(q.id); persist();
  reveal(false, ok ? ti : null);
}

function reveal(restoring, bumpIdx) {
  const q = curQ();
  if (q.clues) renderClues(q);
  const box = $('#options'); box.classList.add('locked');
  [...box.children].forEach((b, j) => {
    b.disabled = true;
    if (G.opts[j] === q.a) b.classList.add('ok');
    else if (j === G.pick) b.classList.add('bad');
  });
  const ok = G.pick >= 0 && G.opts[G.pick] === q.a;
  const v = $('#verdict');
  v.className = 'verdict ' + (ok ? 'ok' : 'bad');
  v.textContent = ok ? `صح! +${G.earned}` : (G.pick === -1 ? 'انتهى الوقت ⏱' : 'خطأ');
  const st = $('#steal');
  const canSteal = !ok && G.settings.steal && G.teams.length > 1 && G.stolen == null;
  st.classList.toggle('hidden', !canSteal);
  if (canSteal) {
    const sb = $('#steal-btns'); sb.innerHTML = '';
    const pts = Math.ceil(qPoints(q) / 2);
    G.teams.forEach((t, k) => {
      if (k === curTeamIdx()) return;
      const b = el('button', 'btn sm', `${esc(t.name)} +${pts}`); b.style.setProperty('--c', t.color);
      b.onclick = () => {
        t.score += pts; t.ok++; G.stolen = k;
        if (G.mode === 1) { const [r, c] = G.cell; G.board[r].cells[c].by = k; }
        persist(); beep('ok'); st.classList.add('hidden'); renderScore(k); toast(`سرقة ناجحة لـ ${t.name}`);
      };
      sb.appendChild(b);
    });
  }
  $('#tools').classList.add('hidden');
  $('#after').classList.remove('hidden');
  const last = G.mode === 1 ? !G.board.some(r => r.cells.some(c => !c.used)) : G.idx + 1 >= G.qs.length;
  $('#btn-next').textContent = last ? 'النتيجة' : (G.mode === 1 ? 'إلى اللوحة' : 'التالي');
  renderScore(restoring ? undefined : bumpIdx);
}

function next() {
  if (G.mode === 1) { G.turn = (G.turn + 1) % G.teams.length; G.qid = null; persist(); return renderBoard(); }
  if (G.idx + 1 >= G.qs.length) return endGame();
  G.idx++; G.qid = G.qs[G.idx]; newOptions(); persist(); renderQ();
}

function useFifty() {
  const team = curTeam();
  if (!team.fifty || G.answered) return;
  const q = curQ();
  const wrong = G.opts.map((o, i) => o === q.a ? -1 : i).filter(i => i >= 0);
  G.gone = shuffle(wrong).slice(0, 2); team.fifty = false; persist();
  G.gone.forEach(i => $('#options').children[i].classList.add('gone'));
  $('#btn-fifty').disabled = true; renderScore();
}

function swapQ() {
  if (G.answered) return;
  const q = curQ();
  const inGame = new Set(G.mode === 1 ? G.board.flatMap(r => r.cells.map(c => c.id)) : G.qs);
  const keys = new Set([...inGame].map(id => (qById(id) || {}).key).filter(Boolean));
  const [rep] = pickFrom(q.cat, q.d, 1, inGame, keys);
  if (!rep) return toast('لا يوجد بديل');
  markUsed(q.id);
  if (G.mode === 1) { const [r, k] = G.cell; G.board[r].cells[k].id = rep.id; } else G.qs[G.idx] = rep.id;
  G.qid = rep.id; newOptions(); persist(); renderQ(); toast('تم تبديل السؤال');
}

function reportQ() {
  const q = curQ(); if (!q) return;
  modal(`<h3>الإبلاغ عن السؤال</h3><p>${esc(q.q)}</p><p><small>الإجابة المعتمدة: ${esc(q.a)}</small></p><textarea class="copy" id="rep-note" placeholder="ملاحظتك (اختياري): ما الخطأ؟"></textarea>`,
    [{ t: 'حفظ', primary: true, f: () => {
      const reps = load(LS.reports, []);
      reps.push({ cat: CATS[q.cat].name, q: q.q, a: q.a, note: ($('#rep-note') || {}).value || '', at: new Date().toISOString().slice(0, 10) });
      save(LS.reports, reps); toast('تم الحفظ');
    } }, { t: 'إلغاء' }]);
}

/* ---------- النهاية ---------- */
function endGame() {
  stopTimer();
  const ranked = G.teams.map((t, i) => ({ ...t, i })).sort((a, b) => b.score - a.score);
  const top = ranked[0].score; const winners = ranked.filter(t => t.score === top);
  $('#winner').textContent = G.teams.length === 1 ? `نتيجتك: ${top}` :
    winners.length > 1 ? 'تعادل! 🤝' : `🏆 الفائز: ${ranked[0].name}`;
  const rk = $('#ranking'); rk.innerHTML = '';
  const medals = ['🥇', '🥈', '🥉'];
  let place = 0, prev = null;
  ranked.forEach((t, k) => {
    if (t.score !== prev) place = k; prev = t.score;
    rk.appendChild(el('div', 'rk' + (t.score === top ? ' first' : ''),
      `<div class="m">${medals[place] || place + 1}</div><div class="nm">${esc(t.name)}<div class="dt">صح ${t.ok} · خطأ ${t.bad}</div></div><div class="pt" style="color:${t.color}">${t.score}</div>`));
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
  modal(`<h3>الأسئلة المُبلَّغ عنها (${reps.length})</h3>` +
    reps.map(r => `<div class="rep">[${esc(r.cat)}] ${esc(r.q)}<br><small>المعتمد: ${esc(r.a)}${r.note ? ' — ' + esc(r.note) : ''}</small></div>`).join('') +
    `<p><small>انسخ القائمة وأرسلها لتصحيحها:</small></p><textarea class="copy" readonly>${esc(txt)}</textarea>`,
    [{ t: 'نسخ', primary: true, f: () => { navigator.clipboard?.writeText(txt).then(() => toast('تم النسخ')); } },
     { t: 'مسح الكل', f: () => modal('<p>مسح كل البلاغات؟</p>', [{ t: 'نعم امسح', primary: true, f: () => { save(LS.reports, []); renderHome(); } }, { t: 'لا' }]) },
     { t: 'إغلاق' }]);
}

/* ---------- الربط ---------- */
function resumeView() { show('game'); if (G.mode === 1 && !G.qid) renderBoard(); else renderQ(); }
function bind() {
  document.querySelectorAll('.ver').forEach(e => e.textContent = VERSION);
  const ORD = ['الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس', 'السابع', 'الثامن'];
  $('#btn-add-team').onclick = () => { if (S.teams.length < 8) { S.teams.push(`الفريق ${ORD[S.teams.length]}`); saveSettings(); renderHome(); } };
  $('#btn-remove-team').onclick = () => { if (S.teams.length > 1) { S.teams.pop(); saveSettings(); renderHome(); } };
  $('#btn-start').onclick = () => { if (load(LS.game, null)) modal('<p>عندك مسابقة لم تكتمل. تبدأ واحدة جديدة؟</p>', [{ t: 'جديدة', primary: true, f: startGame }, { t: 'إلغاء' }]); else startGame(); };
  $('#btn-resume').onclick = () => { G = load(LS.game, null); if (!G) return renderHome(); if (G.mode == null) G.mode = 0; resumeView(); };
  $('#btn-discard').onclick = () => { localStorage.removeItem(LS.game); renderHome(); };
  $('#btn-next').onclick = next;
  $('#btn-fifty').onclick = useFifty;
  $('#btn-clue').onclick = moreClue;
  $('#btn-swap').onclick = swapQ;
  $('#btn-report').onclick = reportQ;
  $('#btn-again').onclick = startGame;
  $('#btn-home').onclick = () => { show('home'); renderHome(); };
  $('#btn-reports').onclick = showReports;
  $('#btn-reset-used').onclick = () => modal('<p>تصفير سجل الأسئلة المستعملة؟ ستعود كل الأسئلة متاحة.</p>', [{ t: 'نعم', primary: true, f: () => { save(LS.used, []); renderHome(); toast('تم التصفير'); } }, { t: 'إلغاء' }]);
  $('#btn-menu').onclick = () => {
    stopTimer();
    const inQ = !!G.qid && !G.answered;
    modal('<h3>القائمة</h3>', [
      { t: 'إنهاء وعرض النتيجة', primary: true, f: endGame },
      { t: 'الخروج للرئيسية (تُحفظ المسابقة)', f: () => { persist(); show('home'); renderHome(); } },
      { t: 'متابعة', f: () => { if (inQ) startTimer(); } },
    ]);
  };
}

(async function init() {
  bind();
  await loadBank();
  renderHome();
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
})();
