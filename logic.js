/* تحدّي — منطق اللعب الخالص (بلا شاشة): التحليل، والتوزيع، والاختيار، والنقاط، والمؤقت.
   يُحمَّل في المتصفح قبل app.js (فيصير window.TL)، ويُستدعى في node للاختبارات: require('./logic.js') */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.TL = api;
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const LEVELS = [1, 2, 3, 4];

  /* ---------- أدوات عامة ---------- */
  function shuffle(a, rng = Math.random) {
    for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rng() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
    return a;
  }
  function hash(s) { let h = 5381; for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0; return (h >>> 0).toString(36); }
  // الأرقام العربية المشرقية (٠-٩) والفارسية (۰-۹) إلى أرقام غربية
  function toWestern(s) {
    return String(s).replace(/[٠-٩]/g, c => String(c.charCodeAt(0) - 0x660))
      .replace(/[۰-۹]/g, c => String(c.charCodeAt(0) - 0x6F0));
  }
  const DIAC = /[ً-ْٰـ]/g;
  // تطبيع الإجابة لمنع اجتماع إجابتين متماثلتين في المسابقة الواحدة
  function normAns(s) {
    return String(s).replace(DIAC, '').replace(/[«»"()]/g, '')
      .replace(/[أإآٱ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه')
      .replace(/\s+/g, ' ').trim()
      .replace(/^سوره /, '')
      .replace(/^ال/, '').trim();
  }
  function normKey(s) { return String(s).replace(DIAC, '').trim().replace(/\s+/g, '-'); }

  /* ---------- تحليل ملف الأسئلة ---------- */
  // الصيغة: الصعوبة|السؤال|الصحيح|خطأ|خطأ|خطأ|المعرّف|المفاتيح
  // يعيد { items, problems } — كل مشكلة: { cat, line, level: 'error'|'warn', msg, text }
  // السطر الذي فيه خطأ يُستبعد، والتنبيه لا يستبعده.
  function parseBank(cat, text, opts = {}) {
    const items = []; const problems = []; const ids = new Set();
    const clues = !!opts.clues;
    String(text).split(/\r?\n/).forEach((raw, i) => {
      const line = raw.trim(); const ln = i + 1;
      if (!line || line.startsWith('#')) return;
      const bad = (msg, level = 'error') => problems.push({ cat, line: ln, level, msg, text: line.slice(0, 140) });
      const p = line.split('|').map(x => x.trim());
      if (p.length < 6) return bad(`حقول ناقصة (${p.length} من 6 على الأقل)`);
      if (p.length > 8) return bad(`علامة | زائدة داخل النص (${p.length} حقلاً، والحد 8)`);
      const dRaw = toWestern(p[0]);
      if (!/^[1-4]$/.test(dRaw)) return bad(`الصعوبة «${p[0]}» ليست من 1 إلى 4`);
      if (dRaw !== p[0]) bad('الصعوبة مكتوبة بأرقام عربية مشرقية (قُبلت)', 'warn');
      const d = +dRaw;
      if (!p[1] || !p[2] || !p[3] || !p[4] || !p[5]) return bad('حقل فارغ في السؤال أو الخيارات');
      // المقارنة بالنص الحرفي: أسئلة الإملاء والضبط تختلف خياراتها بالتشكيل أو الهمزة وحدها
      const ex = x => x.replace(/\s+/g, ' ');
      const na = normAns(p[2]); const xw = p.slice(3, 6).map(ex);
      if (xw.includes(ex(p[2]))) return bad('خيار خاطئ مطابق للإجابة الصحيحة');
      if (new Set(xw).size < 3) bad('خياران خاطئان متطابقان', 'warn');
      const sid = p[6] || '';
      if (sid && ids.has(sid)) return bad(`معرّف مكرر «${sid}»`);
      if (sid) ids.add(sid); else bad('سؤال بلا معرّف (شغّل tools/assign_ids.py)', 'warn');
      const keys = [];
      if (p[7]) p[7].split(/[,،]/).map(normKey).filter(Boolean).forEach(k => { if (!keys.includes(k)) keys.push(k); });
      const q = p[1].replace(/\\n/g, '\n');
      const legacy = cat + ':' + hash(q + '|' + p[2]);
      const item = { id: sid ? cat + ':' + sid : legacy, legacy, cat, d, q, a: p[2], w: p.slice(3, 6), akey: na, keys };
      if (clues) {
        item.clues = q.split(';;').map(x => x.trim()).filter(Boolean);
        if (item.clues.length !== 3) bad(`عدد التلميحات ${item.clues.length} والمطلوب 3`, 'warn');
      }
      items.push(item);
    });
    return { items, problems };
  }

  /* ---------- الفهرس والسجل ---------- */
  function buildIndex(bank) {
    const byId = new Map(); const byLegacy = new Map();
    Object.values(bank).forEach(list => list.forEach(q => { byId.set(q.id, q); byLegacy.set(q.legacy, q.id); }));
    return { byId, byLegacy };
  }
  // ترحيل المعرّفات القديمة (المأخوذة من النص) إلى المعرّفات الثابتة
  function migrateIds(ids, index) {
    const out = new Set();
    ids.forEach(id => out.add(index.byLegacy.get(id) || id));
    return out;
  }
  // مفاتيح المعلومات المستعملة: سؤال مستعمل يجعل كل سؤال يشاركه مفتاحاً مستعملاً
  function usedKeySet(used, index) {
    const ks = new Set();
    used.forEach(id => { const q = index.byId.get(id); if (q) q.keys.forEach(k => ks.add(k)); });
    return ks;
  }
  function isFresh(q, used, usedKeys) {
    return !used.has(q.id) && !q.keys.some(k => usedKeys.has(k));
  }
  // «بصمات» السؤال داخل المسابقة: إجابته المطبَّعة ومفاتيحه
  function facts(q) { return ['a:' + q.akey, ...q.keys.map(k => 'k:' + k)]; }
  function clashes(q, factSet) { return facts(q).some(f => factSet.has(f)); }
  function addFacts(q, factSet) { facts(q).forEach(f => factSet.add(f)); return factSet; }
  function factsOf(ids, index) {
    const s = new Set(); ids.forEach(id => { const q = index.byId.get(id); if (q) addFacts(q, s); }); return s;
  }
  // الأسئلة المتاحة من قسم ومستوى (d=0: كل المستويات)، غير مستعملة ولا تصطدم بما في المسابقة
  function freshPool(bank, cat, d, ctx) {
    return (bank[cat] || []).filter(q => (!d || q.d === d) && isFresh(q, ctx.used, ctx.usedKeys)
      && !(ctx.exclude && ctx.exclude.has(q.id)) && !(ctx.facts && clashes(q, ctx.facts)));
  }
  // يأخذ n أسئلة لا يصطدم بعضها ببعض ولا بما في المسابقة؛ لا يعدّل factSet
  function takeN(pool, n, factSet, rng) {
    const tmp = new Set(factSet); const out = [];
    for (const q of shuffle([...pool], rng)) {
      if (out.length >= n) break;
      if (clashes(q, tmp)) continue;
      addFacts(q, tmp); out.push(q);
    }
    return out;
  }
  function countFresh(bank, cat, d, ctx) {
    // عدد ما يمكن أخذه فعلاً (بعد إسقاط الإجابات المتماثلة فيما بينها)
    const pool = freshPool(bank, cat, d, ctx); const tmp = new Set(ctx.facts || []); let n = 0;
    pool.forEach(q => { if (!clashes(q, tmp)) { addFacts(q, tmp); n++; } });
    return n;
  }

  /* ---------- التوزيع بالجولات (الطريقة المتتابعة) ---------- */
  // كل جولة: قسم واحد ومستوى واحد، ولكل فريق سؤال منهما. فلا يلازم فريقٌ قسماً، ولا يظلم الحظُّ في الصعوبة.
  // diffMode: 'fixed' (level) | 'mixed' | 'team' (المستوى يختاره الفريق في دوره، فيبقى السؤال فارغاً حتى يختار)
  // يعيد { turns: [{round, team, cat, d, id}], rounds }
  function dealRounds({ bank, cats, nTeams, rounds, diffMode = 'mixed', level = 2, ctx, rng = Math.random }) {
    const order = shuffle([...cats], rng);
    const factSet = new Set(ctx.facts || []);
    const turns = []; let r = 0; let cycle = [];
    if (diffMode === 'team') {
      // المستوى يُختار وقت اللعب؛ نتأكد فقط أن في القسم ما يكفي لكل فرق الجولة
      const cap = {}; order.forEach(c => { cap[c] = countFresh(bank, c, 0, { ...ctx, facts: factSet }); });
      for (; r < rounds; r++) {
        let cat = null;
        for (let k = 0; k < order.length; k++) { const c = order[(r + k) % order.length]; if (cap[c] >= nTeams) { cat = c; break; } }
        if (!cat) break;
        cap[cat] -= nTeams;
        for (let t = 0; t < nTeams; t++) turns.push({ round: r, team: t, cat, d: null, id: null });
      }
      return { turns, rounds: r };
    }
    for (; r < rounds; r++) {
      let levels;
      if (diffMode === 'fixed') levels = [level];
      else {
        if (!cycle.length) cycle = shuffle([...LEVELS], rng);
        const want = cycle.shift();
        levels = [want, ...shuffle(LEVELS.filter(x => x !== want), rng)];
      }
      let got = null;
      outer:
      for (let k = 0; k < order.length; k++) {
        const c = order[(r + k) % order.length];
        for (const d of levels) {
          const picks = takeN(freshPool(bank, c, d, { ...ctx, facts: factSet }), nTeams, factSet, rng);
          if (picks.length === nTeams) { got = { c, d, picks }; break outer; }
        }
      }
      if (!got) break;
      got.picks.forEach((q, t) => { addFacts(q, factSet); turns.push({ round: r, team: t, cat: got.c, d: got.d, id: q.id }); });
    }
    return { turns, rounds: r };
  }

  /* ---------- لوحة الأسئلة ---------- */
  // عدد الخانات = عدد الفرق × الأسئلة لكل فريق، مقصوصاً إلى مضاعف لعدد الفرق (أدوار متساوية).
  // تُوزَّع الخانات على الأقسام والمستويات بالتناوب. يعيد { rows, total, wanted }
  function buildBoard({ bank, cats, nTeams, perTeam, levels = LEVELS, ctx, rng = Math.random }) {
    const wanted = nTeams * perTeam;
    const factSet = new Set(ctx.facts || []);
    const L = levels.length; const slots = [];
    for (let li = 0; li < L; li++) cats.forEach((c, ci) => slots.push({ c, d: levels[(li + ci) % L] }));
    const pools = slots.map(s => shuffle(freshPool(bank, s.c, s.d, ctx), rng));
    const added = []; let progress = true;
    while (added.length < wanted && progress) {
      progress = false;
      for (let i = 0; i < slots.length && added.length < wanted; i++) {
        const pool = pools[i];
        while (pool.length) {
          const q = pool.pop();
          if (clashes(q, factSet)) continue;
          addFacts(q, factSet); added.push({ c: slots[i].c, d: slots[i].d, id: q.id }); progress = true; break;
        }
      }
    }
    const total = Math.floor(added.length / nTeams) * nTeams;
    const kept = added.slice(0, total);
    const rows = [];
    cats.forEach(c => {
      const cells = kept.filter(x => x.c === c).sort((a, b) => a.d - b.d).map(x => ({ id: x.id, d: x.d, used: false, by: null }));
      if (cells.length) rows.push({ cat: c, cells });
    });
    return { rows, total, wanted };
  }

  /* ---------- النقاط ---------- */
  // النقاط بأنصاف: ½ نصف نقطة. كل قسمة تُقرَّب إلى أدنى نصف، ولا تقل عن ½.
  const halfFloor = x => Math.floor(x * 2 + 1e-9) / 2;
  const halve = p => Math.max(0.5, halfFloor(p / 2));
  // نقاط السؤال: الصعوبة، و«من أنا؟» يزيد نقطة عن كل تلميح لم يُكشف
  function basePoints(q, shown = 1) { return q.clues ? q.d + Math.max(0, q.clues.length - shown) : q.d; }
  // في وضع المضيف: إظهار الخيارات ينصّف النقاط
  function turnPoints(q, st = {}) { const p = basePoints(q, st.shown); return st.optsShown && st.host ? halve(p) : p; }
  // السرقة: نصف نقاط السؤال الحالية (فالسهل يُسرق بنصف نقطة)
  function stealPoints(p) { return halve(p); }
  function fmtPts(x) {
    const neg = x < 0; const a = Math.abs(x); const i = Math.floor(a + 1e-9); const h = a - i >= 0.25;
    const s = h ? (i ? i + '½' : '½') : String(i);
    return (neg ? '−' : '') + s;
  }
  // تمييز العدد بالعربية: 1 مفرد، 2 مثنى، 3–10 جمع، 11–99 مفرد منصوب، والمئات مفرد مجرور
  function countWord(n, f) {
    if (n === 1) return f.one;
    if (n === 2) return f.two;
    const m = n % 100;
    if (m >= 3 && m <= 10) return `${n} ${f.few}`;
    if (m >= 11) return `${n} ${f.many}`;
    return `${n} ${f.hund}`;
  }
  const PTS = { one: 'نقطة', two: 'نقطتان', few: 'نقاط', many: 'نقطة', hund: 'نقطة' };
  const QS = { one: 'سؤال واحد', two: 'سؤالان', few: 'أسئلة', many: 'سؤالاً', hund: 'سؤال' };
  const ROUNDS = { one: 'جولة واحدة', two: 'جولتان', few: 'جولات', many: 'جولةً', hund: 'جولة' };
  function ptsWord(x) {
    if (x === 0.5) return 'نصف نقطة';
    if (x !== Math.floor(x) || x < 0) return `${fmtPts(x)} نقطة`;
    return countWord(x, PTS);
  }
  const qsWord = n => countWord(n, QS);
  const roundsWord = n => countWord(n, ROUNDS);
  // «بقيت 5 أسئلة» / «بقي 12 سؤالاً» / «بقي سؤالان»
  function leftMsg(n) { const m = n % 100; return (m >= 3 && m <= 10 ? 'بقيت ' : 'بقي ') + qsWord(n); }

  /* ---------- المؤقت ---------- */
  // الحالة: { total (ثوانٍ), leftMs, since (وقت البدء أو null إذا متوقف) }
  // الإيقاف والخروج والعودة لا تعيد الوقت أبداً: يُحفظ المتبقي ويُكمل منه.
  const tNew = total => ({ total, leftMs: total * 1000, since: null });
  const tRemaining = (t, now) => t.since == null ? t.leftMs : Math.max(0, t.leftMs - (now - t.since));
  const tStart = (t, now) => t.since != null ? t : { ...t, since: now };
  const tPause = (t, now) => ({ ...t, leftMs: tRemaining(t, now), since: null });
  const tSeconds = (t, now) => Math.ceil(tRemaining(t, now) / 1000 - 1e-9);
  const tExpired = (t, now) => tRemaining(t, now) <= 0;

  /* ---------- الاستيراد والتصدير ---------- */
  // دمج سجلين: اتحاد المستعمل، وبلاغات بلا تكرار (بالمعرّف)، والإحصاء بالأكبر لكل سؤال
  // (الأسئلة لا تتكرر، فالأكبر لا يضاعف العدّ إذا استُورد الملف نفسه مرتين)
  function mergeHistory(local, inc) {
    const used = new Set(local.used || []); let addedUsed = 0;
    (inc.used || []).forEach(id => { if (typeof id === 'string' && !used.has(id)) { used.add(id); addedUsed++; } });
    const reports = [...(local.reports || [])]; let addedReports = 0;
    const repKey = r => r.id || (r.cat + '|' + r.q);
    const seen = new Set(reports.map(repKey));
    (inc.reports || []).forEach(r => { if (r && typeof r === 'object' && !seen.has(repKey(r))) { seen.add(repKey(r)); reports.push(r); addedReports++; } });
    const stats = { ...(local.stats || {}) };
    Object.entries(inc.stats || {}).forEach(([id, v]) => {
      if (!Array.isArray(v)) return;
      const cur = stats[id] || [0, 0, 0];
      stats[id] = [0, 1, 2].map(i => Math.max(+cur[i] || 0, +v[i] || 0));
    });
    return { used: [...used], reports, stats, addedUsed, addedReports };
  }

  return {
    LEVELS, shuffle, hash, toWestern, normAns, normKey, parseBank,
    buildIndex, migrateIds, usedKeySet, isFresh, facts, clashes, addFacts, factsOf, freshPool, takeN, countFresh,
    dealRounds, buildBoard,
    halfFloor, halve, basePoints, turnPoints, stealPoints, fmtPts, countWord, ptsWord, qsWord, roundsWord, leftMsg,
    tNew, tRemaining, tStart, tPause, tSeconds, tExpired,
    mergeHistory,
  };
});
