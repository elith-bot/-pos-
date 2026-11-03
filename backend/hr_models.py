"""HR records are separate from login accounts; no account is required for staff."""
from datetime import datetime
import json
from models import db


class Staff(db.Model):
    __tablename__ = 'hr_staff'
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), unique=True, nullable=True)
    job_title = db.Column(db.String(120), default='')
    phone = db.Column(db.String(40), default='')
    start_date = db.Column(db.String(10), nullable=False)
    base_salary = db.Column(db.Float, default=0)
    active = db.Column(db.Boolean, default=True)
    notes = db.Column(db.Text, default='')

    def to_dict(self):
        result = {k: getattr(self, k) for k in ('id', 'user_id', 'name', 'job_title', 'phone', 'start_date', 'base_salary', 'active', 'notes')}
        contract = StaffContract.query.filter_by(staff_id=self.id).order_by(StaffContract.effective_month.desc()).first()
        result['contract'] = json.loads(contract.terms) if contract else {}
        return result


class StaffContract(db.Model):
    __tablename__ = 'hr_contracts'
    __table_args__ = (db.UniqueConstraint('staff_id', 'effective_month'),)
    id = db.Column(db.Integer, primary_key=True)
    staff_id = db.Column(db.Integer, db.ForeignKey('hr_staff.id'), nullable=False)
    effective_month = db.Column(db.String(7), nullable=False)
    terms = db.Column(db.Text, nullable=False)
    recorded_by = db.Column(db.String(120), nullable=False)


class Attendance(db.Model):
    __tablename__ = 'hr_attendance'
    __table_args__ = (db.UniqueConstraint('staff_id', 'day'),)
    id = db.Column(db.Integer, primary_key=True)
    staff_id = db.Column(db.Integer, db.ForeignKey('hr_staff.id'), nullable=False)
    day = db.Column(db.String(10), nullable=False)
    status = db.Column(db.String(20), nullable=False)
    check_in = db.Column(db.String(5), default='')
    check_out = db.Column(db.String(5), default='')
    notes = db.Column(db.Text, default='')
    recorded_by = db.Column(db.String(120), nullable=False)

    def to_dict(self):
        result = {k: getattr(self, k) for k in ('id', 'staff_id', 'day', 'status', 'check_in', 'check_out', 'notes', 'recorded_by')}
        result['staff_name'] = db.session.get(Staff, self.staff_id).name
        return result


class Payroll(db.Model):
    __tablename__ = 'hr_payroll'
    __table_args__ = (db.UniqueConstraint('staff_id', 'month'),)
    id = db.Column(db.Integer, primary_key=True)
    staff_id = db.Column(db.Integer, db.ForeignKey('hr_staff.id'), nullable=False)
    month = db.Column(db.String(7), nullable=False)
    base_salary = db.Column(db.Float, nullable=False)
    bonus = db.Column(db.Float, default=0)
    deduction = db.Column(db.Float, default=0)
    notes = db.Column(db.Text, default='')
    status = db.Column(db.String(16), default='draft')
    expense_id = db.Column(db.Integer, db.ForeignKey('expenses.id'), unique=True)
    paid_at = db.Column(db.DateTime)
    recorded_by = db.Column(db.String(120), nullable=False)
    calculation = db.Column(db.Text, default='{}')

    def to_dict(self):
        result = {k: getattr(self, k) for k in ('id', 'staff_id', 'month', 'base_salary', 'bonus', 'deduction', 'notes', 'status', 'expense_id', 'recorded_by')}
        result['staff_name'] = db.session.get(Staff, self.staff_id).name
        result['net_salary'] = round(self.base_salary + self.bonus - self.deduction, 2)
        result['paid_at'] = self.paid_at.isoformat() + 'Z' if self.paid_at else None
        result['calculation'] = json.loads(self.calculation or '{}')
        return result


class FixedExpense(db.Model):
    __tablename__ = 'fixed_expenses'
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(150), nullable=False)
    amount = db.Column(db.Float, nullable=False)
    category = db.Column(db.String(80), nullable=False)
    due_day = db.Column(db.Integer, default=1)
    active = db.Column(db.Boolean, default=True)
    notes = db.Column(db.Text, default='')

    def to_dict(self):
        return {k: getattr(self, k) for k in ('id', 'title', 'amount', 'category', 'due_day', 'active', 'notes')}
