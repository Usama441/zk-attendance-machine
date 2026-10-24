# frozen_string_literal: true

# Admin: office holidays and the Saturday rule (Settings → Holidays & Saturdays). Off days aren't
# counted as absent or late in payroll, the employee portal or the Excel export (see WorkCalendar).
class HolidaysController < ApplicationController
  def index
    @holidays  = Holiday.order(starts_on: :desc).to_a
    @settings  = AppSetting.current
    this_month = Date.today.beginning_of_month
    range      = (this_month << 1)..((this_month >> 3).end_of_month)
    @saturdays = range.select { |d| d.saturday? && WorkCalendar.off_saturday_slot?(d) }
    @working   = WorkingSaturday.where(date: range).pluck(:date).to_set
  end

  # POST /settings/saturdays/toggle  date=YYYY-MM-DD — make a 1st/3rd Saturday working, or off again.
  def toggle_saturday
    date = Date.parse(params[:date].to_s)
    if (ws = WorkingSaturday.find_by(date: date))
      ws.destroy!
      redirect_to holidays_path, notice: "#{date.strftime('%a %d %b %Y')} is an off day again."
    else
      WorkingSaturday.create!(date: date)
      redirect_to holidays_path, notice: "#{date.strftime('%a %d %b %Y')} is now a working day."
    end
  rescue Date::Error, ActiveRecord::RecordInvalid => e
    redirect_to holidays_path, alert: "Could not change that Saturday: #{e.message}"
  end

  # POST /settings/saturdays/rule  from=YYYY-MM-DD (blank = every Saturday off, rule not in use)
  def saturday_rule
    from = params[:from].presence && Date.parse(params[:from])
    AppSetting.current.update!(saturday_rule_from: from)
    redirect_to holidays_path, notice: from ? "Saturday rule applies from #{from.strftime('%d %b %Y')}." : "Saturday rule turned off — every Saturday is off."
  rescue Date::Error
    redirect_to holidays_path, alert: "Invalid date."
  end

  # POST /settings/holidays
  def create
    holiday = Holiday.new(holiday_params)
    if holiday.save
      redirect_to holidays_path, notice: "Holiday added: #{holiday.name}."
    else
      redirect_to holidays_path, alert: holiday.errors.full_messages.to_sentence
    end
  end

  # POST /settings/holidays/:id
  def update
    holiday = Holiday.find(params[:id])
    if holiday.update(holiday_params)
      redirect_to holidays_path, notice: "Saved #{holiday.name}."
    else
      redirect_to holidays_path, alert: holiday.errors.full_messages.to_sentence
    end
  end

  # POST /settings/holidays/:id/delete
  def destroy
    holiday = Holiday.find(params[:id])
    holiday.destroy!
    redirect_to holidays_path, notice: "Holiday #{holiday.name} removed."
  end

  private

  def holiday_params = params.permit(:name, :starts_on, :ends_on)
end
