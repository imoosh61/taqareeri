# تقاريري — تطبيق التقارير الرسمية A4 (iPhone)

تطبيق SwiftUI لإنشاء التقارير والخطابات الرسمية بمقاس A4: ترويسة (شعار + بيانات الجهة + التاريخ الهجري/الميلادي والرقم)، مكتبة إطارات، محرر نصوص عربي بمعاينة حية للصفحات، توقيع وختم، ثم تصدير PDF متجهي واحد ومشاركته.

**تطوير:** Mohammad Hakami - imoosh  
© جميع الحقوق محفوظة.

## البناء عبر GitHub (بدون ماك)

1. أنشئ مستودعاً جديداً على GitHub وارفع **كل محتويات** هذا المجلد (بما فيها مجلد `.github`).
   - تأكد أن الملف `.github/workflows/build-ios.yml` ظهر في المستودع؛ إن لم يظهر أنشئه يدوياً من «Add file → Create new file» بنفس المسار والصق محتواه.
2. افتح تبويب **Actions** → سيعمل «Build iPhone IPA» تلقائياً (أو اضغط Run workflow).
3. بعد النجاح (≈ 5–10 دقائق) افتح التشغيل ونزّل **OfficialReports-unsigned-ipa** من قسم Artifacts.
4. فك الضغط ووقّع `OfficialReports-unsigned.ipa` بشهادتك (Sideloadly / ESign / غيرها) ثم ثبّته.
5. لإصدار رسمي: أنشئ Tag مثل `v1.0.0` فيُرفع الـ IPA تلقائياً في صفحة Releases.

> الخطوط Amiri وTajawal وScheherazade New (رخصة OFL) تُنزَّل تلقائياً أثناء البناء.

## البنية (MVVM)

```
App/
  Models/      Report, BodyDocument, FrameStyle, ReportFont
  Services/    ReportStore, TemplateStore, FontRegistry, ImageProcessor, SpeechDictation, BackupService
  Rendering/   BodyStyler, PageLayout, Paginator (TextKit), PageRenderer, FrameDrawer, PDFExporter
  Editor/      ReportEditorViewModel, RichTextController, RichTextEditor
  Features/    Home, Header, Frames, Writing, Signature, Preview, Library
```

- **التقسيم إلى صفحات**: TextKit يوزّع النص على حاويات بحجم منطقة الكتابة لكل صفحة، فالمعاينة وملف PDF يستخدمان نفس التخطيط تماماً.
- **PDF متجهي**: النص يُرسم كخطوط حقيقية والإطارات كمسارات Core Graphics.
- **فاصل الصفحة**: رمز U+000C داخل النص؛ والأقسام بين الفواصل قابلة لإعادة الترتيب.

## ملاحظات

- خط Traditional Arabic مملوك لمايكروسوفت ولا يمكن تضمينه؛ يمكن استيراد نسختك المرخّصة من «المكتبة ← الخطوط».
- الحفظ السحابي المباشر (iCloud) يتطلب حساب مطوّر مدفوع؛ البديل المدمج: «النسخ الاحتياطي» ثم الحفظ في iCloud Drive، كما تظهر المسودات في تطبيق «الملفات».
- الإملاء الصوتي يتطلب اتصالاً بالإنترنت وأذونات الميكروفون والتعرّف على الكلام.
