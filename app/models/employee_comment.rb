# frozen_string_literal: true

# A comment on an employee for starts_on..ends_on (Comments page). It appears in the Comments
# column of any export whose date range overlaps it, and is deleted the day after ends_on.
class EmployeeComment < ApplicationRecord
  belongs_to :employee

  validates :body, presence: true, length: { maximum: 500 }
  validates :starts_on, :ends_on, presence: true
  validate :ends_after_start

  scope :overlapping, ->(from, to) { where(starts_on: ..to.to_date, ends_on: from.to_date..) }

  # Called on every page load of Comments, every export and every sync.
  def self.purge_expired!(today = Date.today) = where(ends_on: ...today).delete_all

  # { uid => "comment; comment" } for comments overlapping from..to.
  def self.by_uid(from, to)
    overlapping(from, to).includes(:employee).order(:starts_on, :id)
                         .group_by { |c| c.employee.uid }
                         .transform_values { |list| list.map(&:body).join("; ") }
  end

  private

  def ends_after_start
    errors.add(:ends_on, "must be on or after the start date") if starts_on && ends_on && ends_on < starts_on
  end
end
