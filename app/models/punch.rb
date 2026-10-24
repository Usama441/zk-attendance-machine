class Punch < ApplicationRecord
  belongs_to :employee

  # A work day runs 06:00 → 05:59 next morning, so a checkout after midnight (e.g. 01:23 after a
  # late night) belongs to the previous day instead of becoming the next day's check-in.
  DAY_START_HOUR = 6

  scope :active,  -> { where(voided: false) }
  scope :between, ->(from, to) {
    where(punched_at: from.beginning_of_day..to.end_of_day)
  }
  # Punches belonging to the work days from..to (see DAY_START_HOUR).
  scope :on_work_days, ->(from, to) {
    where(punched_at: work_day_start(from)...work_day_start(to.to_date + 1))
  }

  def self.work_day_start(date) = date.to_date.beginning_of_day + DAY_START_HOUR.hours
  def self.work_date(time) = (time - DAY_START_HOUR.hours).to_date

  def work_date = self.class.work_date(punched_at)

  def manual? = source == "manual"

  # Preserve the original punch for audit, exclude it from reports, and create
  # a manual replacement atomically.
  def replace_with!(punched_at:, note:, created_by:)
    replacement = nil

    with_lock do
      raise ArgumentError, "a voided punch cannot be corrected" if voided?

      replacement = employee.punches.create!(
        punched_at: punched_at,
        source: "manual",
        note: note,
        created_by: created_by,
        voided: false
      )
      update!(voided: true)
    end

    replacement
  end
end
