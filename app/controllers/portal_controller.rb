# frozen_string_literal: true

# Employee self-service portal, one job per page: Home (today + this month at a glance),
# Attendance (month calendar), Salary (payslip), Account (profile + password). Leaves live in
# PortalLeavesController. Employees sign in on the shared login page.
class PortalController < ApplicationController
  skip_before_action :require_login
  before_action :require_employee

  # GET /portal
  def show
    today   = Date.today
    @report = MonthlyAttendance.new(current_employee, today)
    # Last 7 days, reaching into last month early in the month.
    days = @report.days
    days = MonthlyAttendance.new(current_employee, today.prev_month).days + days if today.day < 7
    @week = days.select { |d| d.date.between?(today - 6, today) }
    @leaves = current_employee.leave_requests.order(created_at: :desc).limit(3)
    @pending_leaves = current_employee.leave_requests.pending.count
  end

  # GET /portal/attendance?month=YYYY-MM
  def attendance
    @report = MonthlyAttendance.new(current_employee, selected_month)
  end

  # GET /portal/salary?month=YYYY-MM&amount=60000&kind=salary|stipend — salary calculator: the
  # employee enters their salary or stipend and it's worked out against this month's attendance.
  def salary
    @kind   = params[:kind] == "stipend" ? "stipend" : "salary"
    entered = params[:amount].to_s.delete(",").strip
    @amount = entered.match?(/\A\d+(\.\d+)?\z/) ? entered.to_d : current_employee.monthly_salary.to_d
    @amount = nil unless @amount.positive?
    @report = MonthlyAttendance.new(current_employee, selected_month, salary: @amount || 0,
                                    apply_tax: @kind == "salary")
  end

  # GET /portal/account
  def account; end

  # POST /portal/password — the employee changes their own portal password.
  def password
    emp = current_employee
    unless emp.authenticate(params[:current_password].to_s)
      redirect_to portal_account_path, alert: "Current password is incorrect." and return
    end
    if params[:new_password].to_s != params[:new_password_confirmation].to_s
      redirect_to portal_account_path, alert: "New passwords do not match." and return
    end

    emp.password = params[:new_password].to_s
    if emp.save
      redirect_to portal_account_path, notice: "Password changed."
    else
      redirect_to portal_account_path, alert: emp.errors.full_messages.to_sentence
    end
  end

  private

  def require_employee
    redirect_to login_path, alert: "Please sign in." unless employee_logged_in?
  end
end
