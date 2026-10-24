module ApplicationHelper
  DAY_STATUS = {
    present:      ["Present",      "present"],
    late:         ["Late",         "late"],
    absent:       ["Absent",       "absent"],
    leave:        ["Leave",        "leave"],
    unpaid_leave: ["Unpaid leave", "absent"],
    weekend:      ["Weekend",      "muted-tag"],
    holiday:      ["Holiday",      "holiday"],
    today:        ["Today",        "muted-tag"],
    not_tracked:  ["Not tracked",  "muted-tag"],
    upcoming:     ["—",            "muted-tag"]
  }.freeze

  # The 4 attendance cards (Present / Late / Absent / Leave) for a MonthlyAttendance, shared by
  # the admin employee page and the employee portal. Render with shared/stats.
  def attendance_stat_items(r)
    [
      { label: "Present", value: r.presents, icon: "i-check", tone: :green,
        foot: "#{r.working_days_present} of #{pluralize(r.working_days, 'working day')}" \
              "#{" · +#{r.off_days_worked} on weekends/holidays" if r.off_days_worked.positive?}" },
      { label: "Late", value: r.lates, icon: "i-clock", tone: :amber,
        foot: "First punch at or after #{r.late_time_label}" },
      { label: "Absent", value: r.absents, icon: "i-x", tone: :red,
        foot: "Working days with no punch" },
      { label: "Leave", value: r.paid_leaves + r.unpaid_leaves, icon: "i-plane",
        foot: "#{r.paid_leaves} paid · #{r.unpaid_leaves} unpaid#{" · #{pluralize(r.holidays, 'holiday')}" if r.holidays.positive?}" }
    ]
  end

  # Initials badge, or the employee's machine photo when one has been pulled.
  # One query per request for the whole photo list, so tables don't do N+1 lookups.
  def avatar(employee, css = "person-avatar")
    @photo_versions ||= EmployeePhoto.pluck(:employee_id, :fetched_at).to_h
    version = @photo_versions[employee.id]
    return content_tag(:span, employee.initials, class: css) unless version

    content_tag(:span, class: "#{css} has-photo") do
      image_tag(employee_photo_path(employee, v: version.to_i), alt: "", loading: "lazy")
    end
  end

  def money(amount)
    number_to_currency(amount, unit: "Rs ", precision: 2, format: "%u%n")
  end

  def day_status_tag(status)
    label, css = DAY_STATUS.fetch(status)
    content_tag(:span, label, class: "tag #{css}")
  end

  def leave_status_tag(leave)
    content_tag(:span, leave.status, class: "tag leave-#{leave.status}")
  end

  def leave_dates(leave)
    return leave.start_date.strftime("%a, %d %b %Y") if leave.start_date == leave.end_date

    "#{leave.start_date.strftime('%d %b')} → #{leave.end_date.strftime('%d %b %Y')}"
  end

  def punch_time(time)
    time ? time.strftime("%I:%M %p") : content_tag(:span, "—", class: "muted")
  end
end
