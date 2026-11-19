#!/usr/bin/env python3
"""فحص الأسئلة من الخيارات الكاشفة (فحص إرشادي: يقترح مواضع للمراجعة ولا يُفشل شيئاً).

الفحوص:
  leak      الإجابة أو جذرها في نص السؤال (في «من أنا؟»: في أي تلميح)، ولا يشاركها خيار خاطئ
  long      الخيار الصحيح أطول بوضوح من كل الخيارات الخاطئة (بالحروف أو بالكلمات)
  form      الصحيح وحده يختلف في الصيغة: لقب (الإمام، الشيخ…)، كنية، «ابن/بن»، نسبة (البخاري)،
            «ال» التعريف، أقواس أو شرح، أو العكس: كل الخاطئة تشترك في صيغة ليست في الصحيح
  absolute  خيار خاطئ فيه كلمة إطلاق (دائماً، أبداً، فقط، مطلقاً…) تفضح خطأه
  honor     «ﷺ» أو «رضي الله عنه» أو «عليه السلام» داخل خيار
  number    أرقام أو سنوات في أسئلة التاريخ والسيرة (القاعدة: بلا تواريخ ولا أعداد)
  repeat    (ملخص) إجابة تتكرر أكثر من 10 مرات في القسم

الاستعمال:
  python3 tools/audit.py                     كل الفحوص وكل الأقسام
  python3 tools/audit.py --cat poetry,arabic أقسام بعينها
  python3 tools/audit.py --check leak,form   فحوص بعينها
  python3 tools/audit.py --summary           العدد فقط لكل قسم وفحص
"""
import collections, os, re, sys
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tahaddi_data as td

TITLES = [td.norm(x) for x in 'الإمام الشيخ الصحابي الصحابية الملك الأمير السلطان الخليفة سيدنا السيدة القاضي الحافظ العلامة الفقيه النبي الرسول الشاعر المحدث الحكيم'.split()] + [td.norm('أم المؤمنين')]
KUNYA = {td.norm(x) for x in ('أبو', 'أبي', 'أبا', 'أم')}
NASAB = {td.norm(x) for x in ('بن', 'ابن', 'بنت', 'ابنة')}
ABSOLUTE = {td.norm(x) for x in ('دائماً', 'دائما', 'أبداً', 'ابدا', 'فقط', 'مطلقاً', 'مطلقا', 'إطلاقاً', 'اطلاقا', 'قط', 'البتة', 'بتاتاً', 'بتاتا', 'وحده', 'وحدها', 'جميع', 'كافة', 'إلا')}
HONOR = re.compile('ﷺ|صلى الله عليه|رضي الله|عليه السلام|عليها السلام|رحمه الله|رحمها الله')
DIGITS = re.compile(r'[0-9٠-٩]')
NUMWORDS = re.compile(r'(^|\s)(سنة|عام)\s+[0-9٠-٩]')
COMPLETE = re.compile('أكمل|اكمل|تكملة|بقية البيت|عجز البيت|صدر البيت|ما تمام')


PLACE_CATS = {'geography', 'saudi'}  # «ال» جزء من أسماء الأماكن، فلا يُعدّ فرقاً في الصيغة


def feats(opt, cat=''):
    ws = td.words(opt)
    f = set()
    if not ws:
        return f
    n = td.norm(opt)
    if any((' ' + t + ' ') in (' ' + n + ' ') for t in TITLES): f.add('لقب')
    if ws[0] in KUNYA: f.add('كنية')
    if any(w in NASAB for w in ws[1:]) or ws[0] in ('ابن',): f.add('نسب')
    last = ws[-1]
    if 2 <= len(ws) <= 3 and last.startswith('ال') and last.endswith('ي') and len(last) >= 5: f.add('نسبة')
    if ws[0].startswith('ال') and len(ws) <= 3 and cat not in PLACE_CATS: f.add('ال')
    if re.search(r'[()\[\]]', opt): f.add('أقواس')
    if re.search(r'[،,:؛–—-]', opt): f.add('شرح')
    return f


def check(q, cfg):
    out = []
    stem_t = q.stem_text
    a, ws = q.a, q.w
    na = td.norm(a)
    # leak
    if 'leak' in cfg and not COMPLETE.search(stem_t):
        ns = ' ' + td.norm(stem_t) + ' '
        wrong_roots = set().union(*[td.content_roots(w) for w in ws])
        wrong_stems = set().union(*[td.content_stems(w) for w in ws])
        core = re.sub(r'^ال', '', na)
        if len(core) >= 3 and (' ' + na + ' ' in ns or ' ' + core + ' ' in ns or ' ال' + core + ' ' in ns) and not any(td.norm(w) in ns.strip() for w in ws if len(td.norm(w)) >= 3):
            out.append(('leak', f'الإجابة «{a}» بنصها في السؤال'))
        else:
            hit = (td.content_roots(a) & td.content_roots(stem_t)) - wrong_roots
            hit = {h for h in hit if len(h) >= 3}
            # تأكيد: كلمة الإجابة وكلمة السؤال متشابهتا الجذع، لا مجرد هيكل متقارب
            strong = (td.content_stems(a) & td.content_stems(stem_t)) - wrong_stems
            if strong:
                out.append(('leak', 'كلمة من الإجابة في السؤال: ' + '، '.join(sorted(strong))))
            elif hit:
                out.append(('leak', 'جذر من الإجابة في السؤال: ' + '، '.join(sorted(hit))))
    # long
    if 'long' in cfg:
        la, lw = td.vis_len(a), [td.vis_len(w) for w in ws]
        wa, ww = len(td.words(a)), [len(td.words(w)) for w in ws]
        if la > max(lw) * 1.35 and la - max(lw) >= 6:
            out.append(('long', f'الصحيح {la} حرفاً وأطول الخاطئة {max(lw)}'))
        elif wa >= max(ww) + 2:
            out.append(('long', f'الصحيح {wa} كلمات وأطول الخاطئة {max(ww)}'))
    # form
    if 'form' in cfg:
        fa = feats(a, q.cat); fw = [feats(w, q.cat) for w in ws]
        only = {f for f in fa if not any(f in x for x in fw)}
        missing = {f for f in set.intersection(*fw) if f not in fa} if fw else set()
        # «ال» و«شرح» شائعان، فلا يُبلَّغ عنهما إلا مع خيارات قصيرة
        if 'ال' in only and len(td.words(a)) > 2: only.discard('ال')
        if only: out.append(('form', 'في الصحيح وحده: ' + '، '.join(sorted(only))))
        if missing: out.append(('form', 'في الخاطئة كلها وليس في الصحيح: ' + '، '.join(sorted(missing))))
    # absolute
    if 'absolute' in cfg:
        if not set(td.words(a)) & ABSOLUTE:
            bad = [w for w in ws if set(td.words(w)) & ABSOLUTE or td.words(w)[:1] == ['كل']]
            if bad: out.append(('absolute', 'كلمة إطلاق في خيار خاطئ: ' + ' / '.join(bad)))
    # honor
    if 'honor' in cfg:
        hs = [o for o in [a] + ws if HONOR.search(o)]
        if hs: out.append(('honor', 'تعظيم داخل خيار: ' + ' / '.join(hs)))
    # number
    if 'number' in cfg and q.cat in ('history', 'seerah'):
        txt = ' '.join([q.q, a] + ws)
        if DIGITS.search(txt) or NUMWORDS.search(txt):
            out.append(('number', 'رقم في سؤال تاريخ أو سيرة'))
    return out


def main():
    args = sys.argv[1:]
    def opt(name):
        if name in args:
            i = args.index(name)
            return args[i + 1].split(',') if i + 1 < len(args) else []
        return None
    cats = opt('--cat')
    checks = set(opt('--check') or ['leak', 'long', 'form', 'absolute', 'honor', 'number', 'repeat'])
    summary = '--summary' in args
    qs = td.read_questions(cats)
    found = []
    for q in qs:
        for k, msg in check(q, checks):
            found.append((q, k, msg))
    names = {'leak': 'في السؤال', 'long': 'أطول', 'form': 'صيغة', 'absolute': 'إطلاق', 'honor': 'تعظيم', 'number': 'رقم'}
    if not summary:
        for q, k, msg in found:
            print(f'{q.ref()} [{names[k]}] {msg} :: {q.raw[:120]}')
    if 'repeat' in checks:
        by = collections.defaultdict(collections.Counter)
        for q in qs:
            by[q.cat][td.norm_answer(q.a)] += 1
        reps = [(c, a, n) for c, cnt in by.items() for a, n in cnt.items() if n > 10]
        if reps:
            print('\nإجابات تتكرر أكثر من 10 مرات في قسمها:')
            for c, a, n in sorted(reps, key=lambda x: -x[2]):
                print(f'  {c}: «{a}» ×{n}')
    tally = collections.Counter((q.cat, k) for q, k, _ in found)
    print('\nالمجموع:', len(found), file=sys.stderr)
    for (c, k), n in sorted(tally.items()):
        print(f'  {c} [{names[k]}] {n}', file=sys.stderr)


if __name__ == '__main__':
    main()
