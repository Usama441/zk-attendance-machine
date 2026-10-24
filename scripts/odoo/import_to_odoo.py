# Loads the JSON from export_rails.rb into an Odoo database with ti_zk_attendance installed.
# Run inside Odoo shell, JSON path in ZK_IMPORT_JSON (default /tmp/rails_export.json):
#   docker exec -i -e ZK_COMPANY_ID=1 <odoo> odoo shell -d <db> < scripts/odoo/import_to_odoo.py
# Safe to run again: employees match on ZK user ID, punches on (employee, time); other records
# are only added when an identical one is not there yet.
import json
import os
from datetime import datetime

import pytz

from odoo import fields
from odoo.addons.ti_zk_attendance.models.zk_engine import company_tz, local_to_utc

path = os.environ.get('ZK_IMPORT_JSON', '/tmp/rails_export.json')
data = json.load(open(path))
company_id = int(os.environ.get('ZK_COMPANY_ID') or env.company.id)  # noqa: F821 (odoo shell)
env = env(context=dict(env.context, tracking_disable=True, zk_import=True,  # noqa: F821
                       allowed_company_ids=[company_id]))
company = env.company
tz = company_tz(company)
report = {}


def utc(local_str):
    local = datetime.strptime(local_str, '%Y-%m-%d %H:%M:%S')
    return tz.localize(local).astimezone(pytz.utc).replace(tzinfo=None)


# ---- settings ----
s = data['settings']
company.write({
    'zk_saturday_rule_from': s['saturday_rule_from'] or False,
    'zk_parking_bike_price': s['parking_bike_price'],
    'zk_parking_car_price': s['parking_car_price'],
    'zk_salary_tax_enabled': s['salary_tax_enabled'],
})

# ---- employees + salary on the contract (hr.version) ----
Employee = env['hr.employee']
zk_type = env.ref('ti_zk_attendance.structure_type_zk')
by_uid = {e.zk_uid: e for e in Employee.search([('zk_uid', '!=', False), ('company_id', '=', company.id)])}
created = 0
for row in data['employees']:
    emp = by_uid.get(row['uid'])
    vals = {
        'zk_device_admin': row['device_admin'],
        'zk_device_enabled': row['device_enabled'],
        'zk_hide_from_export': row['hidden_from_export'],
    }
    if not emp:
        emp = by_uid[row['uid']] = Employee.create(dict(vals, name=row['name'] or str(row['uid']),
                                                        zk_uid=row['uid'], company_id=company.id))
        created += 1
    else:
        emp.write(vals)
    emp.version_id.write({
        'wage': row['monthly_salary'],
        'structure_type_id': zk_type.id,
        'contract_date_start': emp.version_id.contract_date_start or row['first_punch'] or '2026-01-01',
    })
report['employees created'] = created

# ---- punches ----
Punch = env['zk.punch']
existing = set(Punch.search([]).mapped(lambda p: (p.employee_id.id, p.punched_at)))
users = {}
new = []
for row in data['punches']:
    emp = by_uid[row['uid']]
    at = utc(row['time'])
    if (emp.id, at) in existing:
        continue
    existing.add((emp.id, at))
    note = row['note']
    if row['source'] == 'manual' and row.get('created_by'):
        note = '%s (by %s in Rails)' % (note or 'Manual', row['created_by'])
    new.append({'employee_id': emp.id, 'punched_at': at, 'source': row['source'], 'voided': row['voided'],
                'note': note, 's1': row['s1'], 's2': row['s2']})
Punch.create(new)
report['punches added'] = len(new)

# ---- late rules: same as Rails ----
LateRule = env['zk.late.rule']
rails_rules = {r['effective_from']: r['late_at'] for r in data['late_rules']}
for r in data['late_rules']:
    h, m = map(int, r['late_at'].split(':'))
    rule = LateRule.search([('company_id', '=', company.id), ('effective_from', '=', r['effective_from'])])
    vals = {'late_at': h + m / 60}
    rule.write(vals) if rule else LateRule.create(dict(vals, effective_from=r['effective_from'], company_id=company.id))
extra = LateRule.search([('company_id', '=', company.id)]).filtered(
    lambda r: fields.Date.to_string(r.effective_from) not in rails_rules)
if extra and len(extra) < LateRule.search_count([('company_id', '=', company.id)]):
    extra.unlink()

# ---- public holidays ----
Leaves = env['resource.calendar.leaves']
added = 0
for h in data['holidays']:
    d_from = local_to_utc(fields.Date.to_date(h['starts_on']), 0, tz)
    d_to = local_to_utc(fields.Date.to_date(h['ends_on']), 23 + 59 / 60, tz).replace(second=59)
    if not Leaves.search_count([('resource_id', '=', False), ('name', '=', h['name']), ('date_from', '=', d_from)]):
        Leaves.create({'name': h['name'], 'date_from': d_from, 'date_to': d_to, 'company_id': company.id,
                       'calendar_id': False, 'time_type': 'leave'})
        added += 1
report['holidays added'] = added

# ---- working Saturdays ----
Sat = env['zk.working.saturday']
for d in data['working_saturdays']:
    if not Sat.search_count([('company_id', '=', company.id), ('date', '=', d)]):
        Sat.create({'date': d, 'company_id': company.id})

# ---- comments (expired ones are skipped; Odoo would delete them anyway) ----
Comment = env['zk.employee.comment']
today = fields.Date.to_string(datetime.now(tz).date())
added = 0
for c in data['comments']:
    if c['ends_on'] < today:
        continue
    emp = by_uid[c['uid']]
    if not Comment.search_count([('employee_id', '=', emp.id), ('body', '=', c['body']), ('starts_on', '=', c['starts_on'])]):
        Comment.create({'employee_id': emp.id, 'body': c['body'], 'starts_on': c['starts_on'], 'ends_on': c['ends_on']})
        added += 1
report['comments added'] = added

# ---- leave requests -> Time Off ----
types = {
    'casual': env.ref('ti_zk_attendance.leave_type_casual'),
    'sick': env.ref('ti_zk_attendance.leave_type_sick'),
    'annual': env.ref('ti_zk_attendance.leave_type_annual'),
    'unpaid': env.ref('ti_zk_attendance.leave_type_unpaid'),
}
Leave = env['hr.leave']
added, failed = 0, []
for l in data['leaves']:
    emp = by_uid[l['uid']]
    if Leave.search_count([('employee_id', '=', emp.id), ('request_date_from', '=', l['start_date']),
                           ('holiday_status_id', '=', types[l['leave_type']].id)]):
        continue
    try:
        with env.cr.savepoint():
            leave = Leave.create({
                'employee_id': emp.id, 'holiday_status_id': types[l['leave_type']].id,
                'request_date_from': l['start_date'], 'request_date_to': l['end_date'],
                'private_name': l['reason'],
            })
            if l['status'] == 'approved':
                leave.action_approve()
            elif l['status'] == 'rejected':
                leave.action_refuse()
            elif l['status'] == 'cancelled':
                leave.action_refuse()
            if l.get('admin_note') or l.get('reviewed_by'):
                leave.message_post(body='Rails review: %s by %s. %s' % (l['status'], l.get('reviewed_by') or '-', l.get('admin_note') or ''))
            added += 1
    except Exception as e:  # noqa: BLE001 - report and carry on
        failed.append('%s %s..%s: %s' % (emp.name, l['start_date'], l['end_date'], e))
report['leaves added'] = added
if failed:
    report['leaves failed'] = failed

# ---- parking ----
Parking = env['zk.parking.request']
states = {'pending': 'pending', 'approved': 'approved', 'rejected': 'rejected', 'cancelled': 'cancelled'}
added = 0
for q in data['parking']:
    emp = by_uid[q['uid']]
    if Parking.search_count([('employee_id', '=', emp.id), ('month', '=', q['month']), ('vehicle_number', '=', q['vehicle_number'])]):
        continue
    Parking.create({
        'employee_id': emp.id, 'month': q['month'], 'vehicle_type': q['vehicle_type'],
        'vehicle_number': q['vehicle_number'], 'price': q['price'], 'state': states[q['status']],
        'reviewed_at': utc(q['reviewed_at']) if q.get('reviewed_at') else False,
        'admin_note': ' '.join(filter(None, [q.get('admin_note'), q.get('reviewed_by') and '(reviewed by %s in Rails)' % q['reviewed_by']])) or False,
    })
    added += 1
report['parking added'] = added

env.cr.commit()
print('ZK IMPORT', json.dumps(report, indent=1, default=str))
