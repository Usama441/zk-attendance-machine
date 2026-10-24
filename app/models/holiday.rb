# frozen_string_literal: true

# An office holiday over starts_on..ends_on (Settings → Holidays). On a holiday nobody is absent
# or late; anyone who punches in anyway counts as present.
class Holiday < ApplicationRecord
  validates :name, presence: true, length: { maximum: 80 }
  validates :starts_on, :ends_on, presence: true
  validate :ends_after_start

  scope :overlapping, ->(from, to) { where(starts_on: ..to.to_date, ends_on: from.to_date..) }

  # { Date => "Holiday name" } for every holiday date in from..to.
  def self.lookup(from, to)
    from = from.to_date
    to   = to.to_date
    overlapping(from, to).order(:starts_on).each_with_object({}) do |h, map|
      ([h.starts_on, from].max..[h.ends_on, to].min).each { |d| map[d] ||= h.name }
    end
  end

  def days = (ends_on - starts_on).to_i + 1

  private

  def ends_after_start
    errors.add(:ends_on, "must be on or after the start date") if starts_on && ends_on && ends_on < starts_on
  end
end
