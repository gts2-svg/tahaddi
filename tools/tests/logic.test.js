// اختبارات منطق اللعب: node --test tools/tests/*.test.js
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const TL = require('../../logic.js');

// مولّد عشوائي ثابت حتى تتكرر النتائج
function rng(seed = 1) { let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 2 ** 32; }; }

// بنك صناعي: لكل قسم ولكل مستوى n سؤالاً بإجابات مختلفة
function fakeBank(cats, perLevel = 10, opts = {}) {
  const bank = {};
  cats.forEach(c => {
    let text = '';
    let n = 0;
    for (const d of [1, 2, 3, 4]) for (let i = 0; i < perLevel; i++) {
      n++;
      const keys = opts.keys && opts.keys(c, d, i) ? '|' + opts.keys(c, d, i) : '';
      text += `${d}|سؤال ${c} ${d} ${i}|جواب ${c} ${d} ${i}|خطأ أ ${i}|خطأ ب ${i}|خطأ ج ${i}|${c[0]}${String(n).padStart(4, '0')}${keys}\n`;
    }
    bank[c] = TL.parseBank(c, text).items;
  });
  return bank;
}
const ctx0 = (bank, used = new Set()) => { const index = TL.buildIndex(bank); return { used, usedKeys: TL.usedKeySet(used, index), facts: new Set(), index }; };

/* ---------- التحليل ---------- */
test('المحلّل يقبل الأرقام العربية المشرقية في الصعوبة وينبّه', () => {
  const r = TL.parseBank('religion', '٢|سؤال|صح|خ1|خ2|خ3|r0001\n۳|سؤال2|صح2|خ1|خ2|خ3|r0002');
  assert.equal(r.items.length, 2);
  assert.equal(r.items[0].d, 2); assert.equal(r.items[1].d, 3);
  assert.equal(r.problems.filter(p => p.level === 'warn').length, 2);
});

test('المحلّل يرفض الأسطر المعيبة ويبلّغ عنها', () => {
  const text = [
    '# تعليق', '## عنوان', '',
    '5|سؤال|صح|خ1|خ2|خ3|r0001',          // صعوبة خارج المدى
    '1|سؤال|صح|خ1|خ2',                    // حقول ناقصة
    '1|سؤال|صح|خ1|خ2|خ3|r0003|مفتاح|زائد', // | زائدة
    '1|سؤال|صح|صح|خ2|خ3|r0004',           // خيار مطابق للصحيح
    '1|سؤال|صح|خ1||خ3|r0005',             // حقل فارغ
    '1|سؤال سليم|صح|خ1|خ2|خ3|r0006',
    '1|مكرر|صح9|خ1|خ2|خ3|r0006',          // معرّف مكرر
  ].join('\n');
  const r = TL.parseBank('religion', text);
  assert.equal(r.items.length, 1);
  assert.equal(r.problems.filter(p => p.level === 'error').length, 6);
  assert.deepEqual(r.problems.filter(p => p.level === 'error').map(p => p.line), [4, 5, 6, 7, 8, 10]);
});

test('المحلّل يقرأ المفاتيح والتلميحات والمعرّف الفارغ', () => {
  const r = TL.parseBank('whoami', '2|ت1 ;; ت2 ;; ت3|المتنبي|البحتري|أبو تمام|المعري||متنبي,شعراء-العباسيين', { clues: true });
  const q = r.items[0];
  assert.deepEqual(q.clues, ['ت1', 'ت2', 'ت3']);
  assert.deepEqual(q.keys, ['متنبي', 'شعراء-العباسيين']);
  assert.ok(q.id.startsWith('whoami:'));               // معرّف من النص عند غيابه
  assert.ok(r.problems.some(p => p.msg.includes('بلا معرّف')));
});

test('تطبيع الإجابات: «سورة الفاتحة» = «الفاتحة»', () => {
  assert.equal(TL.normAns('سورة الفاتحة'), TL.normAns('الفاتحة'));
  assert.equal(TL.normAns('أبو بكر'), TL.normAns('ابو بكر'));
});

/* ---------- التوزيع بالجولات ---------- */
test('بالتتابع: كل جولة قسم واحد ومستوى واحد لكل الفرق، وكل فريق يرى أقساماً مختلفة', () => {
  const cats = ['religion', 'history', 'geography', 'poetry'];
  const bank = fakeBank(cats, 20);
  for (let seed = 1; seed <= 50; seed++) {
    const { turns, rounds } = TL.dealRounds({ bank, cats, nTeams: 2, rounds: 10, diffMode: 'mixed', ctx: ctx0(bank), rng: rng(seed) });
    assert.equal(rounds, 10); assert.equal(turns.length, 20);
    for (let r = 0; r < 10; r++) {
      const rt = turns.filter(t => t.round === r);
      assert.equal(new Set(rt.map(t => t.cat)).size, 1, 'قسم واحد في الجولة');
      assert.equal(new Set(rt.map(t => t.d)).size, 1, 'مستوى واحد في الجولة');
      assert.deepEqual(rt.map(t => t.team), [0, 1]);
    }
    // الخلل القديم: الفريق الأول لا يرى إلا قسمين من أربعة
    for (const team of [0, 1]) assert.equal(new Set(turns.filter(t => t.team === team).map(t => t.cat)).size, 4);
    // النقاط الممكنة متساوية
    const sum = team => turns.filter(t => t.team === team).reduce((a, t) => a + t.d, 0);
    assert.equal(sum(0), sum(1));
  }
});

test('بالتتابع: المستوى الثابت يُحترم، والنقص يقصّ الجولات كاملة لا أدواراً متفرقة', () => {
  const cats = ['religion', 'history'];
  const bank = fakeBank(cats, 3); // 3 لكل مستوى في كل قسم = 6 من المستوى 4
  const { turns, rounds } = TL.dealRounds({ bank, cats, nTeams: 4, rounds: 10, diffMode: 'fixed', level: 4, ctx: ctx0(bank), rng: rng(3) });
  assert.ok(turns.every(t => t.d === 4));
  assert.equal(turns.length % 4, 0);
  assert.equal(turns.length, rounds * 4);
  assert.ok(rounds < 10);
});

test('بالتتابع مع «يختاره الفريق»: القسم موزّع بالجولات والمستوى فارغ', () => {
  const cats = ['religion', 'history', 'poetry'];
  const bank = fakeBank(cats, 5);
  const { turns } = TL.dealRounds({ bank, cats, nTeams: 3, rounds: 6, diffMode: 'team', ctx: ctx0(bank), rng: rng(7) });
  assert.equal(turns.length, 18);
  assert.ok(turns.every(t => t.d === null && t.id === null));
  for (let r = 0; r < 6; r++) assert.equal(new Set(turns.filter(t => t.round === r).map(t => t.cat)).size, 1);
  for (const team of [0, 1, 2]) assert.equal(new Set(turns.filter(t => t.team === team).map(t => t.cat)).size, 3);
});

test('لا يتكرر سؤال مستعمل، ولا تجتمع إجابتان متماثلتان', () => {
  const cats = ['religion'];
  let text = '';
  for (let i = 1; i <= 8; i++) text += `1|س${i}|${i <= 4 ? 'المتنبي' : 'جواب' + i}|خ1|خ2|خ3|r${String(i).padStart(4, '0')}\n`;
  const bank = { religion: TL.parseBank('religion', text).items };
  const used = new Set(['religion:r0005']);
  const { turns } = TL.dealRounds({ bank, cats, nTeams: 1, rounds: 8, diffMode: 'fixed', level: 1, ctx: ctx0(bank, used), rng: rng(1) });
  const ids = turns.map(t => t.id);
  assert.ok(!ids.includes('religion:r0005'));
  const ans = ids.map(id => bank.religion.find(q => q.id === id).akey);
  assert.equal(new Set(ans).size, ans.length);
  assert.equal(turns.length, 4); // المتنبي مرة + r6,r7,r8
});

test('المفاتيح: سؤال مستعمل يجعل شركاءه مستعملين، ولا يجتمع شريكان في مسابقة', () => {
  const text = [
    '1|بنى بغداد؟|المنصور|خ1|خ2|خ3|h0001|بغداد-المنصور',
    '1|ما المدينة التي بناها المنصور؟|بغداد|خ1|خ2|خ3|h0002|بغداد-المنصور',
    '1|سؤال آخر|جواب3|خ1|خ2|خ3|h0003',
    '1|سؤال رابع|جواب4|خ1|خ2|خ3|h0004|البردة,بغداد-المنصور',
  ].join('\n');
  const bank = { history: TL.parseBank('history', text).items };
  const index = TL.buildIndex(bank);
  // مستعمل
  const used = new Set(['history:h0001']);
  const uk = TL.usedKeySet(used, index);
  assert.deepEqual(bank.history.filter(q => TL.isFresh(q, used, uk)).map(q => q.id), ['history:h0003']);
  // داخل المسابقة
  for (let s = 1; s <= 30; s++) {
    const { turns } = TL.dealRounds({ bank, cats: ['history'], nTeams: 1, rounds: 4, diffMode: 'fixed', level: 1, ctx: ctx0(bank), rng: rng(s) });
    const keyed = turns.filter(t => ['history:h0001', 'history:h0002', 'history:h0004'].includes(t.id));
    assert.equal(keyed.length, 1);
    assert.equal(turns.length, 2);
  }
});

/* ---------- اللوحة ---------- */
test('اللوحة تلتزم بعدد الأسئلة لكل فريق وتعطي أدواراً متساوية', () => {
  const cats = ['religion', 'history', 'geography', 'poetry'];
  const bank = fakeBank(cats, 10);
  for (const [n, per] of [[2, 10], [3, 5], [4, 5], [3, 10], [5, 7]]) {
    const b = TL.buildBoard({ bank, cats, nTeams: n, perTeam: per, ctx: ctx0(bank), rng: rng(n * per) });
    const cells = b.rows.flatMap(r => r.cells);
    assert.equal(b.wanted, n * per);
    assert.equal(cells.length, n * per, `${n}×${per}`);
    assert.equal(cells.length % n, 0);
    assert.equal(new Set(cells.map(c => c.id)).size, cells.length);
  }
});

test('اللوحة عند النقص: تُقصّ إلى مضاعف لعدد الفرق وتعلن النقص', () => {
  const cats = ['saudi'];
  const bank = fakeBank(cats, 2); // 8 أسئلة فقط
  const b = TL.buildBoard({ bank, cats, nTeams: 3, perTeam: 10, ctx: ctx0(bank), rng: rng(2) });
  assert.equal(b.total, 6); assert.equal(b.wanted, 30);
  assert.equal(b.rows.flatMap(r => r.cells).length, 6);
});

test('اللوحة بمستوى ثابت لا تضم غيره', () => {
  const cats = ['religion', 'history'];
  const bank = fakeBank(cats, 10);
  const b = TL.buildBoard({ bank, cats, nTeams: 2, perTeam: 5, levels: [3], ctx: ctx0(bank), rng: rng(9) });
  assert.ok(b.rows.flatMap(r => r.cells).every(c => c.d === 3));
});

/* ---------- النقاط ---------- */
test('السرقة عادلة للسؤال السهل: نصف نقطة لا نقطة كاملة', () => {
  assert.equal(TL.stealPoints(1), 0.5);
  assert.equal(TL.stealPoints(2), 1);
  assert.equal(TL.stealPoints(3), 1.5);
  assert.equal(TL.stealPoints(4), 2);
  assert.equal(TL.stealPoints(7), 3.5);
  assert.equal(TL.stealPoints(0.5), 0.5);
  assert.equal(TL.stealPoints(1.5), 0.5);
});

test('نقاط «من أنا؟» ووضع المضيف', () => {
  const q = { d: 2, clues: ['a', 'b', 'c'] };
  assert.equal(TL.basePoints(q, 1), 4);
  assert.equal(TL.basePoints(q, 3), 2);
  assert.equal(TL.turnPoints(q, { shown: 1, host: true, optsShown: true }), 2);
  assert.equal(TL.turnPoints(q, { shown: 1, host: true, optsShown: false }), 4);
  assert.equal(TL.turnPoints({ d: 1 }, { host: true, optsShown: true }), 0.5);
  assert.equal(TL.turnPoints({ d: 3 }, { host: true, optsShown: true }), 1.5);
  assert.equal(TL.turnPoints({ d: 3 }, { host: false, optsShown: true }), 3);
});

test('عرض الأنصاف والتمييز العربي', () => {
  assert.equal(TL.fmtPts(0.5), '½');
  assert.equal(TL.fmtPts(2.5), '2½');
  assert.equal(TL.fmtPts(3), '3');
  assert.equal(TL.fmtPts(-1.5), '−1½');
  assert.equal(TL.leftMsg(10), 'بقيت 10 أسئلة');
  assert.equal(TL.leftMsg(3), 'بقيت 3 أسئلة');
  assert.equal(TL.leftMsg(12), 'بقي 12 سؤالاً');
  assert.equal(TL.leftMsg(2), 'بقي سؤالان');
  assert.equal(TL.leftMsg(1), 'بقي سؤال واحد');
  assert.equal(TL.leftMsg(100), 'بقي 100 سؤال');
  assert.equal(TL.ptsWord(1), 'نقطة');
  assert.equal(TL.ptsWord(2), 'نقطتان');
  assert.equal(TL.ptsWord(4), '4 نقاط');
  assert.equal(TL.ptsWord(12), '12 نقطة');
  assert.equal(TL.ptsWord(0.5), 'نصف نقطة');
});

/* ---------- المؤقت ---------- */
test('الإيقاف والمتابعة لا يعيدان الوقت', () => {
  let t = TL.tNew(30);
  t = TL.tStart(t, 1000);
  assert.equal(TL.tSeconds(t, 1000), 30);
  assert.equal(TL.tSeconds(t, 7500), 24);   // بعد 6.5 ثانية
  t = TL.tPause(t, 7500);
  assert.equal(TL.tSeconds(t, 99999), 24);  // متوقف: لا ينقص
  // الخروج والعودة: الحالة تُحفظ JSON ثم تُستعاد
  t = JSON.parse(JSON.stringify(t));
  t = TL.tStart(t, 200000);
  assert.equal(TL.tSeconds(t, 200000), 24);
  assert.equal(TL.tSeconds(t, 210000), 14);
  t = TL.tStart(t, 205000);                 // بدء مكرر لا يعيد شيئاً
  assert.equal(TL.tSeconds(t, 210000), 14);
  assert.ok(TL.tExpired(t, 224000));
  assert.ok(!TL.tExpired(t, 223000));
});

/* ---------- السجل ---------- */
test('دمج السجل: اتحاد، وبلا تكرار، والاستيراد المكرر لا يضاعف الإحصاء', () => {
  const local = { used: ['a:1', 'a:2'], reports: [{ id: 'a:1', note: 'x' }], stats: { 'a:1': [1, 0, 0] } };
  const inc = { used: ['a:2', 'a:3'], reports: [{ id: 'a:1', note: 'x' }, { id: 'a:9' }], stats: { 'a:1': [1, 0, 0], 'a:3': [0, 1, 1] } };
  let m = TL.mergeHistory(local, inc);
  assert.deepEqual(m.used.sort(), ['a:1', 'a:2', 'a:3']);
  assert.equal(m.addedUsed, 1); assert.equal(m.addedReports, 1);
  m = TL.mergeHistory(m, inc);
  assert.equal(m.addedUsed, 0);
  assert.deepEqual(m.stats['a:1'], [1, 0, 0]);
  assert.deepEqual(m.stats['a:3'], [0, 1, 1]);
});

test('ترحيل المعرّفات القديمة', () => {
  const bank = { religion: TL.parseBank('religion', '1|س|ج|خ1|خ2|خ3|r0001').items };
  const idx = TL.buildIndex(bank);
  const leg = bank.religion[0].legacy;
  assert.deepEqual([...TL.migrateIds([leg, 'x:1'], idx)], ['religion:r0001', 'x:1']);
});

/* ---------- ملفات البيانات الحقيقية ---------- */
test('ملفات البيانات تُقرأ، والمعرّفات فريدة عبر البنك', () => {
  const root = path.join(__dirname, '..', '..');
  const reg = JSON.parse(fs.readFileSync(path.join(root, 'data', 'cats.json'), 'utf8'));
  const all = new Set(); let n = 0;
  reg.categories.forEach(c => {
    const { items } = TL.parseBank(c.key, fs.readFileSync(path.join(root, c.file), 'utf8'), { clues: !!c.clues });
    assert.ok(items.length > 50, c.key);
    items.forEach(q => { assert.ok(!all.has(q.id), q.id); all.add(q.id); n++; });
  });
  assert.ok(n > 1000);
});
