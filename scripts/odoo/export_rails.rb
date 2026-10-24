# frozen_string_literal: true
# Dumps the Rails admin data as JSON for scripts/odoo/import_to_odoo.py (test migration to Odoo).
#   docker compose exec -T web bin/rails runner scripts/odoo/export_rails.rb > tmp/rails_export.json
# Punch times are the machine's local wall-clock time (as stored here), "YYYY-MM-DD HH:MM:SS".
require "json"

fmt = ->(t) { t&.strftime("%Y-%m-%d %H:%M:%S") }
settings = AppSetting.current

data = {
  settings: {
    saturday_rule_from: settings.saturday_rule_from&.to_s,
    parking_bike_price: settings.parking_bike_price.to_f,
    parking_car_price: settings.parking_car_price.to_f,
    salary_tax_enabled: settings.salary_tax_enabled?
  },
  employees: Employee.order(:uid).map do |e|
    { uid: e.uid, name: e.name, monthly_salary: e.monthly_salary.to_f, device_admin: e.device_admin?,
      device_enabled: e.device_enabled?, hidden_from_export: e.hidden_from_export?,
      first_punch: e.punches.minimum(:punched_at)&.to_date&.to_s }
  end,
  punches: Punch.includes(:employee).order(:punched_at).map do |p|
    { uid: p.employee.uid, time: fmt.(p.punched_at), source: p.source, voided: p.voided?, note: p.note,
      created_by: p.created_by, s1: p.s1, s2: p.s2 }
  end,
  late_rules: LateRule.order(:effective_from).map { |r| { effective_from: r.effective_from.to_s, late_at: r.late_at } },
  holidays: Holiday.order(:starts_on).map { |h| { name: h.name, starts_on: h.starts_on.to_s, ends_on: h.ends_on.to_s } },
  working_saturdays: WorkingSaturday.order(:date).pluck(:date).map(&:to_s),
  comments: EmployeeComment.includes(:employee).map do |c|
    { uid: c.employee.uid, body: c.body, starts_on: c.starts_on.to_s, ends_on: c.ends_on.to_s, created_by: c.created_by }
  end,
  leaves: LeaveRequest.includes(:employee).order(:start_date).map do |l|
    { uid: l.employee.uid, leave_type: l.leave_type, start_date: l.start_date.to_s, end_date: l.end_date.to_s,
      reason: l.reason, status: l.status, reviewed_by: l.reviewed_by, admin_note: l.admin_note }
  end,
  parking: ParkingRequest.includes(:employee).order(:month).map do |q|
    { uid: q.employee.uid, month: q.month.to_s, vehicle_type: q.vehicle_type, vehicle_number: q.vehicle_number,
      price: q.price.to_f, status: q.status, reviewed_by: q.reviewed_by, reviewed_at: fmt.(q.reviewed_at),
      admin_note: q.admin_note }
  end
}

puts JSON.generate(data)
