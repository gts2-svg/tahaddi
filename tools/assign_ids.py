#!/usr/bin/env python3
"""يعطي كل سؤال معرّفاً ثابتاً في الحقل السابع (لا يتغير عند تعديل نص السؤال).
شغّله بعد إضافة أسئلة جديدة: python3 tools/assign_ids.py"""
import glob, os, re
PREFIX = {'religion':'r','seerah':'s','history':'h','geography':'g','poetry':'p','arabic':'a','saudi':'k','whoami':'w'}
base = os.path.join(os.path.dirname(__file__), '..', 'data')
for f in sorted(glob.glob(os.path.join(base, '*.txt'))):
    cat = os.path.basename(f)[:-4]; pre = PREFIX.get(cat, cat[0])
    lines = open(f, encoding='utf8').read().split('\n')
    used = set(); mx = 0
    for l in lines:
        p = l.split('|')
        if len(p) >= 7 and re.fullmatch(pre + r'\d+', p[6].strip()):
            n = int(p[6].strip()[len(pre):]); mx = max(mx, n)
            if p[6].strip() in used: raise SystemExit(f'معرّف مكرر {p[6]} في {cat}')
            used.add(p[6].strip())
    added = 0
    for i, l in enumerate(lines):
        p = l.split('|')
        if len(p) == 6 and p[0].strip() in ('1','2','3','4'):
            mx += 1; lines[i] = l.rstrip() + f'|{pre}{mx:04d}'; added += 1
    open(f, 'w', encoding='utf8').write('\n'.join(lines))
    print(cat, 'أُضيف', added)
