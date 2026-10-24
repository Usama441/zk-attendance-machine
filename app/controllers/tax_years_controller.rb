# frozen_string_literal: true

# Admin: salaried income tax slabs per tax year (Payroll → Tax slabs). Pakistan's budget changes
# the slabs every June; add the new tax year here and payroll picks it up from 1 July.
class TaxYearsController < ApplicationController
  def index
    @settings  = AppSetting.current
    @tax_years = TaxYear.order(starts_on: :desc).to_a
    @tax_year  = @tax_years.find { |t| t.id.to_s == params[:year] } ||
                 @tax_years.find { |t| t.covers?(Date.today) } || @tax_years.first
    @next_start = (@tax_years.first&.starts_on&.next_year) || Date.new(Date.today.month >= 7 ? Date.today.year : Date.today.year - 1, 7, 1)
  end

  # POST /payroll/tax — a new tax year, starting from a copy of the newest slabs.
  def create
    starts_on = Date.new(params[:start_year].to_i, 7, 1)
    year = TaxYear.new(label: "#{starts_on.year}-#{(starts_on.year + 1).to_s.last(2)}", starts_on: starts_on,
                       slabs: TaxYear.order(starts_on: :desc).first&.slabs || [{ "from" => 0, "rate" => 0 }])
    if year.save
      redirect_to tax_years_path(year: year.id), notice: "Tax year #{year.label} added with a copy of the previous slabs — update them to the new budget and save."
    else
      redirect_to tax_years_path, alert: year.errors.full_messages.to_sentence
    end
  rescue Date::Error
    redirect_to tax_years_path, alert: "Invalid year."
  end

  # POST /payroll/tax/:id — save the slab rows.
  def update
    year = TaxYear.find(params[:id])
    rows = params.fetch(:slabs, {}).values.map { |r| { "from" => r[:from], "rate" => r[:rate] } }
    if year.update(slabs: rows)
      redirect_to tax_years_path(year: year.id), notice: "Saved #{year.label} slabs."
    else
      redirect_to tax_years_path(year: year.id), alert: "#{year.label}: #{year.errors.full_messages.to_sentence}"
    end
  end

  # POST /payroll/tax/toggle — switch salary tax on or off for payroll.
  def toggle
    settings = AppSetting.current
    settings.update!(salary_tax_enabled: params[:enabled] == "1")
    redirect_to tax_years_path(year: params[:year]),
                notice: "Salary income tax is now #{settings.salary_tax_enabled? ? 'on' : 'off'} in payroll."
  end
end
