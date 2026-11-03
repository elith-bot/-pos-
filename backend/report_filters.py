from datetime import datetime, timedelta, timezone
import math


def report_window(args, now=None):
    now = now or datetime.utcnow()
    period = args.get('period', 'all')
    offset = int(args.get('tz_offset', 180))
    if not -840 <= offset <= 840: raise ValueError('المنطقة الزمنية غير صحيحة.')
    delta = timedelta(minutes=offset)
    local = now + delta
    today = local.replace(hour=0, minute=0, second=0, microsecond=0)
    start = end = None
    if period == 'hours':
        hours = float(args.get('hours', 1))
        if not math.isfinite(hours) or not 0 < hours <= 8760: raise ValueError('عدد الساعات يجب أن يكون أكبر من صفر وحتى 8760.')
        start, end = local - timedelta(hours=hours), local
    elif period == 'custom_time':
        def parse(key):
            value = args.get(key)
            if not value: raise ValueError('حدد وقت البداية والنهاية.')
            dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
            return dt.astimezone(timezone.utc).replace(tzinfo=None) + delta if dt.tzinfo else dt
        start, end = parse('start_at'), parse('end_at')
    elif period == 'custom':
        start = datetime.strptime(args['start_date'], '%Y-%m-%d')
        end = datetime.strptime(args['end_date'], '%Y-%m-%d') + timedelta(days=1)
    elif period in ['today','yesterday','week','month','year']:
        start = {'today':today,'yesterday':today-timedelta(days=1),'week':today-timedelta(days=6),
                 'month':today.replace(day=1),'year':today.replace(month=1,day=1)}[period]
        end = today if period == 'yesterday' else today + timedelta(days=1)
    elif period != 'all': raise ValueError('الفترة غير صحيحة.')
    if start is not None and start >= end: raise ValueError('وقت النهاية يجب أن يكون بعد البداية.')
    utc_start, utc_end = (start-delta, end-delta) if start is not None else (None,None)
    clock = period in ['hours','custom_time']
    display_start = start.strftime('%Y-%m-%d %H:%M') if clock else start.strftime('%Y-%m-%d') if start else 'البداية'
    display_end = end.strftime('%Y-%m-%d %H:%M') if clock else (end-timedelta(microseconds=1)).strftime('%Y-%m-%d') if end else 'الآن'
    resolved = dict(args)
    resolved.pop('format', None)
    resolved.update(period='custom_time' if start else 'all',tz_offset=str(offset))
    if start: resolved.update(start_at=utc_start.isoformat()+'Z', end_at=utc_end.isoformat()+'Z')
    return period, display_start, display_end, utc_start, utc_end, delta, resolved
