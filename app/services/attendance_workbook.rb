# frozen_string_literal: true
require "caxlsx"

# Builds a formatted, cross-linked .xlsx from records that respond to #uid, #name, #time.
# Sheets: "Daily Summary", "By User" (totals, with Ctrl+Click links to each person's sheet),
# and one sheet per user (each with a "Back to By User" link).
# Late arrivals (first punch at/after that day's LateRule cut-off) are highlighted; timestamps
# are never altered.
class AttendanceWorkbook
  BY_USER = "By User"

  def initialize(records, names: {}, late_rules: LateRule.schedule)
    @records    = records
    @names      = names
    @late_rules = late_rules
  end

  # Returns the .xlsx as a binary String (ready for send_data).
  def to_stream
    pkg = Axlsx::Package.new
    wb  = pkg.workbook
    s   = build_styles(wb)

    per_user = group_by_user_day
    order    = per_user.keys.sort_by { |uid| [display_name(uid).downcase, uid] }
    @sheet_of = assign_sheet_names(order)

    add_daily_summary(wb, s, per_user, order)
    add_by_user(wb, s, per_user, order)
    order.each { |uid| add_user_sheet(wb, s, uid, per_user[uid]) }

    pkg.to_stream.read
  end

  private

  def build_styles(wb)
    {
      hdr:  wb.styles.add_style(bg_color: "1F4E78", fg_color: "FFFFFF", b: true,
                                alignment: { horizontal: :center }, border: { style: :thin, color: "FFFFFF" }),
      hdrg: wb.styles.add_style(bg_color: "2E7D32", fg_color: "FFFFFF", b: true,
                                alignment: { horizontal: :center }, border: { style: :thin, color: "FFFFFF" }),
      cell: wb.styles.add_style(border: { style: :thin, color: "A6A6A6" }),
      band: wb.styles.add_style(border: { style: :thin, color: "A6A6A6" }, bg_color: "C9DAF0"),
      late: wb.styles.add_style(border: { style: :thin, color: "A6A6A6" }, bg_color: "F4A6A6", fg_color: "8B0000"),
      link: wb.styles.add_style(border: { style: :thin, color: "A6A6A6" }, bg_color: "FFE699",
                                fg_color: "0B5394", b: true, u: true),
      back: wb.styles.add_style(fg_color: "0B5394", b: true, u: true),
    }
  end

  # uid => { Date => [times...] }
  def group_by_user_day
    h = Hash.new { |a, uid| a[uid] = Hash.new { |b, d| b[d] = [] } }
    @records.each { |r| h[r.uid][Punch.work_date(r.time)] << r.time }
    h
  end

  def display_name(uid)
    @names[uid] || @records.find { |r| r.uid == uid }&.name || uid.to_s
  end

  # Unique, Excel-safe (<=31 char) sheet name per user, computed up-front so links can target them.
  def assign_sheet_names(order)
    used = { "daily summary" => true, BY_USER.downcase => true }
    order.each_with_object({}) do |uid, map|
      base = "#{uid}-#{display_name(uid)}".gsub(%r{[:\\/?*\[\]']}, " ").strip.slice(0, 31)
      name = base
      i = 2
      while used[name.downcase]
        name = "#{base.slice(0, 28)}~#{i}"
        i += 1
      end
      used[name.downcase] = true
      map[uid] = name
    end
  end

  def span(times)
    return "0:00" if times.size < 2
    secs = (times.max - times.min).to_i
    format("%d:%02d", secs / 3600, (secs % 3600) / 60)
  end

  def late?(first) = @late_rules.late?(Punch.work_date(first), first)

  def row_style(s, first_time, banded)
    return s[:late] if late?(first_time)
    banded ? s[:band] : s[:cell]
  end

  def add_daily_summary(wb, s, per_user, order)
    wb.add_worksheet(name: "Daily Summary") do |sh|
      sh.add_row ["Date", "UserID", "Name", "First In", "Last Out", "Punches", "Hours (span)"], style: s[:hdr]
      i = 0
      order.each do |uid|
        name = display_name(uid)
        per_user[uid].keys.sort.each do |d|
          t  = per_user[uid][d].sort
          st = row_style(s, t.first, i.odd?)
          sh.add_row [d.to_s, uid, name, t.first.strftime("%H:%M:%S"),
                      (t.size > 1 ? t.last.strftime("%H:%M:%S") : ""), t.size, span(t)],
                     style: [st, st, st, st, st, st, st]
          i += 1
        end
      end
      sh.column_widths 12, 8, 20, 10, 10, 8, 12
    end
  end

  def add_by_user(wb, s, per_user, order)
    wb.add_worksheet(name: BY_USER) do |sh|
      sh.add_row ["UserID", "Name (Ctrl+Click to open)", "Days Present", "Total Punches",
                  "Late Days", "First Day", "Last Day"], style: s[:hdrg]
      order.each_with_index do |uid, i|
        days  = per_user[uid].keys.sort
        total = per_user[uid].values.sum(&:size)
        late  = days.count { |d| late?(per_user[uid][d].min) }
        st    = i.odd? ? s[:band] : s[:cell]
        sh.add_row [uid, display_name(uid), days.size, total, late, days.first.to_s, days.last.to_s],
                   style: [s[:link], s[:link], st, st, st, st, st]

        excel_row = i + 2 # header is row 1
        target = "'#{@sheet_of[uid]}'!A1"
        sh.add_hyperlink location: target, ref: "A#{excel_row}", target: :internal
        sh.add_hyperlink location: target, ref: "B#{excel_row}", target: :internal
      end
      sh.column_widths 8, 24, 12, 14, 18, 12, 12
    end
  end

  def add_user_sheet(wb, s, uid, day_map)
    wb.add_worksheet(name: @sheet_of[uid]) do |sh|
      sh.add_row ["← Back to By User", "", "", "", "", ""], style: [s[:back]]
      sh.add_hyperlink location: "'#{BY_USER}'!A1", ref: "A1", target: :internal

      sh.add_row ["Date", "First In", "Last Out", "Punches", "Hours (span)", "All Punch Times"], style: s[:hdr]

      day_map.keys.sort.each_with_index do |d, i|
        t  = day_map[d].sort
        st = row_style(s, t.first, i.odd?)
        sh.add_row [d.to_s, t.first.strftime("%H:%M:%S"),
                    (t.size > 1 ? t.last.strftime("%H:%M:%S") : ""), t.size, span(t),
                    t.map { |x| x.strftime("%H:%M") }.join(" ")],
                   style: [st, st, st, st, st, st]
      end
      sh.column_widths 12, 10, 10, 8, 12, 40
    end
  end
end
