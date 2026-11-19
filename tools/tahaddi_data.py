"""مكتبة مشتركة لأدوات «تحدّي»: قراءة سجل الأقسام (data/cats.json)، وتحليل أسطر الأسئلة،
وتطبيع العربية وتجذيرها تجذيراً خفيفاً. تستعملها validate.py وaudit.py وdupes.py وassign_ids.py."""
import json, os, re
from dataclasses import dataclass, field

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
DATA = os.path.join(ROOT, 'data')
CATS_JSON = os.path.join(DATA, 'cats.json')


def load_cats():
    with open(CATS_JSON, encoding='utf8') as f:
        return json.load(f)


def save_cats(reg):
    with open(CATS_JSON, encoding='utf8') as f:
        old = f.read()
    # نحافظ على شكل الملف (سطر لكل قسم)
    lines = ['{', f'  "_": {json.dumps(reg.get("_", ""), ensure_ascii=False)},', f'  "format": {reg.get("format", 1)},', '  "categories": [']
    cs = reg['categories']
    for i, c in enumerate(cs):
        lines.append('    ' + json.dumps(c, ensure_ascii=False) + (',' if i < len(cs) - 1 else ''))
    lines += ['  ]', '}', '']
    new = '\n'.join(lines)
    if new != old:
        with open(CATS_JSON, 'w', encoding='utf8') as f:
            f.write(new)


def categories():
    return load_cats()['categories']


# ---------- التطبيع ----------
DIAC = re.compile(r'[ً-ْٰـ]')
PUNCT = re.compile(r'[«»"“”()\[\].,:؛;؟?!،\-–—/\\…*]|\\n')
AR_DIGITS = str.maketrans('٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789')


def norm(s):
    """تطبيع حرفي: بلا تشكيل، والهمزات ألفاً، والياء والتاء المربوطة، وبلا ترقيم."""
    s = DIAC.sub('', s)
    s = PUNCT.sub(' ', s)
    s = s.replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا').replace('ٱ', 'ا').replace('ى', 'ي').replace('ة', 'ه').replace('ؤ', 'و').replace('ئ', 'ي')
    return re.sub(r'\s+', ' ', s).strip()


def norm_answer(s):
    """مطابق لتطبيع الإجابة في logic.js (normAns)."""
    s = DIAC.sub('', s)
    s = re.sub(r'[«»"()]', '', s)
    s = s.replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا').replace('ٱ', 'ا').replace('ى', 'ي').replace('ة', 'ه')
    s = re.sub(r'\s+', ' ', s).strip()
    s = re.sub(r'^سوره ', '', s)
    s = re.sub(r'^ال', '', s).strip()
    return s


STOP = set(norm(w) for w in '''
من ما ماذا متى اين كيف كم لماذا هل في على عن الى إلى اي أي التي الذي الذين اللذان اللتان هو هي هم هن كان كانت يكون تكون ذلك تلك هذا هذه هؤلاء مع بين قال قالت
بن ابن بنت ابو أبو ابي أبي ام أم عبد الله سورة سوره كتاب صاحب صاحبة اول أول آخر اخر اسم معنى ثم او أو لا لم لن ليس كل بعد قبل عند يوم و ف ب ك ل
القائل البيت وزن الشهير المشهور المشهورة الشهيرة تقع يقع دولة مدينة عاصمة عاصمه يسمى تسمى سمي سميت يطلق تطلق اطلق لقب يلقب لقبه كنية يكنى اشتهر اشتهرت عرف عرفت يعرف تعرف
فيه فيها منه منها له لها به بها اليه اليها عليه عليها عنه عنها حتى إذا اذا إن ان أن قد لقد ليست غير سوى ضد مثل نفس ذات
رضي عنه عنها عنهم عليه السلام صلى وسلم ﷺ تعالى رحمه
'''.split())

PREFIXES = ('وبال', 'وكال', 'فبال', 'وال', 'بال', 'فال', 'كال', 'لل', 'ال', 'و', 'ف', 'ب', 'ل', 'ك')
SUFFIXES = ('يات', 'ات', 'ون', 'ين', 'ان', 'تين', 'تان', 'يه', 'ية', 'ه', 'ي', 'ها', 'هم', 'هن', 'كم', 'نا', 'وا', 'تم')


def stem(w):
    """تجذير خفيف: يحذف أشهر السوابق واللواحق ما بقي من الكلمة ثلاثة أحرف."""
    w = norm(w)
    for p in PREFIXES:
        if w.startswith(p) and len(w) - len(p) >= 3:
            w = w[len(p):]
            break
    for s in SUFFIXES:
        if w.endswith(s) and len(w) - len(s) >= 3:
            w = w[:-len(s)]
            break
    return w


def root(w):
    """هيكل تقريبي للجذر: الجذع بلا حروف المد في وسطه (هاجر/هجرة → هجر، مكتوب/كتاب → كتب تقريباً)."""
    s = stem(w)
    if len(s) <= 3:
        return s
    core = s[0] + re.sub('[اوي]', '', s[1:-1]) + s[-1]
    if core.startswith('م') and len(core) >= 4:  # اسم المفعول والمكان: مكتوب، مسجد
        core = core[1:]
    if core.startswith('ت') and len(core) >= 4:  # تفعيل/تفاعل
        core = core[1:]
    return core if len(core) >= 3 else s


def words(s):
    return [w for w in norm(s).split() if w]


STOP_STEMS = None


def _content(w):
    global STOP_STEMS
    if STOP_STEMS is None:
        STOP_STEMS = {stem(x) for x in STOP} | STOP
    st = stem(w)
    return len(st) >= 3 and w not in STOP and st not in STOP_STEMS


def content_stems(s):
    return {stem(w) for w in words(s) if _content(w)}


def content_roots(s):
    return {root(w) for w in words(s) if _content(w)}


def vis_len(s):
    return len(DIAC.sub('', s).replace(' ', ''))


# ---------- تحليل الأسطر ----------
@dataclass
class Q:
    cat: str
    file: str
    line: int
    raw: str
    d: str
    q: str
    a: str
    w: list
    id: str = ''
    keys: list = field(default_factory=list)
    nfields: int = 0

    @property
    def stem_text(self):
        """نص السؤال للبحث: في «من أنا؟» التلميحات كلها."""
        return self.q.replace(';;', ' ')

    def ref(self):
        return f'{self.cat}:{self.line}' + (f' ({self.id})' if self.id else '')


def parse_keys(s):
    return [k.strip() for k in re.split('[,،]', s or '') if k.strip()]


def read_questions(cat_filter=None, strict=False):
    """يعيد قائمة Q من كل ملفات الأقسام. الأسطر ذات الحقول الناقصة تُهمل هنا (validate.py يبلّغ عنها)."""
    out = []
    for c in categories():
        if cat_filter and c['key'] not in cat_filter:
            continue
        path = os.path.join(ROOT, c['file'])
        if not os.path.exists(path):
            continue
        with open(path, encoding='utf8') as f:
            for i, raw in enumerate(f, 1):
                l = raw.rstrip('\n').strip()
                if not l or l.startswith('#'):
                    continue
                p = [x.strip() for x in l.split('|')]
                if len(p) < 6 or (strict and len(p) > 8):
                    continue
                out.append(Q(cat=c['key'], file=c['file'], line=i, raw=l, d=p[0].translate(AR_DIGITS), q=p[1], a=p[2], w=p[3:6],
                             id=p[6] if len(p) > 6 else '', keys=parse_keys(p[7]) if len(p) > 7 else [], nfields=len(p)))
    return out
