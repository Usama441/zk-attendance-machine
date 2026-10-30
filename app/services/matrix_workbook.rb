# frozen_string_literal: true
require "caxlsx"

# Single-sheet attendance MATRIX:
#   rows  = employees (Sr No, Name, Comments, Employee Code)
#   cols  = one block per calendar day in [from..to], each block = IN | OUT
# Colouring: header dark blue, off days (WorkCalendar: Sundays, 1st/3rd Saturdays, holidays) grey, late first-punch (at/after that day's
# LateRule cut-off) yellow,
# approved leave on a working day without punches green (paid) or orange (unpaid), with the leave
# type written across IN|OUT, absent working days pink. Employees with no punch at all in the range are still listed,
# with their name/code cells in red. Timestamps are read from the device, never altered.
class MatrixWorkbook
  # records respond to #uid, #name, #time.
  # names        : { uid => full name }        (falls back to device name)
  # comments     : { uid => comment text }     (optional; blank if missing)
  # uids         : employees to list even without punches (absent rows)
  # leaves       : { uid => { date => approved LeaveRequest } }
  def initialize(records, from:, to:, names: {}, comments: {}, uids: [], leaves: {}, late_rules: LateRule.schedule,
                 calendar: WorkCalendar.new(from, to))
    @records      = records
    @late_rules   = late_rules
    @calendar     = calendar
    @holidays     = calendar.holidays
    @uids         = uids
    @from         = from.to_date
    @to           = to.to_date
    @names        = names
    @comments     = comments
    @leaves       = leaves
  end

  def to_stream
    pkg = Axlsx::Package.new
    wb  = pkg.workbook
    s   = styles(wb)

    days    = (@from..@to).to_a
    per     = group           # uid => date => [times]
    order   = (per.keys | @uids).sort_by { |uid| [name_for(uid).downcase, uid] }

    wb.add_worksheet(name: "Attendance") do |sh|
      add_header(sh, s, days)
      order.each_with_index { |uid, i| add_employee_row(sh, s, i + 1, uid, per.fetch(uid, nil), days) }

      freeze(sh)
      sh.column_widths(*([5, 24, 30, 13] + Array.new(days.size * 2, 10)))
    end

    pkg.to_stream.read
  end

  private

  FIXED = ["Sr. No.", "Employee Name", "Comments", "Employee Code"].freeze

  def styles(wb)
    thin = { style: :thin, color: "FFFFFF" }
    grid = { style: :thin, color: "A6A6A6" }
    {
      hdr:    wb.styles.add_style(bg_color: "1F4E78", fg_color: "FFFFFF", b: true, sz: 9,
                                  alignment: { horizontal: :center, vertical: :center }, border: thin),
      hdr_we: wb.styles.add_style(bg_color: "6B7480", fg_color: "FFFFFF", b: true, sz: 9,
                                  alignment: { horizontal: :center, vertical: :center }, border: thin),
      name:   wb.styles.add_style(border: grid, sz: 9, alignment: { vertical: :center }),
      ctr:    wb.styles.add_style(border: grid, sz: 9, alignment: { horizontal: :center, vertical: :center }),
      ok:     wb.styles.add_style(border: grid, sz: 9, alignment: { horizontal: :center, vertical: :center }),
      late:   wb.styles.add_style(border: grid, sz: 9, bg_color: "FFD966",
                                  alignment: { horizontal: :center, vertical: :center }),
      we:     wb.styles.add_style(border: grid, sz: 9, bg_color: "BFC5CC",
                                  alignment: { horizontal: :center, vertical: :center }),
      absent: wb.styles.add_style(border: grid, sz: 9, bg_color: "F4A6A6",
                                  alignment: { horizontal: :center, vertical: :center }),
      leave:  wb.styles.add_style(border: grid, sz: 9, bg_color: "C6EFCE", fg_color: "006100",
                                  alignment: { horizontal: :center, vertical: :center }),
      unpaid: wb.styles.add_style(border: grid, sz: 9, bg_color: "F8CBAD", fg_color: "833C0B",
                                  alignment: { horizontal: :center, vertical: :center }),
      # employee with no punches in the whole range
      abs_name: wb.styles.add_style(border: grid, sz: 9, bg_color: "E06666", fg_color: "FFFFFF", b: true,
                                    alignment: { vertical: :center }),
      abs_ctr:  wb.styles.add_style(border: grid, sz: 9, bg_color: "E06666", fg_color: "FFFFFF", b: true,
                                    alignment: { horizontal: :center, vertical: :center }),
    }
  end

  def group
    h = Hash.new { |a, uid| a[uid] = Hash.new { |b, d| b[d] = [] } }
    @records.each { |r| h[r.uid][Punch.work_date(r.time)] << r.time }
    h
  end

  def name_for(uid)
    @names[uid] || @records.find { |r| r.uid == uid }&.name || uid.to_s
  end

  def weekend?(d) = @calendar.weekend?(d)
  # Weekend or office holiday: grey, never absent or late.
  def off_day?(d) = weekend?(d) || @holidays.key?(d)


  # ---- header: 3 stacked rows with merges ----
  def add_header(sh, s, days)
    row1 = FIXED.dup;        row2 = ["", "", "", ""]; row3 = ["", "", "", ""]
    st1  = [s[:hdr]] * 4;    st2  = [s[:hdr]] * 4;    st3  = [s[:hdr]] * 4
    days.each do |d|
      h = off_day?(d) ? s[:hdr_we] : s[:hdr]
      row1 << d.strftime("%b %-d") << nil; st1 << h << h
      row2 << (@holidays[d] ? "Holiday: #{@holidays[d]}" : d.strftime("%a")) << nil; st2 << h << h
      row3 << "IN" << "OUT";               st3 << h << h
    end
    sh.add_row row1, style: st1, height: 15
    sh.add_row row2, style: st2, height: 14
    sh.add_row row3, style: st3, height: 14

    # merge the 4 fixed columns vertically, and each day's date/weekday across IN|OUT
    (0..3).each { |c| sh.merge_cells("#{col(c)}1:#{col(c)}3") }
    days.each_with_index do |_, k|
      a = col(4 + 2 * k); b = col(5 + 2 * k)
      sh.merge_cells("#{a}1:#{b}1")
      sh.merge_cells("#{a}2:#{b}2")
    end
  end

  def add_employee_row(sh, s, sr, uid, day_map, days)
    cells  = [sr, name_for(uid), @comments[uid].to_s, uid]
    row_st = if day_map.nil? || day_map.empty?
               [s[:abs_ctr], s[:abs_name], s[:abs_name], s[:abs_ctr]]
             else
               [s[:ctr], s[:name], s[:name], s[:ctr]]
             end

    leave_cols = []
    days.each_with_index do |d, k|
      times = (day_map && day_map[d] || []).sort
      leave = @leaves.dig(uid, d) unless off_day?(d)
      if times.empty? && leave
        # Same rule as MonthlyAttendance: punches win, then off days, then approved leave.
        cells << leave.type_label << ""
        st = leave.unpaid? ? s[:unpaid] : s[:leave]
        row_st << st << st
        leave_cols << k
      elsif times.empty?
        cells << "" << ""
        base = off_day?(d) ? s[:we] : s[:absent]
        row_st << base << base
      else
        first = times.first
        last  = times.size > 1 ? times.last : nil
        cells << first.strftime("%I:%M %p")
        cells << (last ? last.strftime("%I:%M %p") : "")
        in_st  = !off_day?(d) && @late_rules.late?(d, first) ? s[:late] : (off_day?(d) ? s[:we] : s[:ok])
        out_st = off_day?(d) ? s[:we] : s[:ok]
        row_st << in_st << out_st
      end
    end
    sh.add_row cells, style: row_st, height: 14
    r = sr + 3 # below the 3 header rows
    leave_cols.each { |k| sh.merge_cells("#{col(4 + 2 * k)}#{r}:#{col(5 + 2 * k)}#{r}") }
  end

  def freeze(sh)
    sh.sheet_view.pane do |p|
      p.state = :frozen
      p.x_split = 4
      p.y_split = 3
      p.top_left_cell = "E4"
    end
  end

  # 0-based column index -> Excel letters (0 => "A")
  def col(i)
    n = i + 1
    out = +""
    while n.positive?
      n, r = (n - 1).divmod(26)
      out.prepend((65 + r).chr)
    end
    out
  end
end
