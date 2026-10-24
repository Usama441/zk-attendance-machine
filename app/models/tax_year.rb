# frozen_string_literal: true

# Salaried income tax slabs for one Pakistani tax year (1 July – 30 June).
# Slabs: [{ "from" => 0, "rate" => 0 }, { "from" => 600_000, "rate" => 1 }, ...] — the part of
# annual taxable income above "from" (up to the next slab's "from") is taxed at "rate" percent.
class TaxYear < ApplicationRecord
  validates :label, presence: true, length: { maximum: 20 }
  validates :starts_on, presence: true, uniqueness: true
  validate :slabs_are_valid

  before_validation :normalize_slabs

  # Slabs that apply to a month, or nil when salary tax is switched off / nothing is set up.
  # A month after the newest tax year still uses it (see #covers?) until a new year is added.
  def self.applicable(date)
    return nil unless AppSetting.current.salary_tax_enabled?

    where(starts_on: ..date.to_date).order(starts_on: :desc).first
  end

  def ends_on = starts_on.next_year - 1
  def covers?(date) = (starts_on..ends_on).cover?(date.to_date)

  # Slabs with their range end and the fixed tax due at the start of each slab.
  def schedule
    fixed = 0.to_d
    slabs.each_with_index.map do |s, i|
      upto = slabs[i + 1]&.fetch("from")
      row = { from: s["from"].to_d, upto: upto&.to_d, rate: s["rate"].to_d, fixed: fixed }
      fixed += (upto.to_d - s["from"].to_d) * s["rate"].to_d / 100 if upto
      row
    end
  end

  def annual_tax(income)
    income = income.to_d
    schedule.sum do |s|
      next 0 if income <= s[:from]

      ([income, s[:upto]].compact.min - s[:from]) * s[:rate] / 100
    end.round(2)
  end

  # Monthly withholding: tax on the month's taxable salary annualised (× 12), spread over 12 months.
  def monthly_tax(monthly_income)
    return 0.to_d unless monthly_income.to_d.positive?

    (annual_tax(monthly_income.to_d * 12) / 12).round(2)
  end

  private

  def normalize_slabs
    self.slabs = Array(slabs).map { |s| s.to_h.stringify_keys }
                             .reject { |s| s["from"].to_s.strip.empty? && s["rate"].to_s.strip.empty? }
                             .map { |s| { "from" => s["from"].to_s.delete(",").to_d.to_i, "rate" => s["rate"].to_s.to_d.to_f } }
                             .sort_by { |s| s["from"] }
  end

  def slabs_are_valid
    errors.add(:slabs, "need at least one row") and return if slabs.empty?
    errors.add(:slabs, "must start at 0 income") unless slabs.first["from"].zero?
    errors.add(:slabs, "cannot repeat the same starting income") if slabs.map { |s| s["from"] }.uniq.size != slabs.size
    errors.add(:slabs, "rates must be between 0 and 100%") unless slabs.all? { |s| s["rate"].between?(0, 100) }
    errors.add(:slabs, "starting incomes cannot be negative") if slabs.any? { |s| s["from"].negative? }
  end
end
