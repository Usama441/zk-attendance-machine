# ZK Attendance Exporter (Rails + PostgreSQL + Docker)

Web app that connects to the ZKTeco time-attendance terminal (default `192.168.10.15`),
stores every punch in **PostgreSQL**, and exports attendance to **Excel (.xlsx)**.

Why a database? The device only keeps ~1 month of logs in its own memory. Each **Sync**
pulls the current logs and upserts them into Postgres (duplicates are skipped), so you build
up a permanent history you can export any time — even for dates the device has since dropped.

The app only **reads** attendance from the device. It never edits or writes back the machine's
timestamps. The one exception is **Settings → Machine access**, which can activate/deactivate users.

## Run

- **Easiest:** double-click **“ZK Attendance”** on the Desktop. It starts the app
  (Docker Desktop must be running) and opens the browser. **“ZK Attendance — Stop”** stops it.
- **Terminal:**
  ```
  cd ~/zk-attendance
  docker compose up --build      # first time
  # later:  docker compose up -d
  ```

Open <http://localhost:3000>.

Stop: `docker compose down`  ·  Reset data too: `docker compose down -v`

## Sign in

There is **no separate app account**. You sign in with your **device Login ID + password**,
and only users who have the **admin role on the machine** are accepted (the app verifies the
credentials against the terminal). The signed-in admin's own credentials are then used to
sync from the device.

## How to use

1. Set the date range and click **⟳ Sync from device** (pulls into Postgres without reloading the page).
2. Choose **All employees** (bulk) or **Single employee**, set the range, click **⬇ Export to Excel**.
3. The `.xlsx` downloads an IN/OUT attendance matrix. Late arrivals (first punch ≥ 09:15)
   are highlighted — no data is altered.

Open **Settings** to enable automatic synchronization, choose the interval, and choose how
many recent days each sync fetches. Automatic sync uses AJAX and runs while the Home page
remains open in a signed-in browser.

## Corrections (admin)

Open **Corrections** (top nav) to fix records without touching the raw device log:
- **Add a punch** — pick employee + date + time, add a reason (e.g. forgot to punch, or
  clocked in on another person's finger).
- **Void a punch** — exclude a wrong punch from reports; it is not deleted, and re-syncing
  never brings it back. You can **Restore** it later.

Every manual punch records who added it and the note; voided punches are hidden from all
exports. Only signed-in device admins can reach this page.

## Employee portal, leaves & payroll

**Employees** sign in on the same page via the **Employee** tab, using their **machine user ID** and a
**portal password** that an admin sets on **Payroll** (column *Portal → Set up*). They can:
- see their attendance month by month (present / late / absent / leave, first IN and last OUT per day);
- see this month's salary deduction (running total) and past months (final);
- apply for leave and cancel it while it is still pending; change their own portal password.

**Admins** get two new pages:
- **Leaves** — approve or reject requests (with an optional note). The nav shows the pending count.
- **Payroll** — set each employee's monthly salary, see every employee's deduction for a month,
  click a name for the day-by-day breakdown, and set / reset / remove portal passwords.

**Deduction rules** (`app/services/monthly_attendance.rb`):

| Case | Deduction |
|------|-----------|
| Absent (Mon–Fri, no punch, no approved leave) | 1 day each |
| Late (first punch at or after `MatrixWorkbook::GRACE`, 08:50) | every 3 lates = 1 day (3–5 lates = 1 day, 6–8 = 2, …) |
| Approved **unpaid** leave | 1 day each |
| Approved casual / sick / annual leave, weekends | none |

Day rate = monthly salary ÷ calendar days in the month. Days before an employee's first-ever punch
are "not tracked" (not counted as absent). Today is not counted as absent until the day is over.
Public holidays are **not** known to the app — fix them with **Corrections** (or approved leave).

After pulling this change, rebuild once (new `bcrypt` gem + migrations): `docker compose up -d --build`.

## Machine access (activate / deactivate employees)

**Settings → Machine access** lists every employee with their status on the machine. Click
**Deactivate** for someone who has left: they stay enrolled (fingerprints, card and history are
kept) but the machine rejects them, so they can't punch in or open the door. **Activate** reverses it.
The change is written to the machine immediately, and the app records who did it and when.
"Also hide deactivated people from export" (on by default) also ticks them in *Hide from export*.

- This uses the machine's binary SDK (**port 4370**, set under *Machine connection → SDK port*), not
  the web pages, because the web firmware has no enable/disable option. It authenticates with the
  machine's **Comm Key** (machine menu → Comm. → Comm Key; default 0).
- It tries TCP first and falls back to UDP; the machine accepts only one TCP SDK client at a time.
- Only the "disabled" bit of the user's record changes. Name, privilege, password, card and
  fingerprints are written back untouched. Statuses are re-read on every sync, so changes made on
  the machine itself also show up. Use **Refresh from machine** to re-read them on demand.
- You can't deactivate the account you're signed in with, or the last active admin.

## Configuration — `docker-compose.yml` (web → environment)

| Var | Default | Meaning |
|-----|---------|---------|
| `ZK_HOST` / `ZK_PORT` | `192.168.10.15` / `80` | initial device address; change it later from **Settings → Machine Connection** |
| `SECRET_KEY_BASE` | (dev default) | set a random value for real use |

App login is the device's own admin credentials — no app-specific user to configure.

Change a value, then `docker compose up -d --build`.

## Notes

- Device timestamps are naive local time; the container runs in **UTC**, so stored/displayed
  clock values match the device exactly. Keep the default timezone to avoid shifting times.
- Re-syncing an overlapping range is safe — existing punches are de-duplicated on
  `(employee, punched_at)`.

## Layout

```
app/lib/zk_client.rb              device HTTP client (session, login, download, parse)
app/lib/zk_sdk_client.rb          device SDK client, port 4370 (list users, enable/disable)
app/controllers/device_access_controller.rb  Settings → Machine access
app/services/sync_service.rb      pulls device data -> upserts into Postgres
app/services/attendance_workbook.rb  builds the formatted .xlsx (caxlsx)
app/controllers/exports_controller.rb  index / sync / export actions
app/models/{employee,punch,leave_request}.rb  ActiveRecord models
app/services/monthly_attendance.rb  per-employee month: day statuses + salary deduction
app/controllers/{leave_requests,payroll}_controller.rb  admin: Leaves, Payroll
app/controllers/portal*_controller.rb  employee portal (sign-in, attendance, leaves)
db/migrate/*                      schema (employees, punches, leave_requests, …)
Dockerfile, docker-compose.yml    Ruby web image + Postgres 16
```
