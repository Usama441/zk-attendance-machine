# frozen_string_literal: true

# Manual attendance corrections (admin only — every logged-in user is a device admin).
# Use cases: someone forgot to punch, or clocked in on another person's finger.
# Corrections are auditable: manual punches carry source="manual", a note and the
# admin who made them; wrong punches are *voided* (not deleted) so the raw log stays intact.
class CorrectionsController < ApplicationController
  MAX_BULK_DAYS = 366

  def index
    @employees = Employee.order(:name)
    @employee  = Employee.find_by(id: params[:employee_id])
    @from, @to = view_range
    @punches   = @employee ? @employee.punches.between(@from, @to).order(:punched_at) : []
    @punches_by_day = @punches.group_by { |p| p.punched_at.to_date }
  end

  # Add a missing punch for an employee at a given date + time.
  def create
    emp = Employee.find(params[:employee_id])
    at  = Time.find_zone("UTC").parse("#{params[:date]} #{params[:time]}")
    raise ArgumentError, "invalid date/time" if at.nil?

    Punch.create!(employee: emp, punched_at: at, source: "manual",
                  note: params[:note].presence, created_by: current_admin, voided: false)
    redirect_to back_path(emp.id), notice: "Added #{at.strftime('%d %b %I:%M %p')} for #{emp.name}."
  rescue ActiveRecord::RecordNotUnique
    redirect_to back_path, alert: "A punch already exists for that employee at that exact time."
  rescue => e
    redirect_to back_path, alert: "Could not add punch: #{e.message}"
  end

  # Add the same punch time(s) to every day across one or more date ranges.
  def bulk_create
    emp   = Employee.find(params[:employee_id])
    times = Array(params[:times]).map(&:strip).reject(&:blank?).uniq
    raise ArgumentError, "add at least one time" if times.empty?

    days = bulk_days
    raise ArgumentError, "add at least one valid date range" if days.empty?
    raise ArgumentError, "too many days (max #{MAX_BULK_DAYS})" if days.size > MAX_BULK_DAYS

    note = params[:note].presence || "Bulk correction"
    added = skipped = 0
    Punch.transaction do
      days.each do |day|
        times.each do |t|
          at = Time.find_zone("UTC").parse("#{day} #{t}")
          raise ArgumentError, "invalid time #{t}" if at.nil?

          if emp.punches.exists?(punched_at: at)
            skipped += 1
          else
            emp.punches.create!(punched_at: at, source: "manual", note: note,
                                created_by: current_admin, voided: false)
            added += 1
          end
        end
      end
    end

    msg = "Added #{added} punch(es) over #{days.size} day(s) for #{emp.name}."
    msg += " Skipped #{skipped} that already existed." if skipped.positive?
    redirect_to corrections_path(employee_id: emp.id, from: days.first, to: days.last), notice: msg
  rescue => e
    redirect_to back_path, alert: "Could not add punches: #{e.message}"
  end

  # Replace a punch time without deleting the raw device record.
  def replace
    original = Punch.find(params[:punch_id])
    raise ArgumentError, "time is required" if params[:time].blank?

    at = Time.find_zone("UTC").parse("#{original.punched_at.to_date} #{params[:time]}")
    raise ArgumentError, "invalid time" if at.nil?

    replacement = original.replace_with!(punched_at: at, note: nil, created_by: current_admin)

    redirect_to back_path(original.employee_id),
                notice: "Corrected #{original.punched_at.strftime('%I:%M %p')} to #{replacement.punched_at.strftime('%I:%M %p')}."
  rescue ActiveRecord::RecordNotUnique
    redirect_to back_path, alert: "A punch already exists at that corrected time."
  rescue => e
    redirect_to back_path, alert: "Could not correct punch: #{e.message}"
  end

  # Void (or restore) a punch — e.g. one recorded on the wrong person's finger.
  def void
    p = Punch.find(params[:punch_id])
    p.update!(voided: !p.voided)
    redirect_to back_path(p.employee_id),
                notice: (p.voided ? "Punch voided (excluded from reports)." : "Punch restored.")
  end

  private

  # Range being viewed; accepts from/to, or a single legacy `date`.
  def view_range
    from = parse_date(params[:from]) || parse_date(params[:date]) || Date.today
    to   = parse_date(params[:to]) || parse_date(params[:date]) || from
    from, to = to, from if to < from
    [from, to]
  end

  def back_path(employee_id = params[:employee_id])
    from, to = view_range
    corrections_path(employee_id: employee_id, from: from, to: to)
  end

  # Unique, sorted days across all submitted ranges, minus skipped weekdays.
  def bulk_days
    skip = Array(params[:skip_wdays]).map(&:to_i)
    ranges = params[:ranges].respond_to?(:values) ? params[:ranges].values : Array(params[:ranges])
    ranges.flat_map do |r|
      from = parse_date(r[:from])
      to   = parse_date(r[:to]) || from
      next [] unless from

      from, to = to, from if to < from
      raise ArgumentError, "range #{from} → #{to} is too long" if (to - from) >= MAX_BULK_DAYS

      (from..to).to_a
    end.uniq.sort.reject { |d| skip.include?(d.wday) }
  end

  def parse_date(v)
    Date.parse(v.to_s) if v.present?
  rescue Date::Error
    nil
  end
end
