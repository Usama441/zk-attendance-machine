# frozen_string_literal: true

# A 1st or 3rd Saturday (off by default) that an admin has turned into a working day
# (Settings → Holidays & Saturdays). See WorkCalendar.
class WorkingSaturday < ApplicationRecord
  validates :date, presence: true, uniqueness: true
  validate :off_saturday

  private

  def off_saturday
    return if date.nil?

    errors.add(:date, "must be a 1st or 3rd Saturday") unless date.saturday? && WorkCalendar.off_saturday_slot?(date)
  end
end
