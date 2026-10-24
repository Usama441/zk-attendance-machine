# frozen_string_literal: true

# One sign-in page for everyone. The app decides where you land from your account's role:
# admin → the full app, employee → the self-service portal. As a fallback, the attendance
# machine's own admin login (e.g. 999) still opens the full app, so admins can't be locked out.
class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]

  # GET /login
  def new
    redirect_to root_path and return if logged_in?
    redirect_to portal_path and return if employee_logged_in?
  end

  # POST /login
  def create
    login = params[:login_id].to_s.strip
    pw    = params[:password].to_s

    emp = Employee.find_for_portal(login)
    emp = nil unless emp&.portal_enabled?
    if emp
      raise ArgumentError, "wrong password" unless emp.authenticate(pw)

      reset_session
      if emp.admin?
        session[:admin_id] = emp.id
        redirect_to root_path, notice: "Signed in as #{emp.name}."
      else
        session[:employee_id] = emp.id
        redirect_to portal_path, notice: "Welcome, #{emp.name}."
      end
    else
      AppSetting.current.zk_client(username: login, password: pw).login
      reset_session
      session[:zk_user] = login
      session[:zk_pass] = pw
      redirect_to root_path, notice: "Signed in as #{login} (machine admin)."
    end
  rescue ZkClient::Error, ArgumentError
    flash.now[:alert] = "Login failed — wrong username or password."
    render :new, status: :unauthorized
  end

  # DELETE /logout
  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out."
  end
end
