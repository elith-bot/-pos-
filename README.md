# 🚀 قالب البداية المتكامل (Flutter + Python Flask + SQLAlchemy)

مشروع أساسي (Boilerplate / Starter Template) يربط بين تطبيق واجهات **Flutter** وسيرفر **Python Flask** مع دعم التبديل السلس بين قواعد البيانات **SQLite** و **MySQL** عبر **SQLAlchemy ORM**.

---

## 📁 هيكل المشروع

```text
كاشير/
├── backend/                  # سيرفر الباك إند بلغة بايثون
│   ├── app.py                # السيرفر ونقاط الاتصال API
│   ├── config.py             # إعدادات قاعدة البيانات والبيئة
│   ├── models.py             # نماذج البيانات (SQLAlchemy ORM)
│   ├── .env                  # ملف متغيرات البيئة واختيار نوع قاعدة البيانات
│   └── requirements.txt      # مكتبات بايثون المطلوبة
├── frontend/                 # تطبيق الواجهة الأمامية بلغة فلاتر
│   ├── lib/
│   │   ├── main.dart         # نقطة انطلاق تطبيق فلاتر
│   │   ├── models/           # كلاس البيانات Item
│   │   ├── services/         # كلاس الاتصال API Service
│   │   └── screens/          # شاشات الواجهة (HomeScreen)
│   └── pubspec.yaml          # إعدادات ومكتبات فلاتر
├── run_backend.bat           # ملف تشغيل السيرفر بضغطة زر
└── run_frontend.bat          # ملف تشغيل تطبيق فلاتر بضغطة زر
```

---

## ⚙️ طريقة التشغيل

### 1️⃣ تشغيل سيرفر الباك إند (Backend)
قم بفتح المجلد واضغط مرتين على `run_backend.bat` أو نفّذ الأمر التالي:
```bash
cd backend
python app.py
```
سيتم تشغيل السيرفر على الرابط: `http://127.0.0.1:5000`

---

### 2️⃣ تشغيل تطبيق الفلاتر (Frontend)
قم بفتح المجلد واضغط مرتين على `run_frontend.bat` أو نفّذ الأمر التالي:
```bash
cd frontend
flutter run -d chrome
# أو لتشغيل كبرنامج Windows مستمر:
# flutter run -d windows
```

---

## 🗄️ كيفية التبديل بين قواعد البيانات (SQLite <-> MySQL)

يمتلك السيرفر نظاماً ديناميكياً للتبديل بين قواعد البيانات من خلال متغير `DATABASE_TYPE` في ملف [backend/.env](file:///c:/Users/Fighter/Desktop/كاشير/backend/.env):

- **للاستخدام المعياري (SQLite):**
  ```env
  DATABASE_TYPE=sqlite
  SQLITE_DB_PATH=app_database.db
  ```
- **للتحويل إلى (MySQL):**
  ```env
  DATABASE_TYPE=mysql
  MYSQL_USER=root
  MYSQL_PASSWORD=your_password
  MYSQL_HOST=localhost
  MYSQL_PORT=3306
  MYSQL_DB=my_flask_db
  ```

كما يمكنك التبديل مباشرة من داخل واجهة تطبيق الفلاتر بالضغط على زر **الإعدادات (⚙️)** واختيار نوع قاعدة البيانات المطلوب!
