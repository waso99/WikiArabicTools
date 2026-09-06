# WikiArabicTools

**الإصدار: 1.0.2**

أداة PowerShell لمعالجة روابط ويكيبيديا الإنجليزية وتحويلها إلى روابط عربية اعتمادًا على **Wikidata** وبيانات ويكيبيديا، مع استخدام **Gemini** فقط عندما تكون ترجمة النص الظاهر للرابط مطلوبة فعلًا.

## المزايا

- استخراج روابط ويكيبيديا من Wikitext.
- الحصول على QID من Wikidata/خصائص ويكيبيديا.
- استخدام Cache محلي لتقليل طلبات Wikipedia وWikidata.
- حفظ أسماء Wikidata العربية في Cache، بما في ذلك النتائج السلبية.
- استخدام عنوان ويكيبيديا العربية مباشرة عندما يكون مطابقًا للمصدر.
- استخدام الاسم العربي في Wikidata عند عدم وجود مقالة عربية، وإنشاء `{{Ill-WD2}}` عند توفر الشروط.
- ترجمة النص الظاهر للرابط بواسطة Gemini فقط عند الحاجة.
- Cache مستقل لترجمات Gemini لتجنب إعادة ترجمة النصوص السابقة.
- دعم روابط الأقسام `#Section`.
- إنشاء تقرير بالنتائج والروابط التي لم تُترجم.
- لا يحتوي الإصدار على أي مفتاح API سري.

## المتطلبات

- Windows PowerShell 5.1 أو PowerShell 7+.
- اتصال بالإنترنت عند الحاجة إلى Wikipedia/Wikidata/Gemini.
- مفتاح Gemini API **اختياري**، ويُستخدم فقط عند الحاجة إلى ترجمة النصوص الظاهرة.

> لا تحتاج إلى تثبيت Python أو Node.js أو مكتبات PowerShell خارجية.

## التثبيت على جهاز جديد

1. فك ضغط مجلد الإصدار كاملًا.
2. افتح PowerShell داخل مجلد `WikiArabicTools-v1.0.1`.
3. شغّل:

```powershell
.\SETUP.cmd
```

سيقوم Setup بـ:

- فحص إصدار PowerShell.
- إنشاء مجلدات `Modules` و`Cache` إذا كانت ناقصة.
- إزالة حظر Windows عن ملفات `.ps1` عند الإمكان.
- فحص ترميز ملفات PowerShell.
- التأكد من وجود الملفات الأساسية.
- اكتشاف `GEMINI_API_KEY`.
- إعطائك خيار إدخال مفتاح Gemini وحفظه كمتغير بيئة للمستخدم، دون كتابته داخل المشروع.

### بدون إعداد Gemini الآن

```powershell
.\SETUP.cmd -SkipApiKeyPrompt
```

يمكنك إعداد المفتاح لاحقًا:

```powershell
[Environment]::SetEnvironmentVariable('GEMINI_API_KEY','YOUR_NEW_KEY','User')
```

ثم افتح نافذة PowerShell جديدة.

## التشغيل

### باستخدام `input.wiki`

ضع Wikitext الإنجليزي في:

```text
input.wiki
```

ثم:

```powershell
.\WikiArabicTools.ps1
```

### باستخدام عنوان ويكيبيديا

```powershell
.\WikiArabicTools.ps1 -Title "Dutch Revolt"
```

### باستخدام رابط ويكيبيديا

```powershell
.\WikiArabicTools.ps1 -Url "https://en.wikipedia.org/wiki/Dutch_Revolt"
```

## ملفات النتائج

بعد التشغيل ستجد:

- `output.wiki` — Wikitext الناتج.
- `untranslated-links.txt` — الروابط التي تعذر تحويلها.
- `source-info.txt` — معلومات المصدر وتاريخ المعالجة.

## Cache

يُحفظ Cache داخل:

```text
Cache\WikidataCache.json
Cache\GeminiDisplayCache.json
```

**يفضل الاحتفاظ بمجلد `Cache` عند نقل المشروع إلى جهاز آخر** إذا كنت تريد الاحتفاظ بالبيانات والترجمات التي جُمعت سابقًا.

يمكنك أيضًا حذف Cache يدويًا إذا أردت بدء قاعدة بيانات محلية جديدة؛ سيؤدي ذلك إلى إعادة طلب البيانات من الخدمات عند الحاجة.

## ترتيب اتخاذ القرار

يعمل المشروع بصورة تقريبية بهذا التسلسل:

```text
Wikidata Cache
      ↓
Wikipedia/Wikidata data
      ↓
العنوان العربي الحتمي
      ↓
Gemini translation cache
      ↓
Gemini API (عند الحاجة فقط)
```

وهذا يقلل استدعاءات Gemini ويستفيد من البيانات المخزنة محليًا إلى أقصى حد.

## الأمان

**لا تضع مفتاح Gemini داخل ملفات المشروع أو ZIP.**

استخدم متغير البيئة:

```powershell
[Environment]::SetEnvironmentVariable('GEMINI_API_KEY','YOUR_NEW_KEY','User')
```

إذا كان لديك مفتاح قديم تم إدخاله في ملف أو مشاركته سابقًا، فالأفضل إلغاؤه وإنشاء مفتاح جديد.

## نقل المشروع

لإنشاء نسخة احتياطية قابلة للنقل، اضغط **المجلد كاملًا** بما فيه `Modules` و`Cache` و`README` و`SETUP`.

لا حاجة إلى نقل إعدادات PowerShell الخاصة بالجهاز القديم؛ يكفي إعداد `GEMINI_API_KEY` على الجهاز الجديد.

## بنية المشروع

```text
WikiArabicTools-v1.0.1/
├── .github/
│   └── workflows/
│       └── translate.yml
├── WikiArabicTools.ps1
├── SETUP.ps1
├── VERSION.txt
├── README.md
├── README.txt
├── GEMINI_API_KEY.txt.example
├── Modules/
│   ├── LinkTranslator.ps1
│   ├── Wikidata.ps1
│   ├── WikipediaFetcher.ps1
│   └── WikitextParser.ps1
├── Cache/
│   ├── GeminiDisplayCache.json
│   └── WikidataCache.json
├── input.wiki
├── output.wiki
├── source-info.txt
└── untranslated-links.txt
```

## الإصدار

رقم الإصدار محفوظ في `VERSION.txt`، والإصدار الحالي هو **1.0.1**.



## التشغيل عن بُعد عبر GitHub Actions

يمكن تشغيل WikiArabicTools على خوادم GitHub دون إبقاء جهازك قيد التشغيل. يدعم المستودع التشغيل اليدوي من تبويب **Actions**، كما يمكن تشغيله تلقائيًا عند تحديث `input.wiki`.

### إعداد مفتاح Gemini

لا تضع مفتاح Gemini داخل المستودع.

1. افتح مستودع GitHub ثم **Settings → Secrets and variables → Actions**.
2. أنشئ **Repository secret** باسم:

```text
GEMINI_API_KEY
```

3. ألصق مفتاح Gemini في قيمة السر واحفظه.

إذا لم تضف المفتاح، فسيستمر البرنامج في معالجة الروابط التي يمكن تحويلها حتميًا، بينما تُترك الترجمات التي تحتاج Gemini دون تغيير.

### التشغيل اليدوي

1. ارفع المشروع إلى GitHub.
2. افتح تبويب **Actions**.
3. اختر **WikiArabicTools**.
4. اضغط **Run workflow**.
5. اختر المصدر:
   - `input`: معالجة الملف `input.wiki` الموجود في المستودع.
   - `title`: جلب مقالة من ويكيبيديا الإنجليزية بواسطة العنوان.
   - `url`: جلب مقالة من ويكيبيديا الإنجليزية بواسطة الرابط.
6. عند اختيار `title` أو `url` أدخل القيمة المطلوبة.
7. اختر نموذج Gemini وحجم الدفعة عند الحاجة.

بعد انتهاء التشغيل تُحفظ النتائج بطريقتين:

1. **مباشرة في المستودع**:
   - `output.wiki`
   - `untranslated-links.txt`
   - `source-info.txt`

2. **في Artifacts** تحت اسم قريب من:

```text
WikiArabicTools-results-<run-number>
```

ويتضمن الـArtifact أيضًا ملفات `Cache/*.json`.

### التشغيل التلقائي

أي `push` يغيّر `input.wiki` أو ملفات البرنامج الأساسية (`WikiArabicTools.ps1` أو `Modules/`) يشغّل Workflow تلقائيًا.

### ملاحظات عن Cache

يستخدم GitHub Actions Cache للاحتفاظ ببيانات `Cache` بين التشغيلات وتقليل الطلبات المتكررة إلى الخدمات الخارجية. كما تُرفق ملفات Cache الناتجة مع نتائج كل تشغيل.

### الأمان

يستخدم Workflow صلاحية `contents: write` لأن وظيفته نشر ملفات النتائج تلقائيًا داخل المستودع. ولا تُستخدم هذه الصلاحية إلا في هذا الـWorkflow. مفتاح Gemini يمر إلى التشغيل من خلال GitHub Actions Secret ولا يُكتب في ملفات المشروع.

ملفات النتائج موجودة في `.gitignore` لمنع إضافتها بالخطأ أثناء العمل المحلي، ويستخدم Workflow الأمر `git add -f` فقط عند النشر الآلي للنتائج.
