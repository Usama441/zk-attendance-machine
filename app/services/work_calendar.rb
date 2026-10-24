# frozen_string_literal: true

# Which days are off: every Sunday, the 1st and 3rd Saturday of each month (unless an admin made
# that Saturday a working day, WorkingSaturday), and office holidays (Holiday). 2nd, 4th and 5th
# Saturdays are working days. Before AppSetting#saturday_rule_from every Saturday is off.
# Payroll (MonthlyAttendance) and the Excel export (MatrixWorkbook) both ask this class.
class WorkCalendar
  OFF_SATURDAYS = [1, 3].freeze

  # 1 for the first Saturday of the month, 2 for the second, …
  def self.nth_weekday(date) = (date.day - 1) / 7 + 1
  def self.off_saturday_slot?(date) = OFF_SATURDAYS.include?(nth_weekday(date))

  attr_reader :holidays

  def initialize(from, to)
    from = from.to_date
    to   = to.to_date
    @holidays = Holiday.lookup(from, to)
    @working_saturdays = WorkingSaturday.where(date: from..to).pluck(:date).to_set
    @rule_from = AppSetting.current.saturday_rule_from
  end

  def weekend?(date)
    return true if date.sunday?
    return false unless date.saturday?

    saturday_off?(date)
  end

  def saturday_off?(date)
    return true if @rule_from.nil? || date < @rule_from

    self.class.off_saturday_slot?(date) && !@working_saturdays.include?(date)
  end

  def holiday(date) = @holidays[date]
  def off_day?(date) = weekend?(date) || @holidays.key?(date)
end
