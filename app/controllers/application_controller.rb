# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Internal LAN tool behind a device-backed sign-in.
  skip_forgery_protection

  before_action :require_login

  private

  # The full app is for admins: an employee account with the admin role, or the attendance
  # machine's own admin login (fallback). Employees only get the portal.
  def require_login
    redirect_to login_path, alert: "Please sign in." unless logged_in?
  end

  def logged_in?
    current_admin_employee.present? || session[:zk_user].present?
  end
  helper_method :logged_in?

  # The signed-in admin's employee record (nil when signed in with the machine login).
  def current_admin_employee
    return @current_admin_employee if defined?(@current_admin_employee)

    @current_admin_employee = session[:admin_id] && Employee.find_by(id: session[:admin_id])
    # Admin role or portal access removed since sign-in: drop the stale session.
    @current_admin_employee = nil unless @current_admin_employee&.admin? && @current_admin_employee.portal_enabled?
    @current_admin_employee
  end

  helper_method :current_admin_employee

  # Who is signed in, for "by …" audit fields and the top bar.
  def current_admin
    current_admin_employee&.then { |e| e.portal_username || e.name } || session[:zk_user]
  end
  helper_method :current_admin

  # Machine login used for device calls: the one signed in with, else the configured one.
  def device_login_id = session[:zk_user].presence || ENV.fetch("ZK_USER", "999")
  def device_password = session[:zk_user].present? ? session[:zk_pass] : ENV.fetch("ZK_PASS", "999")
  helper_method :device_login_id

  # Employee self-service portal (separate from the device-admin sign-in).
  def current_employee
    return @current_employee if defined?(@current_employee)

    @current_employee = session[:employee_id] && Employee.find_by(id: session[:employee_id])
    # Access removed (or made admin) since sign-in: drop the stale session.
    @current_employee = nil unless @current_employee&.portal_enabled? && @current_employee.employee?
    @current_employee
  end
  helper_method :current_employee

  def employee_logged_in?
    current_employee.present?
  end
  helper_method :employee_logged_in?

  # Whether a portal page (a key of AppSetting::PORTAL_PAGES) is shown to employees.
  def portal_page?(page)
    @portal_settings ||= AppSetting.current
    @portal_settings.portal_page_visible?(page)
  end
  helper_method :portal_page?

  def pending_leave_count
    @pending_leave_count ||= LeaveRequest.pending.count
  end
  helper_method :pending_leave_count

  def pending_parking_count
    @pending_parking_count ||= ParkingRequest.pending.count
  end
  helper_method :pending_parking_count

  # ?month=YYYY-MM -> first day of that month (defaults to the current month).
  def selected_month
    Date.strptime(params[:month].to_s, "%Y-%m")
  rescue Date::Error
    Date.today.beginning_of_month
  end

  # A device client using the saved connection and machine admin credentials.
  def zk_client
    AppSetting.current.zk_client(username: device_login_id, password: device_password)
  end
end
