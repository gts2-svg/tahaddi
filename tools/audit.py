#!/usr/bin/env python3
"""فحص الأسئلة من الخيارات الكاشفة: الإجابة داخل السؤال، الخيار الصحيح أطول بوضوح، أقواس أو قيود في الصحيح فقط."""
import re, sys, glob, os
AR_DIAC = re.compile(r'[ً-ْٰـ]')
STOP = set('من ما في على عن إلى الى أي التي الذي هو هي كان ذلك هذا هذه مع بين قال بن ابن أبو أبي عبد الله سورة كتاب صاحب أول آخر اسم معنى ثم أو لا لم كل بعد قبل عند يوم'.split())
def norm(w):
    w = AR_DIAC.sub('', w)
    w = re.sub(r'[«»"().,:؟?!،;\-]', '', w)
    w = w.replace('أ','ا').replace('إ','ا').replace('آ','ا').replace('ى','ي').replace('ة','ه')
    for p in ('وال','بال','فال','كال','لل','ال'):
        if w.startswith(p) and len(w) - len(p) >= 3: w = w[len(p):]; break
    for s in ('يه','يات','ات','ون','ين','يه','ي','ه'):
        if w.endswith(s) and len(w) - len(s) >= 3: w = w[:-len(s)]; break
    return w
def toks(s): return {norm(w) for w in re.split(r'\s+', s) if len(norm(w)) >= 3 and norm(w) not in STOP and AR_DIAC.sub('', w) not in STOP}
def vis_len(s): return len(AR_DIAC.sub('', s))
issues = []
for f in sorted(glob.glob(os.path.join(os.path.dirname(__file__), '..', 'data', '*.txt'))):
    cat = os.path.basename(f)[:-4]
    for i, l in enumerate(open(f, encoding='utf8'), 1):
        l = l.strip()
        if not l or l.startswith('#'): continue
        p = [x.strip() for x in l.split('|')]
        if len(p) < 6: continue
        p = p[:6]
        d, q, a, ws = p[0], p[1], p[2], p[3:]
        if cat == 'whoami': q = q.split(';;')[0]   # التلميح الأول فقط
        if 'أكمل' in q: continue
        qt = toks(q); at = toks(a)
        leak = (qt & at) - set().union(*[toks(w) for w in ws])
        if leak: issues.append((cat, i, 'في السؤال', '/'.join(leak), l))
        la, lw = vis_len(a), [vis_len(w) for w in ws]
        if la > max(lw) * 1.35 and la - max(lw) >= 6: issues.append((cat, i, 'أطول', f'{la} مقابل {max(lw)}', l))
        if ('(' in a) and not any('(' in w for w in ws): issues.append((cat, i, 'أقواس', '', l))
for c, i, k, x, l in issues: print(f'{c}:{i} [{k}] {x} :: {l[:110]}')
print('المجموع', len(issues), file=sys.stderr)
