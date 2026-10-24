# frozen_string_literal: true

# Late cut-off time from a date onward (Settings → Late time). A day's first punch at or after
# the cut-off in force that day counts as late. Days before the first rule use the first rule.
class LateRule < ApplicationRecord
  DEFAULT = "08:50"

  validates :effective_from, presence: true, uniqueness: true
  validates :late_at, format: { with: /\A([01]\d|2[0-3]):[0-5]\d\z/, message: "must be a time like 08:50" }

  # All rules loaded once; use this when checking many days.
  def self.schedule = Schedule.new(order(:effective_from).pluck(:effective_from, :late_at))

  class Schedule
    def initialize(rules) = @rules = rules

    # "HH:MM" cut-off in force on date.
    def cutoff(date)
      date = date.to_date
      (@rules.reverse.find { |from, _| from <= date } || @rules.first)&.last || DEFAULT
    end

    def late?(date, time) = time.strftime("%H:%M") >= cutoff(date)

    # Cut-offs in force during from..to, e.g. "09:15 until 05 Oct, 08:50 from 06 Oct".
    def describe(from, to)
      changes = @rules.select { |d, _| d > from.to_date && d <= to.to_date }
      return cutoff(from) if changes.empty?

      parts = ["#{cutoff(from)} until #{(changes.first[0] - 1).strftime('%d %b')}"]
      parts.concat(changes.map { |d, t| "#{t} from #{d.strftime('%d %b')}" }).join(", ")
    end
  end
end
