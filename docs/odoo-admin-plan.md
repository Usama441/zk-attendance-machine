# ZK Attendance — moving the admin side to Odoo 19

Flow: **ZK machine → Rails app → Odoo**. Rails keeps talking to the machine and keeps the
employee portal. Everything an admin does today in Rails moves to Odoo (Enterprise, test
database `zk_hr_test` on http://localhost:8070).

---

## 1. Inventory of the Rails admin side

| # | Rails page / route | What it does | Data it owns |
|---|---|---|---|
| A1 | **Dashboard / Sync** `/`, `POST /sync` | Pull users + punches from the machine for a date range; auto-sync every N minutes over the last N days; shows last sync status | `employees`, `punches`, `app_settings.last_sync_*` |
| A2 | **Export** `POST /export` | Excel *matrix*: one row per employee, IN/OUT per day; off days grey, late IN yellow, absent pink, employee with no punch red; comments column; all employees (minus hidden/deactivated) or one employee | reads punches, comments, holidays, late rules |
| A3 | **Corrections** `/corrections` | View an employee's punches for a range; add a missing punch; bulk-add the same times over date ranges (skip weekdays); replace a punch time (original voided, manual replacement); void/restore a punch. All manual punches carry note + who | `punches.source/voided/note/created_by` |
| A4 | **Comments** `/comments` | Date-ranged note per employee, shown in the export's Comments column, auto-deleted the day after it ends | `employee_comments` |
| A5 | **Leaves** `/leaves` | Approve / reject employee leave requests (casual, sick, annual, unpaid) with an admin note; a decision can be changed later | `leave_requests` |
| A6 | **Parking** `/parking` | Review monthly sticker requests (bike/car, plate `LEM-334`), set bike/car prices, export the month's vehicle list to Excel; approved stickers are deducted from pay | `parking_requests`, `app_settings.parking_*_price` |
| A7 | **Payroll** `/payroll`, `/payroll/:id` | Per month, per employee: present / late / absent / leave / unpaid / holiday counts, deduction, income tax, parking, take-home; day-by-day breakdown; set salary, portal username/password, admin role | `employees.monthly_salary`, `password_digest`, `role` |
| A8 | **Tax slabs** `/payroll/tax` | Pakistani salaried tax slabs per tax year (1 Jul–30 Jun); switch salary tax on/off | `tax_years`, `app_settings.salary_tax_enabled` |
| A9 | **Late time** `/settings/late` | Late cut-off by effective date (09:15 until 5 Oct 2026, 08:50 from 6 Oct) | `late_rules` |
| A10 | **Holidays & Saturdays** `/settings/holidays` | Office holidays (date ranges); 1st & 3rd Saturdays off from a start date, with per-date "make this a working Saturday" | `holidays`, `working_saturdays`, `app_settings.saturday_rule_from` |
| A11 | **Settings** `/settings` | Machine connection (host, ports, timeouts, comm key), auto-sync, hide employees from exports | `app_settings`, `employees.hidden_from_export` |
| A12 | **Machine access** | Enable/disable a user *on the machine* (SDK port 4370), refresh status, rename employee (name kept on later syncs) | `employees.device_enabled/_changed_*`, `name_locked` |

### Business rules (from `MonthlyAttendance`, `WorkCalendar`, `Punch`)

* A **work day** runs 06:00 → 05:59 next morning (a 01:30 checkout belongs to the day before).
* **First punch** of the day = IN, **last punch** (if more than one) = OUT.
* **Off days**: every Sunday; 1st & 3rd Saturday from `saturday_rule_from` (before it every
  Saturday is off) unless made a working Saturday; office holidays.
* **Day status** (in this order): punched → *present* or *late* (late only on a working day,
  first punch ≥ cut-off of that date) · *weekend* · *holiday* · approved leave → *leave* or
  *unpaid_leave* · today → *today* · before the employee's first ever punch → *not tracked* ·
  otherwise *absent*. Future days are *upcoming*.
* **Deduction days** = absents + unpaid leave days + ⌊lates ÷ 3⌋.
* **Day rate** = monthly salary ÷ calendar days in the month. Deduction is capped at the salary.
* **Income tax** = annual tax on (full salary × 12) ÷ 12 — on the *full* salary, not the
  salary after deductions — capped at what is left. Can be switched off.
* **Parking** = approved stickers of that month, taken after tax, capped at what is left.
* **Take-home** = salary − attendance deduction − tax − parking.

---

## 2. Mapping to Odoo

| # | Odoo home | Standard / custom |
|---|---|---|
| A1 | Rails keeps syncing the machine and **pushes** employees + raw punches to Odoo (JSON-2 API). Odoo stores them in `zk.punch` and builds one `hr.attendance` per work day | custom model + Rails push (phase 2) |
| A2 | Wizard **ZK Attendance → Exports → Attendance matrix** (same layout and colours, xlsx) | custom |
| A3 | **ZK Attendance → Punches**: list grouped by employee/day with *Void/Restore*, *Correct time*, *Add punch*, *Bulk add* wizards. Original punch is never deleted | custom (on top of `hr.attendance`) |
| A4 | **ZK Attendance → Comments** (`zk.employee.comment`), daily cron deletes expired | custom |
| A5 | **Time Off** (`hr_holidays`): types Casual, Sick, Annual (paid) and Unpaid (`unpaid = True`), no allocation needed, approved by the Time Off officer. Refusing / resetting replaces "change the decision" | standard |
| A6 | **ZK Attendance → Parking** (`zk.parking.request`) with Approve/Reject, prices in Settings, vehicle-list xlsx wizard; deduction on the payslip | custom |
| A7 | **ZK Attendance → Monthly summary** (per-employee month report + day lines) and real **Payroll payslips** on a new structure *"TI: ZK Monthly"*. Salary = wage on the employee's contract (`hr.version`) | standard Payroll + custom rules |
| A8 | Pakistani tax brackets are an Odoo **rule parameter** (`l10n_pk_tax_brackets`) with dated values; the 2026-27 slabs from Rails are added from 1 Jul 2026. On/off switch in Settings | standard + data |
| A9 | **Configuration → Late rules** (`zk.late.rule`) | custom |
| A10 | Holidays = Odoo **Public Holidays** (Time Off → Configuration). Saturday rule start date in Settings, **Working Saturdays** list (`zk.working.saturday`) | standard + custom |
| A11 | Machine connection & auto-sync **stay in Rails** (only Rails talks to the machine). "Hide from export" → checkbox on the employee | split |
| A12 | Enabling/disabling users *on the machine* **stays in Rails** (needs the SDK socket). Rename → just edit the employee in Odoo (Rails never overwrites a name that exists) | stays in Rails |

---

## 3. Analysis — gaps, risks and decisions

1. **Raw punches vs `hr.attendance`.** Odoo attendance is one check-in/check-out pair; Rails
   keeps every raw punch so corrections are auditable. *Decision:* keep the raw log in
   `zk.punch` (device + manual, voided flag, note, who) and derive one `hr.attendance` per
   employee per work day (first IN → last OUT). Corrections edit punches, never attendance
   directly; attendance is recomputed automatically.
2. **Single-punch days.** Odoo allows only one *open* attendance per employee, so a day with a
   single punch gets `check_out = check_in` and is flagged *Missing OUT* (same as Rails, where
   OUT is blank).
3. **Time zones.** Rails stores the machine's local wall-clock time labelled UTC. Odoo stores
   real UTC. *Decision:* the Rails push (and the migration script) convert Asia/Karachi → UTC;
   Odoo shows times in the user's time zone (admin set to Asia/Karachi). Work dates are computed
   in Asia/Karachi.
4. **Odoo's own payroll proration differs.** The stock Pakistan structure pays
   `payslip.paid_amount` (prorated by work hours) and taxes the prorated gross. Rails uses
   *salary ÷ calendar days* and taxes the *full* salary. *Decision:* a separate structure
   **"TI: ZK Monthly"** (same Pakistan structure type) whose rules call the same Python code as
   the monthly summary, so payslip, summary and portal always agree. The stock structure is left
   untouched.
5. **Tax slabs.** Odoo ships 2024 brackets in `(from, to, rate, fixed)` form; Rails has the
   2026-27 slabs. They are added as a new parameter value from 2026-07-01:
   0–600k 0% · 600k–1.2M 1% · 1.2M–2.2M 11% · 2.2M–3.2M 20% · 3.2M–4.1M 25% · 4.1M–5.6M 29% ·
   5.6M–7M 32% · 7M+ 35%. Next June: add a new value in Payroll → Configuration → Rule
   Parameters (no code).
6. **Saturday rule.** Odoo work schedules can't say "1st and 3rd Saturday". Payroll and the
   export don't use the Odoo schedule — they use the custom calendar (`WorkCalendar` port) —
   so this is exact. Side effect: Odoo's *Time Off* duration counts only Mon–Fri (standard
   40 h schedule); a leave over a working Saturday still covers that Saturday in our rules.
7. **Leaves.** Rails has no balances; Odoo types are created with *no allocation required* so
   they behave the same. Rails' admin note maps to the Time Off chatter / refuse reason.
8. **Who is an admin.** Rails roles (`admin`) are replaced by Odoo users and groups:
   Attendance Officer/Manager for ZK menus, Payroll Officer for salaries and parking prices.
9. **Portal stays in Rails** (phase 2): leave/parking requests are written to Odoo; attendance,
   salary and statuses are read from Odoo. Portal usernames/passwords stay in Rails.
10. **What's not moved:** machine connection, auto-sync timer, enable/disable on the machine —
    they need the device and stay in Rails.

---

## 4. Implementation — Odoo module `ti_zk_attendance`

Location: `/opt/odoo/odoo19/custom_addons/TI_Associates/ti_zk_attendance`
Depends: `hr_attendance`, `hr_holidays`, `hr_payroll`, `l10n_pk_hr_payroll`.

| Model | Purpose |
|---|---|
| `hr.employee` (+) | `zk_uid` (unique), `zk_device_admin`, `zk_device_enabled`, `zk_hide_from_export`, `zk_first_punch_date` |
| `zk.punch` | raw punch log: employee, time (UTC), work date, source device/manual, voided, note, created by; unique (employee, time); keeps `hr.attendance` in sync |
| `zk.late.rule` | effective from + late time |
| `zk.working.saturday` | 1st/3rd Saturday turned into a working day |
| `zk.employee.comment` | date-ranged comments + purge cron |
| `zk.parking.request` | sticker requests, plate normalisation, review |
| `zk.month.summary` / `zk.month.day` | stored monthly report per employee (recomputed on demand and nightly) |
| `zk.calendar` (abstract) | port of `WorkCalendar` + `MonthlyAttendance` |
| `res.company` / `res.config.settings` (+) | Saturday rule start, parking prices, salary-tax switch |
| `hr.payslip` (+) | exposes the same numbers to salary rules |
| wizards | add punch, bulk add, correct time, attendance matrix export, parking export, compute month |

Data: leave types (Casual/Sick/Annual/Unpaid), late rules (09:15 from 2026-01-01, 08:50 from
2026-10-06), 2026-27 tax brackets, salary structure "TI: ZK Monthly" + rules, purge/recompute
crons.

## 5. Test plan (in `zk_hr_test`)

1. Migrate Rails data (employees, punches, leaves, holidays, late rules, Saturdays, comments,
   parking, salaries) with `scripts/migrate_rails_to_odoo`.
2. For each of A2–A10 compare Odoo with the Rails page for the same month:
   matrix export, corrections, comments, leave approval, parking + export, monthly summary,
   payslip, tax, late rules, holidays/Saturdays.
3. Phase 2: Rails push (sync → Odoo) and portal reading/writing Odoo.
