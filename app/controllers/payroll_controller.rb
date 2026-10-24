# frozen_string_literal: true

# Admin: monthly salary deductions for every employee, plus each employee's
# salary and self-service portal password.
class PayrollController < ApplicationController
  def index
    @month = selected_month
    @show_hidden = params[:hidden] == "1"
    employees = @show_hidden ? Employee.all : Employee.exportable
    @tax_year = TaxYear.applicable(@month)
    late_rules = LateRule.schedule
    parking = ParkingRequest.approved.for_month(@month).group(:employee_id).sum(:price)
    @reports = employees.order(Arel.sql("LOWER(name)"), :uid)
                        .map { |e| MonthlyAttendance.new(e, @month, tax_year: @tax_year, late_rules: late_rules,
                                                         parking_fee: parking.fetch(e.id, 0)) }
  end

  # GET /payroll/:id?month=YYYY-MM — one employee's day-by-day breakdown.
  def show
    @employee = Employee.find(params[:id])
    @report = MonthlyAttendance.new(@employee, selected_month)
  end

  # POST /payroll/:id — salary, portal password, or remove portal access.
  def update
    emp = Employee.find(params[:id])
    emp.monthly_salary = params[:monthly_salary] if params.key?(:monthly_salary)
    emp.portal_username = params[:portal_username] if params.key?(:portal_username)
    emp.role = params[:role] if Employee.roles.key?(params[:role]) && emp != current_admin_employee
    if params[:remove_portal] == "1"
      return redirect_to(back_path, alert: "You can't remove your own access.") if emp == current_admin_employee

      emp.password_digest = nil
      emp.portal_username = nil
      emp.role = :employee
    elsif params[:portal_password].present?
      emp.password = params[:portal_password]
    end

    if emp.save
      redirect_to back_path, notice: "Saved #{emp.name}."
    else
      redirect_to back_path, alert: "#{emp.name}: #{emp.errors.full_messages.to_sentence}"
    end
  end

  private

  def back_path
    params[:return_to] == "show" ? payroll_employee_path(params[:id], month: params[:month]) :
      payroll_path(month: params[:month], hidden: params[:hidden])
  end
end
