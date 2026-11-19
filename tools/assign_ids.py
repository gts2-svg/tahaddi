#!/usr/bin/env python3
"""يعطي كل سؤال جديد معرّفاً ثابتاً في الحقل السابع (لا يتغير عند تعديل نص السؤال).
شغّله بعد إضافة أسئلة: python3 tools/assign_ids.py [--dry]

- البادئة وآخر رقم أُعطي في كل قسم في data/cats.json (prefix وlastId).
  الرقم الجديد يبدأ بعد أكبرهما: آخر رقم مسجل، وأكبر رقم في الملف. فلا يأخذ سؤال جديد رقم سؤال محذوف
  (وإلا ورث حالة «مستعمل» عند من لعبه).
- يقبل السطر ذا الحقول الستة، والسطر الذي ينتهي بـ«|» فارغة، والسطر الذي معرّفه فارغ وبعده مفاتيح:
  الصعوبة|السؤال|الصحيح|خطأ|خطأ|خطأ||مفتاح1,مفتاح2
"""
import os, re, sys
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tahaddi_data as td


def main():
    dry = '--dry' in sys.argv
    reg = td.load_cats()
    changed_reg = False
    for c in reg['categories']:
        path = os.path.join(td.ROOT, c['file'])
        if not os.path.exists(path):
            continue
        pre = c['prefix']
        with open(path, encoding='utf8') as f:
            text = f.read()
        lines = text.split('\n')
        used, mx = set(), int(c.get('lastId') or 0)
        for i, l in enumerate(lines, 1):
            if not l.strip() or l.strip().startswith('#'):
                continue
            p = [x.strip() for x in l.split('|')]
            if len(p) >= 7 and p[6]:
                if not re.fullmatch(re.escape(pre) + r'\d+', p[6]):
                    raise SystemExit(f'{c["file"]}:{i}: معرّف بصيغة غير صحيحة «{p[6]}»')
                if p[6] in used:
                    raise SystemExit(f'{c["file"]}:{i}: معرّف مكرر «{p[6]}»')
                used.add(p[6]); mx = max(mx, int(p[6][len(pre):]))
        added = 0
        for i, l in enumerate(lines):
            s = l.strip()
            if not s or s.startswith('#'):
                continue
            p = s.split('|')
            if len(p) < 6 or len(p) > 8 or p[0].strip().translate(td.AR_DIGITS) not in ('1', '2', '3', '4'):
                continue
            if len(p) >= 7 and p[6].strip():
                continue
            mx += 1; sid = f'{pre}{mx:04d}'; added += 1
            if len(p) == 6:
                p.append(sid)
            else:
                p[6] = sid
                if len(p) == 8 and not p[7].strip():
                    p = p[:7]
            lines[i] = '|'.join(p)
        if mx != int(c.get('lastId') or 0):
            c['lastId'] = mx; changed_reg = True
        if added and not dry:
            with open(path, 'w', encoding='utf8') as f:
                f.write('\n'.join(lines))
        print(f'{c["key"]}: معرّفات جديدة {added} · آخر رقم {pre}{mx:04d}')
    if changed_reg and not dry:
        td.save_cats(reg)


if __name__ == '__main__':
    main()
