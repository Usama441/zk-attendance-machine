# frozen_string_literal: true

class ExportsController < ApplicationController
  Row = Struct.new(:uid, :name, :time, :s1, :s2, keyword_init: true)

  # GET / — the form.
  def index
    @default_start = default_start
    @default_end   = Date.today.to_s
    @employees     = Employee.order(:name)
    @stats         = dashboard_stats
    @settings      = AppSetting.current
  end

  # POST /sync — pull fresh data from the device into Postgres.
  def sync
    settings = AppSetting.current
    automatic = params[:automatic] == "1"

    if automatic
      claimed = settings.with_lock do
        next false unless settings.auto_sync_due?

        settings.update!(
          last_sync_at: Time.current,
          last_sync_status: "running",
          last_sync_message: "Automatic sync is running."
        )
        true
      end

      unless claimed
        render json: {
          ok: true,
          skipped: true,
          message: "Auto-sync is disabled or not due yet.",
          stats: serialized_stats
        }
        return
      end
    end

    from, to = automatic ? settings.auto_range : range
    validate_range!(from, to)
    result = SyncService.new(client: zk_client).sync(from.to_s, to.to_s)
    message = "Synced #{result[:employees]} employees, #{result[:punches_added]} new punches " \
              "(#{result[:punches_seen]} seen) for #{from} → #{to}."
    settings.update(last_sync_at: Time.current, last_sync_status: "success", last_sync_message: message)
    EmployeeComment.purge_expired!

    respond_to do |format|
      format.html { redirect_to root_path, notice: message }
      format.json { render json: { ok: true, message: message, stats: serialized_stats } }
    end
  rescue ZkClient::Error => e
    sync_error("Device error: #{e.message}", :bad_gateway)
  rescue ArgumentError => e
    sync_error("Invalid date range: #{e.message}", :unprocessable_entity)
  end

  # POST /export — build the .xlsx from stored data.
  def export
    from, to = range

    scope = Punch.active.includes(:employee).on_work_days(from, to)
    if params[:mode] == "single" && params[:employee_id].present?
      # An explicitly chosen employee is exported even if hidden in Settings.
      employees = Employee.where(id: params[:employee_id])
    else
      employees = Employee.exportable
    end
    scope = scope.where(employee_id: employees.select(:id))
    # Every selected employee gets a row, so those with no punches show up as absent.
    uids = employees.pluck(:uid)

    rows = scope.map do |p|
      Row.new(uid: p.employee.uid, name: p.employee.name, time: p.punched_at, s1: p.s1, s2: p.s2)
    end

    if rows.empty? && uids.empty?
      redirect_to root_path, alert: "No stored employees for that selection. Try 'Sync from device' first."
      return
    end

    names = Employee.pluck(:uid, :name).to_h
    EmployeeComment.purge_expired!
    comments = EmployeeComment.by_uid(from, to)
    leaves = approved_leaves(employees, from, to)

    if params[:mode] == "separate"
      send_data separate_workbooks_zip(rows, uids, from: from, to: to, names: names, comments: comments, leaves: leaves),
        filename: export_filename(from, ext: "zip"),
        type: "application/zip",
        disposition: "attachment"
      return
    end

    # Both bulk and single-employee use the same single-sheet IN/OUT matrix
    # (a single export is just the matrix filtered to one row).
    data = MatrixWorkbook.new(rows, from: from, to: to, names: names, comments: comments, uids: uids,
                              leaves: leaves).to_stream

    send_data data,
      filename: export_filename(from),
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      disposition: "attachment"
  end

  private

  # One .xlsx per employee (same matrix as the single-employee export), bundled into a .zip.
  # Punches, comments, leaves and the work calendar are loaded once and split per employee.
  def separate_workbooks_zip(rows, uids, from:, to:, names:, comments:, leaves:)
    require "zip"
    by_uid     = rows.group_by(&:uid)
    calendar   = WorkCalendar.new(from, to)
    late_rules = LateRule.schedule
    month      = from.strftime("%Y-%m")

    buffer = Zip::OutputStream.write_buffer do |zip|
      uids.uniq.sort_by { |uid| [names[uid].to_s.downcase, uid] }.each do |uid|
        sheet = MatrixWorkbook.new(by_uid.fetch(uid, []), from: from, to: to, names: names,
                                   comments: comments.slice(uid), uids: [uid], leaves: leaves.slice(uid),
                                   late_rules: late_rules, calendar: calendar).to_stream
        safe_name = names[uid].to_s.gsub(/[^\w\- ]/, "").strip.tr(" ", "_").presence || "employee"
        zip.put_next_entry("attendance-log-#{uid}-#{safe_name}-#{month}.xlsx")
        zip.write(sheet)
      end
    end
    buffer.string
  end

  # { uid => { date => leave } } for approved leaves in the range, so the sheet can colour them.
  def approved_leaves(employees, from, to)
    LeaveRequest.includes(:employee).where(status: "approved", employee_id: employees.select(:id))
                .overlapping(from, to).each_with_object(Hash.new { |h, k| h[k] = {} }) do |l, out|
      ([l.start_date, from].max..[l.end_date, to].min).each { |d| out[l.employee.uid][d] = l }
    end
  end

  # Default the range to the current month so both pickers open on today's month
  # (From = first of this month, To = today).
  def default_start
    Date.today.beginning_of_month.to_s
  end

  def range
    from = params[:sdate].presence ? Date.parse(params[:sdate]) : Date.parse(default_start)
    to   = params[:edate].presence ? Date.parse(params[:edate]) : Date.today
    [from, to]
  end

  def validate_range!(from, to)
    raise ArgumentError, "start date must not be after end date" if from > to
    raise ArgumentError, "range cannot exceed 365 days" if (to - from).to_i >= 365
  end

  def dashboard_stats
    {
      employees: Employee.count,
      punches:   Punch.count,
      last:      Punch.maximum(:punched_at)
    }
  end

  def serialized_stats
    stats = dashboard_stats
    {
      employees: stats[:employees],
      punches: stats[:punches],
      last: stats[:last]&.strftime("%Y-%m-%d %H:%M")
    }
  end

  def sync_error(message, status)
    AppSetting.current.update(last_sync_at: Time.current, last_sync_status: "error", last_sync_message: message)

    if request.format.json?
      render json: { ok: false, message: message }, status: status
    else
      redirect_to root_path, alert: message
    end
  end

  # Filename template:  attendance-log-<YYYY-MM>-<YYYYMMDD>-<HHMMSS>.xlsx
  #   <YYYY-MM>  = month of the report period (range start)
  #   <...>      = when the export was generated (local time, TZ_OFFSET default +05:00)
  # Single-employee exports insert the user id:  attendance-log-<uid>-<YYYY-MM>-...
  # Separate-files exports are a zip:  attendance-logs-separate-<YYYY-MM>-<YYYYMMDD>-<HHMMSS>.zip
  def export_filename(from, ext: "xlsx")
    month = from.strftime("%Y-%m")
    gen   = Time.now.getlocal(ENV.fetch("TZ_OFFSET", "+05:00")).strftime("%Y%m%d-%H%M%S")
    if params[:mode] == "single" && params[:employee_id].present?
      uid = Employee.find(params[:employee_id]).uid
      "attendance-log-#{uid}-#{month}-#{gen}.#{ext}"
    elsif params[:mode] == "separate"
      "attendance-logs-separate-#{month}-#{gen}.#{ext}"
    else
      "attendance-log-#{month}-#{gen}.#{ext}"
    end
  end
end
