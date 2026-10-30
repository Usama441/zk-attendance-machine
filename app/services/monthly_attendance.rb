# frozen_string_literal: true

# One employee's attendance for one calendar month, and the salary deduction it causes.
#
# Working days come from WorkCalendar: Mon–Fri plus the 2nd/4th/5th Saturday (same as the Excel matrix). A day runs 06:00 → 05:59 next morning
# (Punch::DAY_START_HOUR). For each working day up to today:
#   present / late  — at least one active punch; late when the first punch is at/after that
#                     day's late time (LateRule, Settings → Late time)
#   holiday         — office holiday (Holiday) with no punch: no deduction
#   leave           — approved paid leave (casual / sick / annual): no deduction
#   unpaid_leave    — approved unpaid leave: 1 day deducted
#   absent          — no punch and no approved leave: 1 day deducted
#
# Lates: every LATES_PER_DAY lates cost 1 day (3, 4 or 5 lates = 1 day; 6 lates = 2 days).
# Day rate = monthly salary / calendar days in the month.
# Income tax (TaxYear slabs): tax on (monthly salary × 12) ÷ 12 — worked out on the full salary,
# not on what's left after attendance deductions. Approved parking stickers for the month are
# taken after tax. Take-home = salary − attendance deduction − income tax − parking.
# Days before the employee's first ever punch are "not tracked" (not yet joined / no data).
class MonthlyAttendance
  LATES_PER_DAY = 3

  Day = Struct.new(:date, :status, :first_in, :last_out, :leave, :holiday, keyword_init: true)

  attr_reader :employee, :month, :days

  # tax_year / late_rules: pass TaxYear.applicable(month) / LateRule.schedule when building many
  # reports for the same month.
  # salary / apply_tax: the portal's salary calculator works out pay for an amount the employee
  # enters (stipends are calculated without income tax).
  # parking_fee: pass the month's approved sticker total when building many reports at once.
  def initialize(employee, month, today: Date.today, tax_year: :lookup, late_rules: LateRule.schedule,
                 salary: nil, apply_tax: true, parking_fee: :lookup)
    @employee = employee
    @month    = month.to_date.beginning_of_month
    @today    = today
    @tax_year = tax_year == :lookup ? TaxYear.applicable(@month) : tax_year
    @late_rules = late_rules
    @salary    = salary&.to_d
    @apply_tax = apply_tax
    @parking_fee = parking_fee == :lookup ? nil : parking_fee.to_d
    @days     = build_days
  end

  def count(status) = days.count { |d| d.status == status }

  # Late cut-off(s) in force this month, e.g. "08:50" or "09:15 until 05 Oct, 08:50 from 06 Oct".
  def late_time_label = @late_rules.describe(month, month.end_of_month)

  def lates          = count(:late)
  def absents        = count(:absent)
  def paid_leaves    = count(:leave)
  def unpaid_leaves  = count(:unpaid_leave)
  def holidays       = count(:holiday)
  def presents       = count(:present) + lates
  # Working days so far (WorkCalendar: Mon–Fri + 2nd/4th/5th Saturdays, minus holidays).
  def working_days   = days.count { |d| !off_day?(d) && %i[present late leave unpaid_leave absent].include?(d.status) }
  def off_days_worked = days.count { |d| off_day?(d) && d.first_in }
  def working_days_present = presents - off_days_worked

  # Working days with a check-in but no check-out, once that work day is over (the portal warns
  # the employee to report them to HR).
  def missing_punch_days(open_day = Punch.work_date(Time.current))
    days.select { |d| d.first_in && d.last_out.nil? && !off_day?(d) && d.date < open_day }
  end

  def late_deduction_days = lates / LATES_PER_DAY
  # Lates still needed before the next late-day deduction kicks in.
  def lates_to_next_deduction = LATES_PER_DAY - (lates % LATES_PER_DAY)
  def deduction_days = absents + unpaid_leaves + late_deduction_days

  def salary   = @salary || employee.monthly_salary.to_d
  def day_rate = salary / month.end_of_month.day
  def deduction_amount = [(day_rate * deduction_days).round(2), salary].min
  def net_salary = salary - deduction_amount

  attr_reader :tax_year
  # On the full monthly salary; never more than is actually paid out that month.
  def income_tax = tax_year && @apply_tax ? [tax_year.monthly_tax(salary), net_salary].min : 0.to_d

  # Approved parking stickers for this month (charged only after an admin approves them).
  def parking_fee = @parking_fee ||= employee.parking_requests.approved.for_month(month).sum(:price).to_d
  # What's actually taken: never more than is left after tax.
  def parking_deduction = [parking_fee, [net_salary - income_tax, 0].max].min
  def take_home  = net_salary - income_tax - parking_deduction

  # A past month is settled; the current month is a running total up to today.
  def final? = month.end_of_month < @today

  def off_day?(day) = @calendar.off_day?(day.date)

  private

  def build_days
    range   = month..month.end_of_month
    punches = employee.punches.active.on_work_days(range.first, range.last).order(:punched_at)
                      .group_by(&:work_date)
    leaves  = employee.leave_requests.open.overlapping(range.first, range.last).to_a
    first_seen = employee.punches.active.minimum(:punched_at)&.then { |t| Punch.work_date(t) }
    @calendar = WorkCalendar.new(range.first, range.last)
    holidays  = @calendar.holidays

    range.map do |date|
      times = (punches[date] || []).map(&:punched_at)
      # Prefer an approved leave over a pending one on the same day.
      leave = leaves.select { |l| l.covers?(date) }.min_by { |l| l.approved? ? 0 : 1 }
      Day.new(date: date, status: status_for(date, times, leave, first_seen, holidays[date]),
              first_in: times.first, last_out: (times.last if times.size > 1), leave: leave,
              holiday: holidays[date])
    end
  end

  def status_for(date, times, leave, first_seen, holiday)
    return :upcoming if date > @today

    weekend = @calendar.weekend?(date)
    off_day = weekend || holiday
    return (!off_day && @late_rules.late?(date, times.first) ? :late : :present) if times.any?
    return :weekend if weekend
    return :holiday if holiday
    return (leave.unpaid? ? :unpaid_leave : :leave) if leave&.approved?
    return :today if date == @today # the day isn't over yet
    return :not_tracked if first_seen.nil? || date < first_seen

    :absent
  end
end
