#!/usr/bin/env python3
"""كشف الأسئلة المكررة بالمعنى: نفس الإجابة وتقارب كبير في كلمات السؤال (خارج «من أنا؟»)."""
import glob, re, itertools, os, collections
D = re.compile(r'[ً-ْٰـ]')
STOP = set('من ما في على عن الى اي التي الذي هو هي كان ذلك هذا هذه مع بين قال بن ابن ابو ابي عبد الله سوره كتاب صاحب اول اخر اسم معني ثم او لا لم كل بعد قبل عند يوم القائل البيت وزن الشهير المشهور تقع يقع دوله مدينه'.split())
def norm(s):
    s = D.sub('', s); s = re.sub(r'[«»"().,:؟?!،;\-]|\\n', ' ', s)
    return s.replace('أ','ا').replace('إ','ا').replace('آ','ا').replace('ى','ي').replace('ة','ه')
def toks(s): return {w[2:] if w.startswith('ال') and len(w) > 4 else w for w in norm(s).split() if len(w) >= 3} - STOP
items = []
base = os.path.join(os.path.dirname(__file__), '..', 'data')
for f in glob.glob(os.path.join(base, '*.txt')):
    c = os.path.basename(f)[:-4]
    if c == 'whoami': continue
    for i, l in enumerate(open(f, encoding='utf8'), 1):
        p = l.strip().split('|')
        if len(p) >= 6 and p[0] in '1234': items.append((c, i, p[1], norm(p[2]).strip(), toks(p[1])))
by = collections.defaultdict(list)
for it in items: by[it[3]].append(it)
for a, lst in by.items():
    for x, y in itertools.combinations(lst, 2):
        if not x[4] or not y[4]: continue
        j = len(x[4] & y[4]) / min(len(x[4]), len(y[4]))
        if j >= 0.5: print(f'{x[0]}:{x[1]} | {y[0]}:{y[1]} | {a} | {x[2][:60]} || {y[2][:60]}')
