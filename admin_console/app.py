"""Unified Local Vendor Admin Console: Single Window for Edition Export, Auto-Key & Offline Activation."""
import os
import sys
import uuid
import threading
import subprocess
import shutil
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox, filedialog, simpledialog

ROOT = Path(sys.executable).resolve().parent / 'build-kit' if getattr(sys, 'frozen', False) else Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'backend'))
sys.path.insert(0, str(ROOT / 'packaging'))
from service import unlock_key, create_edition, issue_license, find_edition
from key_store import managed_key
from license_protocol import parse_request
from cryptography.hazmat.primitives import serialization
from system_settings import preset, PRESETS, TAB_LABELS
from role_access import BUILTINS, DEFAULTS, CAPABILITIES, GROUPS, normalize_permissions


class AdminApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('منصة إدارة نسخ الكاشير — لوحة الأدمن المركزية')
        self.geometry('980x880')
        self.minsize(900, 750)
        self.configure(bg='#F8FAFC')

        self.root_dir = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'POS Admin'
        self.root_dir.mkdir(parents=True, exist_ok=True)
        self.key_path = self.root_dir / 'signing-private.pem'
        self.key_pass_path = self.root_dir / '.key_secret'
        self.key = None
        self.edition = None

        self.fields = {}
        self.tabs = {}
        self.roles = [dict(id=k, name=v, permissions=sorted(DEFAULTS[k] & set(CAPABILITIES))) for k, v in BUILTINS.items()]

        # Apply Modern TTK Styles
        self.style = ttk.Style(self)
        try:
            self.style.theme_use('clam')
        except Exception:
            pass
        self.style.configure('TLabelframe', background='#FFFFFF', padding=12)
        self.style.configure('TLabelframe.Label', font=('Segoe UI', 11, 'bold'), foreground='#0F172A', background='#FFFFFF')
        self.style.configure('TLabel', background='#FFFFFF', font=('Segoe UI', 10))
        self.style.configure('Header.TLabel', font=('Segoe UI', 15, 'bold'), foreground='#0F172A', background='#F8FAFC')
        self.style.configure('Primary.TButton', font=('Segoe UI', 12, 'bold'), foreground='#FFFFFF', background='#0284C7', padding=10)
        self.style.map('Primary.TButton', background=[('active', '#0369A1'), ('disabled', '#94A3B8')])
        self.style.configure('Action.TButton', font=('Segoe UI', 10, 'bold'), padding=6)

        # Header Title
        header_frame = tk.Frame(self, bg='#F8FAFC')
        header_frame.pack(fill='x', padx=25, pady=(15, 10))
        title = ttk.Label(header_frame, text='تجهيز وتصدير نسخ الكاشير والتفعيل الأوفلاين للزبائن', style='Header.TLabel', anchor='e')
        title.pack(fill='x')
        subtitle = tk.Label(header_frame, text='أدخل بيانات الزبون واختر نوع النشاط، ثم اضغط على زر التصدير ليتم إنشاء المفتاح والنسخة الموقّعة تلقائياً.', font=('Segoe UI', 9), fg='#64748B', bg='#F8FAFC', anchor='e')
        subtitle.pack(fill='x', pady=(2, 0))

        # Main Scrollable Area or Canvas
        canvas = tk.Canvas(self, bg='#F8FAFC', highlightthickness=0)
        scrollbar = ttk.Scrollbar(self, orient='vertical', command=canvas.yview)
        self.main_content = tk.Frame(canvas, bg='#F8FAFC')
        self.main_content.bind('<Configure>', lambda e: canvas.configure(scrollregion=canvas.bbox('all')))
        content_window = canvas.create_window((0, 0), window=self.main_content, anchor='nw', width=930)
        canvas.bind('<Configure>', lambda e: canvas.itemconfigure(content_window, width=e.width))
        canvas.configure(yscrollcommand=scrollbar.set)

        scrollbar.pack(side='left', fill='y')
        canvas.pack(side='right', fill='both', expand=True, padx=(10, 20), pady=5)

        # 1. Customer & Owner Section
        sec_customer = ttk.LabelFrame(self.main_content, text='  1. معلومات الزبون  ')
        sec_customer.pack(fill='x', pady=8)

        # Customer fields grid
        self._add_grid_field(sec_customer, 'customer_name', 'اسم الزبون:', row=0, col=0)
        self._add_grid_field(sec_customer, 'phone', 'رقم هاتف الزبون:', row=0, col=1)
        self._add_grid_field(sec_customer, 'address', 'المحافظة والعنوان الكامل:', row=1, col=0)
        self._add_grid_field(sec_customer, 'notes', 'الملاحظات والاتفاق:', row=1, col=1)

        sec_owner = ttk.LabelFrame(self.main_content, text='  2. معلومات المالك والأدمن — الحساب الأول  ')
        sec_owner.pack(fill='x', pady=8)
        self._add_grid_field(sec_owner, 'owner_name', 'اسم المالك (صاحب الحساب الأول):', row=0, col=0)
        self._add_grid_field(sec_owner, 'owner_phone', 'هاتف المالك (اسم المستخدم الأول):', row=0, col=1)
        self._add_grid_field(sec_owner, 'owner_password', 'كلمة مرور الحساب الأول (8 أحرف على الأقل):', row=1, col=0, secret=True)
        ttk.Label(sec_owner, text='يُنشأ الحساب الأول بدور مالك لإدارة الكاشير.', anchor='e').grid(row=2, column=0, columnspan=2, sticky='ew', padx=10, pady=5)

        sec_cashier = ttk.LabelFrame(self.main_content, text='  3. معلومات الكاشير وإعداداته الافتراضية  ')
        sec_cashier.pack(fill='x', pady=8)
        self._add_grid_field(sec_cashier, 'name', 'اسم المتجر / النشاط (يظهر بالنظام والملفات):', row=0, col=0)
        self._add_grid_field(sec_cashier, 'vendor_name', 'اسم شركتنا:', row=0, col=1)
        self.fields['vendor_name'].set('moon')

        # 2. Activity & Presets Section
        sec_activity = tk.Frame(sec_cashier, bg='#FFFFFF')
        sec_activity.grid(row=1, column=0, columnspan=2, sticky='ew', pady=8)

        row_act = tk.Frame(sec_activity, bg='#FFFFFF')
        row_act.pack(fill='x', pady=5)

        self.activity_var = tk.StringVar(value='سوبرماركت / متجر تجزئة')
        ttk.Label(row_act, text='نوع النشاط الافتراضي:').pack(side='right', padx=10)
        self.activity_combo = ttk.Combobox(row_act, state='readonly', values=list(PRESETS.values()), width=28)
        self.activity_combo.current(list(PRESETS).index('supermarket'))
        self.activity_combo.pack(side='right', padx=5)
        self.activity_combo.bind('<<ComboboxSelected>>', self._on_preset_selected)

        ttk.Label(row_act, text='مدة تسجيل الدخول (بالساعات):').pack(side='right', padx=(30, 10))
        self.session_hours_var = tk.StringVar(value='24')
        ttk.Entry(row_act, textvariable=self.session_hours_var, width=8, justify='center').pack(side='right')

        ttk.Label(sec_activity, text='بعد هذه المدة يحتاج الموظف تسجيل الدخول مجدداً. لا تؤثر على الدوام أو ترخيص النسخة.').pack(anchor='e', pady=4)

        # Checkboxes for Tabs in one row
        tabs_frame = tk.Frame(sec_activity, bg='#FFFFFF')
        tabs_frame.pack(fill='x', pady=(10, 5))
        ttk.Label(tabs_frame, text='التبويبات المفعّلة:').pack(side='right', padx=10)

        for key, label in reversed(list(TAB_LABELS.items())):
            var = tk.BooleanVar(value=(key != 'tables')) # By default tables hidden for supermarket
            self.tabs[key] = var
            cb = ttk.Checkbutton(tabs_frame, text=label, variable=var)
            cb.pack(side='right', padx=8)

        role_bar = tk.Frame(sec_cashier, bg='#FFFFFF'); role_bar.grid(row=2, column=0, columnspan=2, sticky='ew', pady=8)
        self.role_combo = ttk.Combobox(role_bar, state='readonly', values=[r['name'] for r in self.roles]); self.role_combo.current(0); self.role_combo.pack(side='right')
        ttk.Button(role_bar, text='تعديل صلاحيات الدور', command=self.edit_role).pack(side='right', padx=6)
        ttk.Button(role_bar, text='إضافة دور', command=lambda: self.edit_role(new=True)).pack(side='right', padx=6)
        ttk.Button(role_bar, text='نسخة احتياطية للمفتاح', command=self.backup_key).pack(side='left', padx=6)

        # 3. Big Unified Action Button
        action_frame = tk.Frame(self.main_content, bg='#F8FAFC')
        action_frame.pack(fill='x', pady=15)

        self.btn_export = ttk.Button(
            action_frame,
            text='🚀 إنشاء المفتاح تلقائياً وتصدير نسخة تنصيب EXE للزبون',
            style='Primary.TButton',
            command=self.unified_export
        )
        self.btn_export.pack(fill='x', ipady=6)

        self.status_label = tk.Label(action_frame, text='جاهز لتصدير النسخة.', font=('Segoe UI', 10), fg='#0284C7', bg='#F8FAFC', anchor='center')
        self.status_label.pack(fill='x', pady=5)

        # 4. Activation Section (Direct in the same window)
        sec_act = ttk.LabelFrame(self.main_content, text='  4. تفعيل نسخة الزبون (أوفلاين بواسطة كود طلب التفعيل)  ')
        sec_act.pack(fill='x', pady=8)

        tk.Label(sec_act, text='الصق كود طلب التفعيل الظاهر على شاشة جهاز الزبون، ثم اضغط زر "إصدار رمز التفعيل":', font=('Segoe UI', 9), bg='#FFFFFF', anchor='e').pack(fill='x', pady=(2, 6))

        req_row = tk.Frame(sec_act, bg='#FFFFFF')
        req_row.pack(fill='x', pady=4)
        self.req_entry = ttk.Entry(req_row, font=('Consolas', 10), justify='left')
        self.req_entry.pack(side='right', fill='x', expand=True, padx=(10, 0))

        ttk.Button(req_row, text='🔑 إصدار رمز التفعيل لهذا الجهاز', style='Action.TButton', command=self.quick_activate).pack(side='right', padx=5)

        tk.Label(sec_act, text='رمز التفعيل الموقّع الممنوح للزبون:', font=('Segoe UI', 9), bg='#FFFFFF', anchor='e').pack(fill='x', pady=(8, 2))
        res_row = tk.Frame(sec_act, bg='#FFFFFF')
        res_row.pack(fill='x', pady=4)
        self.res_entry = ttk.Entry(res_row, font=('Consolas', 10), justify='left')
        self.res_entry.pack(side='right', fill='x', expand=True, padx=(10, 0))
        ttk.Button(res_row, text='📋 نسخ رمز التفعيل', style='Action.TButton', command=self.copy_token).pack(side='right', padx=5)

        # Keys are opened only when the operator requests export or signing.

    def _add_grid_field(self, parent, key, label_text, row, col, secret=False):
        f = tk.Frame(parent, bg='#FFFFFF')
        f.grid(row=row, column=col, sticky='nsew', padx=10, pady=5)
        parent.grid_columnconfigure(col, weight=1)

        lbl = ttk.Label(f, text=label_text, anchor='e')
        lbl.pack(fill='x')
        var = tk.StringVar()
        ent = ttk.Entry(f, textvariable=var, justify='right', show='•' if secret else '')
        ent.pack(fill='x', pady=2)
        self.fields[key] = var

    def _on_preset_selected(self, _=None):
        name = list(PRESETS.keys())[self.activity_combo.current()]
        p = preset(name)
        for k, v in p['tabs'].items():
            if k in self.tabs:
                self.tabs[k].set(v)

    def _ensure_key_ready(self):
        if self.key is not None: return True
        try:
            if self.key_path.exists() and not self.key_pass_path.exists():
                password = simpledialog.askstring('مفتاح الإدارة', 'كلمة مرور المفتاح الأصلي:', show='*', parent=self)
                if password is None: return False
                self.key = unlock_key(self.key_path, password)
            else:
                self.key = managed_key(self.root_dir)
            return True
        except Exception as error:
            messagebox.showerror('تعذر فتح المفتاح', str(error), parent=self)
            return False

    def backup_key(self):
        if not self._ensure_key_ready(): return
        password = simpledialog.askstring('نسخة احتياطية', 'اختر كلمة مرور للنسخة الاحتياطية (12 حرفاً على الأقل):', show='*', parent=self)
        if password is None: return
        if len(password) < 12:
            messagebox.showerror('كلمة المرور', 'استخدم 12 حرفاً على الأقل.', parent=self); return
        path = filedialog.asksaveasfilename(parent=self, defaultextension='.pem', initialfile='pos-signing-backup.pem')
        if not path: return
        try:
            Path(path).write_bytes(self.key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                serialization.BestAvailableEncryption(password.encode('utf-8'))))
            messagebox.showinfo('تم الحفظ', 'احفظ هذه النسخة وكلمة مرورها بمكان آمن. تحتاجهما عند نقل برنامج الأدمن إلى جهاز آخر.', parent=self)
        except Exception as error: messagebox.showerror('تعذر الحفظ', str(error), parent=self)

    def edit_role(self, new=False):
        role = dict(id='role_'+uuid.uuid4().hex[:12], name='', permissions=[]) if new else self.roles[self.role_combo.current()]
        window = tk.Toplevel(self); window.title('الدور والصلاحيات'); window.geometry('650x650'); window.grab_set()
        name = tk.StringVar(value=role['name']); ttk.Entry(window, textvariable=name, justify='right').pack(fill='x', padx=15, pady=10)
        canvas = tk.Canvas(window); scroll = ttk.Scrollbar(window, orient='vertical', command=canvas.yview)
        scroll.pack(side='right', fill='y'); canvas.pack(fill='both', expand=True)
        canvas.configure(yscrollcommand=scroll.set)
        inner = ttk.Frame(canvas); canvas.create_window((0,0), window=inner, anchor='nw')
        inner.bind('<Configure>', lambda _: canvas.configure(scrollregion=canvas.bbox('all')))
        checks = {}
        for group, permissions in GROUPS.items():
            ttk.Label(inner, text=group, font=('Segoe UI',12,'bold')).pack(anchor='e', pady=10)
            for key, label in permissions.items():
                checks[key] = tk.BooleanVar(value=key in role['permissions'])
                ttk.Checkbutton(inner, text=label, variable=checks[key]).pack(anchor='e')
        def save():
            if not name.get().strip(): return
            updated = dict(id=role['id'], name=name.get().strip(), permissions=sorted(normalize_permissions([k for k,v in checks.items() if v.get()])))
            if new: self.roles.append(updated)
            else: self.roles[self.role_combo.current()] = updated
            self.role_combo.config(values=[r['name'] for r in self.roles]); self.role_combo.current(0)
            window.destroy()
        ttk.Button(window, text='حفظ الدور', command=save).pack(pady=10)

    def unified_export(self):
        """Unified One-Click Export: Verify, Auto-Sign Edition, and Build/Export."""
        if not self._ensure_key_ready(): return
        values = {k: v.get().strip() for k, v in self.fields.items()}

        if not values['customer_name']:
            messagebox.showwarning('تنبيه', 'يرجى إدخال اسم الزبون.', parent=self)
            return
        if not values['name']:
            messagebox.showwarning('تنبيه', 'يرجى إدخال اسم المتجر / النشاط.', parent=self)
            return
        if not values['phone']:
            messagebox.showwarning('تنبيه', 'يرجى إدخال رقم هاتف الزبون.', parent=self)
            return
        if not values['owner_name']:
            messagebox.showwarning('تنبيه', 'أدخل اسم المالك.', parent=self); return
        if not values['owner_phone']:
            messagebox.showwarning('تنبيه', 'يرجى إدخال رقم هاتف المالك (اسم المستخدم الأول).', parent=self)
            return
        if len(values['owner_password']) < 8:
            messagebox.showwarning('تنبيه', 'يرجى إدخال كلمة مرور المالك (8 أحرف على الأقل).', parent=self)
            return

        preset_key = list(PRESETS.keys())[self.activity_combo.current()]
        try:
            hours = int(self.session_hours_var.get().strip() or '24')
        except ValueError:
            hours = 24

        settings = preset(preset_key)
        settings.update(
            business_name=values['name'],
            business_phone=values['phone'],
            business_address=values['address'],
            tabs={k: v.get() for k, v in self.tabs.items()},
            session_hours=hours
        )

        self.status_label.config(text='جارٍ إنشاء النسخة وتوقيع المفتاح رقمياً…', fg='#0284C7')
        self.update()

        try:
            # 1. Create signed edition
            self.edition = create_edition(
                self.root_dir / 'editions',
                self.key,
                {k: values[k] for k in ['name', 'customer_name', 'phone', 'address', 'notes']},
                dict(name=values['owner_name'], phone=values['owner_phone'], password=self.fields['owner_password'].get()),
                settings,
                self.roles, vendor_name=values['vendor_name']
            )

            self.fields['owner_password'].set('')
            self.btn_export.config(state='disabled')
            self.status_label.config(text='جارٍ بناء ملف التنصيب… قد يستغرق عدة دقائق.')
            edition = self.edition
            def build_worker():
                try:
                    python = shutil.which('python') if getattr(sys, 'frozen', False) else sys.executable
                    if not python: raise RuntimeError('يلزم Python وأدوات البناء على جهاز الأدمن لإنشاء ملفات التنصيب.')
                    log = self.root_dir / 'last-build.log'
                    with log.open('w', encoding='utf-8') as output:
                        result = subprocess.run([python, str(ROOT / 'packaging' / 'build_customer.py'), str(edition)],
                            stdout=output, stderr=subprocess.STDOUT, cwd=ROOT,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
                    if result.returncode:
                        raise RuntimeError('لم يكتمل ملف التنصيب. بيانات النسخة محفوظة. راجع سجل البناء: ' + str(log))
                    from distribution_names import application_name
                    from license_protocol import verify, public_pem
                    deployment = verify((edition / 'deployment.pos').read_text(encoding='utf-8'), public_pem(self.key), 'deployment')
                    out_dir = ROOT / 'dist' / 'customers' / application_name(deployment)
                    expected = out_dir / (application_name(deployment) + '-Setup.exe')
                    if not expected.is_file(): raise RuntimeError('لم يتم العثور على ملف التنصيب الناتج.')
                    self.after(0, lambda: self.build_finished(str(expected), None))
                except Exception as error:
                    self.after(0, lambda message=str(error): self.build_finished(None, message))
            threading.Thread(target=build_worker, daemon=True).start()

        except Exception as error:
            self.status_label.config(text=f'حدث خطأ: {error}', fg='#DC2626')
            messagebox.showerror('تعذر التصدير', str(error), parent=self)

    def build_finished(self, output, error):
        self.btn_export.config(state='normal')
        if error:
            self.status_label.config(text='لم يكتمل بناء ملف التنصيب', fg='#DC2626')
            messagebox.showerror('نتيجة البناء', error, parent=self)
        else:
            self.status_label.config(text='تم إنشاء ملف التنصيب EXE', fg='#16A34A')
            messagebox.showinfo('اكتمل البناء', output, parent=self)
            os.startfile(str(Path(output).parent))

    def quick_activate(self):
        """Issue offline license using customer hardware request code."""
        req = self.req_entry.get().strip()
        if not req:
            messagebox.showwarning('تنبيه', 'يرجى لصق كود طلب التفعيل أولاً.', parent=self)
            return

        if not self._ensure_key_ready(): return
        try:
            request = parse_request(req)
            self.edition = find_edition(req, self.key, [self.root_dir / 'editions', ROOT / 'dist' / 'customers', ROOT.parent / 'customers'])
            if self.edition is None:
                choose = messagebox.askyesno('بيانات نسخة الزبون غير موجودة',
                    'كود الطلب صحيح، لكن بيانات هذه النسخة غير موجودة في سجل الأدمن الحالي.\nقد تكون النسخة صادرة من جهاز أو حساب ويندوز آخر.\n\nتحتاج ملف deployment.pos الأصلي ومفتاح التوقيع الذي أصدر النسخة.\nهل تريد استيراد ملف بيانات النسخة الآن؟', parent=self)
                if not choose: return
                path = filedialog.askopenfilename(parent=self, title='استيراد deployment.pos الأصلي', initialdir=self.root_dir / 'editions', filetypes=[('POS edition', '*.pos')])
                if not path: return
                from license_protocol import verify, public_pem
                payload = verify(Path(path).read_text(encoding='utf-8'), public_pem(self.key), 'deployment')
                if payload['edition_id'] != request['edition_id']:
                    raise ValueError('هذا الملف يخص نسخة أخرى. اختر ملف النسخة المطابقة لكود الطلب.')
                self.edition = self.root_dir / 'editions' / request['edition_id']
                self.edition.mkdir(parents=True, exist_ok=True)
                import shutil
                shutil.copyfile(path, self.edition / 'deployment.pos')
        except Exception as error:
            messagebox.showerror('كود غير صالح', str(error), parent=self); return

        try:
            token = issue_license(self.edition, req, self.key, None)
            self.res_entry.delete(0, 'end')
            self.res_entry.insert(0, token)
            messagebox.showinfo('تم التفعيل', 'تم توليد رمز التفعيل الموقّع بنجاح لهذا الجهاز.\nاضغط زر "نسخ رمز التفعيل" وأرسله للزبون.', parent=self)
        except Exception as error:
            messagebox.showerror('خطأ في التفعيل', f'تعذر إصدار الترخيص: {error}', parent=self)

    def copy_token(self):
        token = self.res_entry.get().strip()
        if token:
            self.clipboard_clear()
            self.clipboard_append(token)
            messagebox.showinfo('تم النسخ', 'تم نسخ رمز التفعيل إلى الحافظة بنجاح.', parent=self)


if __name__ == '__main__':
    AdminApp().mainloop()
