#!/usr/bin/env python3
"""فحص صيغة ملفات الأسئلة قبل الرفع (يعمل آلياً في GitHub Actions).
يفحص: عدد الحقول، وأرقام الصعوبة، والخيارات الفارغة أو المكررة، والمعرّفات المكررة وصيغتها،
وسوء استعمال «|»، وتلميحات «من أنا؟» الثلاثة، وصيغة المفاتيح، وسجل الأقسام data/cats.json.

الاستعمال: python3 tools/validate.py [--strict]
  الأخطاء (تمنع دخول السطر إلى اللعب أو تفسده) تُنهي الفحص برمز 1.
  التنبيهات لا تُفشل الفحص إلا مع --strict.
"""
import json, os, re, sys, collections
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tahaddi_data as td

KEY_RE = re.compile(r'^[ء-ي٠-٩ٱ-ۓa-zA-Z0-9_\-]+$')
errors, warns = [], []


def err(where, msg): errors.append(f'{where}: {msg}')
def warn(where, msg): warns.append(f'{where}: {msg}')


def main():
    strict = '--strict' in sys.argv
    try:
        reg = td.load_cats()
    except Exception as e:
        print(f'خطأ: تعذّر قراءة data/cats.json: {e}')
        return 1
    cats = reg.get('categories') or []
    need = ('key', 'name', 'icon', 'file', 'color', 'prefix')
    keys, prefixes = set(), set()
    for c in cats:
        miss = [k for k in need if not c.get(k)]
        if miss: err('cats.json', f'القسم {c.get("key")} ينقصه: {", ".join(miss)}')
        if c.get('key') in keys: err('cats.json', f'مفتاح قسم مكرر {c.get("key")}')
        if c.get('prefix') in prefixes: err('cats.json', f'بادئة معرّف مكررة {c.get("prefix")}')
        keys.add(c.get('key')); prefixes.add(c.get('prefix'))
        if c.get('file') and not os.path.exists(os.path.join(td.ROOT, c['file'])): err('cats.json', f'الملف غير موجود: {c["file"]}')
        if c.get('color') and not re.fullmatch(r'#[0-9a-fA-F]{6}', c['color']): err('cats.json', f'لون غير صالح {c["color"]}')
        for f in ('c1', 'c2'):
            if c.get(f) and not re.fullmatch(r'#[0-9a-fA-F]{6}', c[f]): err('cats.json', f'لون تدرّج غير صالح {f}={c[f]} في القسم {c.get("key")}')
        ic = c.get('icon') or ''
        if ic and not re.fullmatch(r'[a-z][a-z0-9-]*|M[0-9MmLlHhVvCcSsQqTtAaZz .,\-]+', ic):
            warn('cats.json', f'أيقونة القسم {c.get("key")} ليست اسماً من مكتبة الأيقونات ولا مسار SVG (الرموز التعبيرية لم تعد تُستعمل)')
    listed = {c.get('file') for c in cats}
    for f in sorted(os.listdir(td.DATA)):
        if f.endswith('.txt') and 'data/' + f not in listed: warn('cats.json', f'الملف data/{f} غير مسجل في cats.json فلن يظهر في التطبيق')

    all_ids = {}
    counts = collections.Counter()
    for c in cats:
        path = os.path.join(td.ROOT, c.get('file', ''))
        if not os.path.exists(path): continue
        pre = c['prefix']; clues = bool(c.get('clues'))
        seen_ids = {}
        with open(path, encoding='utf8') as f:
            text = f.read()
        if '\r' in text: warn(c['file'], 'نهايات أسطر بصيغة ويندوز (CRLF)')
        if text.startswith('﻿'): warn(c['file'], 'علامة BOM في أول الملف')
        for i, raw in enumerate(text.split('\n'), 1):
            l = raw.strip()
            if not l or l.startswith('#'): continue
            where = f'{c["file"]}:{i}'
            p = [x.strip() for x in l.split('|')]
            n = len(p)
            if n < 6: err(where, f'حقول ناقصة: {n} والمطلوب 6 على الأقل'); continue
            if n > 8: err(where, f'علامة | زائدة داخل النص: {n} حقلاً والحد 8'); continue
            d = p[0]
            if d.translate(td.AR_DIGITS) != d and d.translate(td.AR_DIGITS) in ('1', '2', '3', '4'):
                err(where, f'الصعوبة «{d}» بأرقام عربية مشرقية؛ اكتبها {d.translate(td.AR_DIGITS)}')
            elif d not in ('1', '2', '3', '4'):
                err(where, f'الصعوبة «{d}» ليست 1 أو 2 أو 3 أو 4'); continue
            for k, name in ((1, 'السؤال'), (2, 'الإجابة الصحيحة'), (3, 'الخيار الخاطئ الأول'), (4, 'الخيار الخاطئ الثاني'), (5, 'الخيار الخاطئ الثالث')):
                if not p[k]: err(where, f'{name} فارغ')
            opts = [re.sub(r'\s+', ' ', x) for x in p[2:6]]  # حرفياً: خيارات الإملاء تختلف بالتشكيل أو الهمزة وحدها
            if opts[0] and opts[0] in opts[1:]: err(where, 'خيار خاطئ مطابق للإجابة الصحيحة')
            elif len(set(o for o in opts[1:] if o)) < len([o for o in opts[1:] if o]): err(where, 'خياران خاطئان متطابقان')
            if any('\\n' in x for x in p[2:6]): warn(where, 'كسر سطر \\n داخل خيار')
            if clues:
                cl = [x.strip() for x in p[1].split(';;')]
                if len(cl) != 3: err(where, f'«من أنا؟» يحتاج 3 تلميحات بينها « ;; »، والموجود {len([x for x in cl if x])}')
                elif any(not x for x in cl): err(where, 'تلميح فارغ')
                elif not re.search(r'\s;;\s', p[1]): warn(where, 'افصل التلميحات بـ « ;; » مع مسافتين')
            elif ';;' in p[1]: warn(where, '«;;» في سؤال ليس من «من أنا؟»')
            sid = p[6] if n > 6 else ''
            if sid:
                if not re.fullmatch(re.escape(pre) + r'\d{4,}', sid): err(where, f'المعرّف «{sid}» ليس بصيغة {pre}0000')
                if sid in seen_ids: err(where, f'معرّف مكرر «{sid}» (سبق في السطر {seen_ids[sid]})')
                seen_ids.setdefault(sid, i)
                gid = c['key'] + ':' + sid
                if gid in all_ids and all_ids[gid] != where: err(where, f'معرّف مكرر عبر الملفات {gid}')
                all_ids.setdefault(gid, where)
            else:
                warn(where, 'سؤال جديد بلا معرّف (يُعطى بـ tools/assign_ids.py)')
            if n > 7:
                if not p[7]: warn(where, 'حقل المفاتيح فارغ؛ احذف «|» الأخيرة')
                for k in td.parse_keys(p[7]):
                    if not KEY_RE.match(k): err(where, f'مفتاح «{k}» غير صالح: حروف وأرقام وشرطة فقط، بلا مسافات، ويُفصل بين المفاتيح بفاصلة')
            counts[c['key']] += 1

    for w in warns: print('تنبيه:', w)
    for e in errors: print('خطأ:', e)
    total = sum(counts.values())
    print(f'\nفُحص {total} سؤالاً في {len(counts)} أقسام: {len(errors)} خطأ، {len(warns)} تنبيه.', ' '.join(f'{k}={v}' for k, v in counts.items()))
    if errors or (strict and warns): return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
