from datetime import datetime
from functools import wraps
import re
import json
from flask import request, jsonify, g
from sqlalchemy.exc import IntegrityError
from models import db, Expense, User
from hr_models import Staff, StaffContract, Attendance, Payroll, FixedExpense
from transactions import number
from security import failure, POLICY


def money(value):
    value = number(value)
    if value < 0 or value > 1e12:
        raise ValueError('المبلغ يجب أن يكون موجباً أو صفراً وضمن الحد المسموح.')
    return round(value, 2)


def text(value, limit=150, required=False):
    value = str(value or '').strip()
    if len(value) > limit or (required and not value):
        raise ValueError('تحقق من الحقول المطلوبة وطول النص.')
    return value


def period(value, monthly=False):
    value = str(value or '')
    pattern, fmt = (r'\d{4}-\d{2}', '%Y-%m') if monthly else (r'\d{4}-\d{2}-\d{2}', '%Y-%m-%d')
    if not re.fullmatch(pattern, value):
        raise ValueError('صيغة التاريخ غير صحيحة.')
    datetime.strptime(value, fmt)
    return value


def contract_terms(d, start):
    kind = d.get('pay_type', 'monthly')
    if kind not in ['monthly', 'daily', 'hourly']: raise ValueError('نوع الأجر غير صحيح.')
    month = period(d.get('effective_month', start[:7]), True)
    if month < start[:7]: raise ValueError('العقد لا يسبق تاريخ التعيين.')
    workdays = str(d.get('workdays', '0,1,2,3,4,5')).replace(' ', '')
    if not re.fullmatch(r'[0-6](,[0-6])*', workdays): raise ValueError('أيام الدوام أرقام من 0 (الاثنين) إلى 6 (الأحد) مفصولة بفواصل.')
    shift_start, shift_end = d.get('shift_start', '09:00'), d.get('shift_end', '17:00')
    for t in [shift_start, shift_end]:
        if not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d', t): raise ValueError('وقت الدوام بصيغة HH:MM.')
    if shift_end <= shift_start: raise ValueError('حالياً حدّد دواماً يبدأ وينتهي في اليوم نفسه.')
    bonus_type = d.get('bonus_type', 'none')
    if bonus_type not in ['none', 'monthly', 'per_present_day']: raise ValueError('نظام المكافآت غير صحيح.')
    return dict(effective_month=month, pay_type=kind, rate=money(d.get('rate', 0)),
        shift_start=shift_start, shift_end=shift_end, workdays=workdays,
        grace_minutes=money(d.get('grace_minutes', 0)), late_per_minute=money(d.get('late_per_minute', 0)),
        absence_per_day=money(d.get('absence_per_day', 0)), fixed_deduction=money(d.get('fixed_deduction', 0)),
        bonus_type=bonus_type, bonus_amount=money(d.get('bonus_amount', 0)),
        contract_notes=text(d.get('contract_notes'), 6000))


def payroll_calculation(staff, month):
    contract = StaffContract.query.filter(StaffContract.staff_id == staff.id, StaffContract.effective_month <= month).order_by(StaffContract.effective_month.desc()).first()
    if not contract: raise ValueError('أضف عقداً سارياً لهذا الشهر أولاً.')
    terms = json.loads(contract.terms)
    attendance = Attendance.query.filter(Attendance.staff_id == staff.id, Attendance.day.startswith(month + '-')).all()
    scheduled = {int(x) for x in terms['workdays'].split(',')}
    minutes = lambda t: int(t[:2]) * 60 + int(t[3:])
    worked = late = present = absent = 0
    for row in attendance:
        if row.status == 'present':
            present += 1
            if row.check_in and row.check_out: worked += minutes(row.check_out) - minutes(row.check_in)
            if row.check_in and datetime.strptime(row.day, '%Y-%m-%d').weekday() in scheduled:
                late += max(0, minutes(row.check_in) - minutes(terms['shift_start']) - terms['grace_minutes'])
        elif row.status == 'absent' and datetime.strptime(row.day, '%Y-%m-%d').weekday() in scheduled:
            absent += 1
    units = {'monthly': 1, 'daily': present, 'hourly': worked / 60}[terms['pay_type']]
    bonus = terms['bonus_amount'] * ({'none': 0, 'monthly': 1, 'per_present_day': present}[terms['bonus_type']])
    deduction = terms['fixed_deduction'] + late * terms['late_per_minute'] + absent * terms['absence_per_day']
    return dict(contract=terms, present_days=present, absent_days=absent, worked_hours=round(worked / 60, 4),
        late_minutes=late, base_salary=round(units * terms['rate'], 2), automatic_bonus=round(bonus, 2), automatic_deduction=round(deduction, 2))


def install_hr_finance(app):
    POLICY['my_contract'] = {'cashier', 'admin', 'owner', 'developer'}
    @app.get('/api/hr/my-contract')
    def my_contract():
        staff = Staff.query.filter_by(user_id=g.current_user.id).first()
        if not staff: return jsonify(staff=None, contracts=[])
        contracts = StaffContract.query.filter_by(staff_id=staff.id).order_by(StaffContract.effective_month.desc()).all()
        return jsonify(staff={k: getattr(staff, k) for k in ['name', 'job_title', 'start_date']},
            contracts=[json.loads(c.terms) for c in contracts])

    def linked_user(value):
        if value in [None, '', '0', 0]: return None
        user_id = int(value)
        if not db.session.get(User, user_id): raise ValueError('حساب الدخول غير موجود.')
        return user_id

    def route(path, methods):
        def decorate(fn):
            # Payroll and personnel files require owner-level access, unlike sales reports.
            POLICY[fn.__name__] = {'owner', 'developer'}
            @wraps(fn)
            def guarded(*args, **kwargs):
                try:
                    return fn(*args, **kwargs)
                except (ValueError, TypeError) as error:
                    db.session.rollback()
                    return failure(str(error), 400)
                except IntegrityError:
                    db.session.rollback()
                    return failure('السجل موجود أو تم تنفيذه مسبقاً. حدّث الصفحة.', 409)
            app.route(path, methods=methods)(guarded)
            return guarded
        return decorate

    @route('/api/hr/staff', ['GET', 'POST'])
    def hr_staff():
        if request.method == 'GET':
            return jsonify(staff=[s.to_dict() for s in Staff.query.order_by(Staff.name).all()])
        d = request.get_json() or {}
        s = Staff(name=text(d.get('name'), 120, True), job_title=text(d.get('job_title'), 120),
                  user_id=linked_user(d.get('user_id')),
                  phone=text(d.get('phone'), 40), start_date=period(d.get('start_date')),
                  base_salary=money(d.get('base_salary', 0)), notes=text(d.get('notes'), 2000))
        db.session.add(s)
        db.session.flush()
        terms = contract_terms(d.get('contract', {'rate': s.base_salary}), s.start_date)
        db.session.add(StaffContract(staff_id=s.id, effective_month=terms['effective_month'], terms=json.dumps(terms, ensure_ascii=False), recorded_by=g.current_user.full_name))
        db.session.commit()
        return jsonify(staff=s.to_dict()), 201

    @route('/api/hr/staff/<int:staff_id>', ['PUT'])
    def hr_update_staff(staff_id):
        s = db.session.get(Staff, staff_id)
        if not s: return failure('الموظف غير موجود.', 404)
        d = request.get_json() or {}
        if 'user_id' in d: s.user_id = linked_user(d['user_id'])
        s.name = text(d.get('name', s.name), 120, True)
        s.job_title = text(d.get('job_title', s.job_title), 120)
        s.phone = text(d.get('phone', s.phone), 40)
        s.start_date = period(d.get('start_date', s.start_date))
        s.base_salary = money(d.get('base_salary', s.base_salary))
        if 'active' in d:
            if not isinstance(d['active'], bool): raise ValueError('حالة الموظف غير صحيحة.')
            s.active = d['active']
        s.notes = text(d.get('notes', s.notes), 2000)
        if 'contract' in d:
            terms = contract_terms(d['contract'], s.start_date)
            if Payroll.query.filter(Payroll.staff_id == s.id, Payroll.month >= terms['effective_month'], Payroll.status == 'paid').first():
                raise ValueError('لا تعدّل عقد فترة صُرفت رواتبها؛ اختر شهر سريان أحدث.')
            existing = StaffContract.query.filter_by(staff_id=s.id, effective_month=terms['effective_month']).first()
            if not existing:
                existing = StaffContract(staff_id=s.id, effective_month=terms['effective_month'])
                db.session.add(existing)
            existing.terms, existing.recorded_by = json.dumps(terms, ensure_ascii=False), g.current_user.full_name
        db.session.commit()
        return jsonify(staff=s.to_dict())

    @route('/api/hr/attendance', ['GET', 'POST'])
    def hr_attendance():
        if request.method == 'GET':
            month = period(request.args.get('month'), True)
            rows = Attendance.query.filter(Attendance.day.startswith(month + '-')).order_by(Attendance.day.desc()).all()
            return jsonify(attendance=[r.to_dict() for r in rows])
        d = request.get_json() or {}
        s = db.session.get(Staff, int(d.get('staff_id', 0)))
        if not s: return failure('الموظف غير موجود.', 404)
        day = period(d.get('day'))
        if Payroll.query.filter_by(staff_id=s.id, month=day[:7], status='paid').first():
            raise ValueError('حضور شهر مصروف مقفل؛ لا تغيّر سجل الراتب المدفوع.')
        if day < s.start_date: raise ValueError('الحضور لا يسبق تاريخ التعيين.')
        if not s.active: raise ValueError('الموظف مؤرشف.')
        status = d.get('status')
        if status not in ['present', 'absent', 'leave', 'holiday']: raise ValueError('حالة الحضور غير صحيحة.')
        times = [text(d.get(k), 5) for k in ['check_in', 'check_out']]
        for time in times:
            if time and not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d', time): raise ValueError('الوقت بصيغة 24 ساعة HH:MM.')
        if times[1] and not times[0]: raise ValueError('سجّل وقت الدخول أولاً.')
        if times[0] and times[1] and times[1] <= times[0]: raise ValueError('الخروج بعد الدخول في اليوم نفسه؛ قسّم الدوام الليلي على يومين.')
        if status != 'present' and any(times): raise ValueError('الأوقات تخص حالة الحضور فقط.')
        row = Attendance.query.filter_by(staff_id=s.id, day=day).first()
        if not row:
            row = Attendance(staff_id=s.id, day=day)
            db.session.add(row)
        row.status, row.check_in, row.check_out = status, *times
        row.notes, row.recorded_by = text(d.get('notes'), 2000), g.current_user.full_name
        db.session.commit()
        return jsonify(attendance=row.to_dict())

    @route('/api/hr/payroll', ['GET', 'POST'])
    def hr_payroll():
        if request.method == 'GET':
            month = period(request.args.get('month'), True)
            return jsonify(payroll=[r.to_dict() for r in Payroll.query.filter_by(month=month).all()])
        d = request.get_json() or {}
        s = db.session.get(Staff, int(d.get('staff_id', 0)))
        if not s: return failure('الموظف غير موجود.', 404)
        month = period(d.get('month'), True)
        if month < s.start_date[:7]: raise ValueError('شهر الراتب لا يسبق التعيين.')
        row = Payroll.query.filter_by(staff_id=s.id, month=month).first()
        if row and row.status != 'draft': return failure('الراتب المصروف مقفل للحفاظ على السجل.', 409)
        if not s.active and not row: raise ValueError('الموظف مؤرشف.')
        calculation = payroll_calculation(s, month)
        base = calculation['base_salary']
        manual_bonus, manual_deduction = money(d.get('bonus', 0)), money(d.get('deduction', 0))
        bonus, deduction = manual_bonus + calculation['automatic_bonus'], manual_deduction + calculation['automatic_deduction']
        notes = text(d.get('notes'), 2000)
        if manual_bonus + manual_deduction > 0 and not notes: raise ValueError('اكتب سبب المكافأة أو الخصم اليدوي.')
        if base + bonus < deduction: raise ValueError('الخصومات تتجاوز الراتب والمكافآت.')
        if not row:
            row = Payroll(staff_id=s.id, month=month)
            db.session.add(row)
        row.base_salary, row.bonus, row.deduction = base, bonus, deduction
        calculation.update(manual_bonus=manual_bonus, manual_deduction=manual_deduction)
        row.calculation = json.dumps(calculation, ensure_ascii=False)
        row.notes, row.recorded_by = notes, g.current_user.full_name
        db.session.commit()
        return jsonify(payroll=row.to_dict())

    @route('/api/hr/staff/<int:staff_id>/payroll-preview', ['GET'])
    def hr_payroll_preview(staff_id):
        s = db.session.get(Staff, staff_id)
        if not s: return failure('الموظف غير موجود.', 404)
        return jsonify(calculation=payroll_calculation(s, period(request.args.get('month'), True)))

    @route('/api/hr/payroll/<int:payroll_id>/pay', ['POST'])
    def hr_payroll_pay(payroll_id):
        row = db.session.get(Payroll, payroll_id)
        if not row: return failure('الراتب غير موجود.', 404)
        if row.status == 'paid': return jsonify(payroll=row.to_dict())
        current = payroll_calculation(db.session.get(Staff, row.staff_id), row.month)
        saved = json.loads(row.calculation or '{}')
        if any(current[k] != saved.get(k) for k in current):
            return failure('تغير العقد أو الحضور بعد إعداد الراتب؛ أعد إعداد المسودة قبل الصرف.', 409)
        changed = db.session.execute(db.update(Payroll).where(Payroll.id == row.id, Payroll.status == 'draft').values(status='paid'))
        if changed.rowcount != 1: return failure('تم صرف الراتب مسبقاً.', 409)
        amount = round(row.base_salary + row.bonus - row.deduction, 2)
        if amount > 0:
            expense = Expense(title=f'راتب {db.session.get(Staff, row.staff_id).name} • {row.month}',
                amount=amount, category='رواتب', notes=row.notes[:255], created_by=g.current_user.full_name,
                source='payroll', source_key=f'payroll:{row.id}')
            db.session.add(expense)
            db.session.flush()
            row.expense_id = expense.id
        row.paid_at = datetime.utcnow()
        db.session.commit()
        return jsonify(payroll=row.to_dict())

    @route('/api/fixed-expenses', ['GET', 'POST'])
    def fixed_expenses():
        if request.method == 'GET':
            month = period(request.args.get('month'), True)
            result = []
            for row in FixedExpense.query.order_by(FixedExpense.id.desc()).all():
                d = row.to_dict()
                paid = Expense.query.filter_by(source_key=f'fixed:{row.id}:{month}').first()
                d['paid'] = paid is not None
                d['paid_amount'] = paid.amount if paid else None
                result.append(d)
            return jsonify(fixed_expenses=result)
        d = request.get_json() or {}
        amount = money(d.get('amount', 0))
        if amount <= 0: raise ValueError('المبلغ يجب أن يكون أكبر من صفر.')
        day = int(d.get('due_day', 1))
        if not 1 <= day <= 28: raise ValueError('يوم الاستحقاق من 1 إلى 28.')
        category = d.get('category')
        if category not in ['إيجار', 'اشتراكات', 'خدمات', 'مدفوعات ثابتة']: raise ValueError('اختر تصنيفاً للالتزام الثابت.')
        row = FixedExpense(title=text(d.get('title'), 150, True), amount=amount, category=category,
            due_day=day, notes=text(d.get('notes'), 2000))
        db.session.add(row)
        db.session.commit()
        return jsonify(fixed_expense=row.to_dict()), 201

    @route('/api/fixed-expenses/<int:fixed_id>', ['PUT'])
    def fixed_expense_update(fixed_id):
        row = db.session.get(FixedExpense, fixed_id)
        if not row: return failure('الالتزام غير موجود.', 404)
        d = request.get_json() or {}
        row.title = text(d.get('title', row.title), 150, True)
        row.amount = money(d.get('amount', row.amount))
        if row.amount <= 0: raise ValueError('المبلغ يجب أن يكون أكبر من صفر.')
        row.due_day = int(d.get('due_day', row.due_day))
        if not 1 <= row.due_day <= 28: raise ValueError('يوم الاستحقاق من 1 إلى 28.')
        if 'active' in d:
            if not isinstance(d['active'], bool): raise ValueError('الحالة غير صحيحة.')
            row.active = d['active']
        db.session.commit()
        return jsonify(fixed_expense=row.to_dict())

    @route('/api/fixed-expenses/<int:fixed_id>/pay', ['POST'])
    def fixed_expense_pay(fixed_id):
        row = db.session.get(FixedExpense, fixed_id)
        if not row: return failure('الالتزام غير موجود.', 404)
        month = period((request.get_json() or {}).get('month'), True)
        key = f'fixed:{row.id}:{month}'
        old = Expense.query.filter_by(source_key=key).first()
        if old: return jsonify(expense=old.to_dict())
        if not row.active: raise ValueError('الالتزام متوقف.')
        expense = Expense(title=f'{row.title} • {month}', amount=row.amount, category=row.category,
            notes=row.notes[:255], created_by=g.current_user.full_name, source='fixed', source_key=key)
        db.session.add(expense)
        db.session.commit()
        return jsonify(expense=expense.to_dict()), 201
