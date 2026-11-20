#!/bin/sh
# يجهّز تطبيق الآيفون والآيباد الأصلي (SwiftUI) للبناء:
# ينسخ ملفات الأسئلة من data/ (cats.json وكل ملفات .txt وclubs.json إن وُجد) إلى داخل التطبيق،
# ويضبط رقم نسخة التطبيق (MARKETING_VERSION) من الملف ios/VERSION.
# الاسم باقٍ كما هو لأن سير البناء ورفع TestFlight يستدعيانه.
set -e
cd "$(dirname "$0")/.."
rm -rf ios/App/Data && mkdir -p ios/App/Data
cp data/cats.json ios/App/Data/
for f in data/*.txt; do [ -f "$f" ] && cp "$f" ios/App/Data/; done
if [ -f data/clubs.json ]; then cp data/clubs.json ios/App/Data/; fi
V=$(tr -d ' \r\n' < ios/VERSION)
sed -i.bak -E "s/MARKETING_VERSION: \"[0-9.]+\"/MARKETING_VERSION: \"$V\"/" ios/project.yml && rm -f ios/project.yml.bak
echo "data copied: $(ls ios/App/Data | wc -l | tr -d ' ') files, version $V"
du -sh ios/App/Data
