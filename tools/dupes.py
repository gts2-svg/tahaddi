#!/usr/bin/env python3
"""كشف الأسئلة المكررة بالمعنى عبر كل الملفات (ومنها تلميحات «من أنا؟»)، بتطبيع عربي وتجذير خفيف.

أنواع المرشحات:
  same     الإجابة نفسها (بعد التطبيع) وكلمات السؤالين متقاربة: المعلومة نفسها مرتين
  reverse  سؤالان معكوسان: إجابة كلٍّ منهما في نص الآخر (عاصمة فرنسا؟ باريس / باريس عاصمة أي دولة؟ فرنسا)
  reveals  نص سؤال يذكر إجابة سؤال آخر وموضوعهما واحد، فيكشف أحدهما الآخر إذا اجتمعا
  text     نصان متطابقان تقريباً بإجابتين مختلفتين

الأزواج التي يجمعها مفتاح معلومة (الحقل الثامن) مُعالجة أصلاً في التطبيق، فلا تظهر إلا مع --all.

الاستعمال: python3 tools/dupes.py [--all] [--type same,reverse] [--cat poetry] [--min 0.5]
"""
import collections, itertools, os, sys
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tahaddi_data as td

EXTRA_STOP = {td.stem(w) for w in 'الذي التي قوله تعالى ورد قال النبي الشاعر الصحابي يسمي يسمى سمي اسم اشهر اكبر اصغر اطول اول اخر اي ما من'.split()}


def main():
    args = sys.argv[1:]
    def opt(name, default=None):
        if name in args:
            i = args.index(name)
            return args[i + 1] if i + 1 < len(args) else default
        return default
    show_all = '--all' in args
    types = set((opt('--type') or 'same,reverse,reveals,text').split(','))
    cats = opt('--cat'); cats = cats.split(',') if cats else None
    thr = float(opt('--min') or 0.5)

    qs = td.read_questions()
    items = []
    for q in qs:
        st = td.content_stems(q.stem_text) - EXTRA_STOP
        ans = td.norm_answer(q.a)
        ast = td.content_stems(q.a) - EXTRA_STOP
        items.append((q, st, ans, ast, set(q.keys)))

    # فهرس مقلوب: الجذع ← الأسئلة، والإجابة ← الأسئلة
    by_stem = collections.defaultdict(set); by_ans = collections.defaultdict(set)
    for i, (q, st, ans, ast, _) in enumerate(items):
        for s in st | ast: by_stem[s].add(i)
        by_ans[ans].add(i)
    cand = set()
    for ids in by_ans.values():
        if len(ids) < 400: cand.update(itertools.combinations(sorted(ids), 2))
    for s, ids in by_stem.items():
        if len(ids) <= 60: cand.update(itertools.combinations(sorted(ids), 2))

    out = []
    for i, j in cand:
        a, b = items[i], items[j]
        qa, sa, ansa, asa, ka = a
        qb, sb, ansb, asb, kb = b
        if cats and qa.cat not in cats and qb.cat not in cats: continue
        keyed = bool(ka & kb)
        if keyed and not show_all: continue
        found = None
        if sa and sb:
            ov = len(sa & sb) / min(len(sa), len(sb))
            jac = len(sa & sb) / len(sa | sb)
        else:
            ov = jac = 0
        common = len(sa & sb)
        if 'same' in types and ansa == ansb and ansa and ov >= thr and common >= 2:
            found = ('same', f'الإجابة نفسها «{qa.a}»، وتقارب {ov:.0%}')
        elif 'reverse' in types and asa and asb and asa <= sb and asb <= sa:
            found = ('reverse', f'معكوسان: «{qa.a}» ↔ «{qb.a}»')
        elif 'text' in types and jac >= 0.8 and len(sa | sb) >= 3 and ansa != ansb:
            found = ('text', f'نصان متشابهان جداً ({jac:.0%}) بإجابتين مختلفتين: قد يكشف أحدهما الآخر في المسابقة نفسها')
        elif 'reveals' in types:
            for x, y in ((a, b), (b, a)):
                qx, sx, ansx, asx, _ = x; qy, sy, ansy, asy, _ = y
                rest_x = sx - asy; rest_y = sy - asy
                if asy and asy <= sx and len(rest_x & rest_y) >= 2 and len(rest_x & rest_y) / min(len(rest_x), len(rest_y)) >= 0.5:
                    found = ('reveals', f'نص {qx.ref()} يذكر «{qy.a}» إجابة {qy.ref()}')
                    break
        if found:
            out.append((found[0], qa, qb, found[1] + (' [مربوطان بمفتاح]' if keyed else '')))

    names = {'same': 'المعلومة نفسها', 'reverse': 'معكوس', 'reveals': 'يكشف', 'text': 'نص'}
    order = {'same': 0, 'reverse': 1, 'reveals': 2, 'text': 3}
    for k, qa, qb, msg in sorted(out, key=lambda x: (order[x[0]], x[1].cat, x[1].line)):
        print(f'[{names[k]}] {qa.ref()} | {qb.ref()} | {msg}\n    {qa.raw[:110]}\n    {qb.raw[:110]}')
    c = collections.Counter(k for k, *_ in out)
    print('\nالمجموع:', len(out), ' '.join(f'{names[k]}={v}' for k, v in c.items()), file=sys.stderr)


if __name__ == '__main__':
    main()
