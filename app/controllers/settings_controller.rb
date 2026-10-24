# frozen_string_literal: true

class SettingsController < ApplicationController
  def show
    @settings = AppSetting.current
    @employees = export_employees
  end

  def test_connection
    settings = AppSetting.current
    settings.assign_attributes(connection_params)

    unless settings.valid?
      render json: { ok: false, message: settings.errors.full_messages.to_sentence },
             status: :unprocessable_entity
      return
    end

    username, password = connection_credentials
    settings.zk_client(username: username, password: password).login

    render json: {
      ok: true,
      message: "Connected successfully to #{settings.device_name} at #{settings.device_host}:#{settings.device_port}."
    }
  rescue ZkClient::Error => e
    render json: { ok: false, message: "Connection failed: #{e.message}" }, status: :bad_gateway
  rescue ArgumentError => e
    render json: { ok: false, message: e.message }, status: :unprocessable_entity
  end

  def update
    settings = AppSetting.current
    settings.assign_attributes(settings_params)

    unless settings.valid?
      render_settings_error(settings.errors.full_messages.to_sentence, settings)
      return
    end

    if settings.connection_configuration_changed? || connection_credentials_supplied?
      username, password = connection_credentials
      settings.zk_client(username: username, password: password).login
      if session[:zk_user].present?
        session[:zk_user] = username
        session[:zk_pass] = password
      end
    end

    AppSetting.transaction do
      settings.save!
      save_hidden_employees
    end
    respond_to do |format|
      format.html { redirect_to settings_path, notice: "Settings saved." }
      format.json do
        render json: {
          ok: true,
          message: "Settings saved.",
          settings: settings_payload(settings)
        }
      end
    end
  rescue ZkClient::Error => e
    render_settings_error("Connection was not saved: #{e.message}", settings, :bad_gateway)
  rescue ArgumentError => e
    render_settings_error(e.message, settings)
  end

  private

  def settings_params
    params.require(:app_setting).permit(
      :auto_sync_enabled,
      :sync_interval_minutes,
      :sync_lookback_days,
      :device_name,
      :device_host,
      :device_port,
      :device_open_timeout,
      :device_read_timeout,
      :device_sdk_port,
      :device_comm_key
    )
  end

  # Admins first, then everyone else, each alphabetical.
  def export_employees
    Employee.order(device_admin: :desc).order(Arel.sql("LOWER(name)"), :uid)
  end

  # The form always sends hidden_employee_ids[] (with a blank sentinel), so an
  # absent param means "not part of this form" and nothing is changed.
  def save_hidden_employees
    return unless params.key?(:hidden_employee_ids)

    ids = Array(params[:hidden_employee_ids]).reject(&:blank?).map(&:to_i)
    Employee.where(id: ids).update_all(hidden_from_export: true)
    Employee.where.not(id: ids).update_all(hidden_from_export: false)
  end

  def connection_params
    params.require(:app_setting).permit(
      :device_name,
      :device_host,
      :device_port,
      :device_open_timeout,
      :device_read_timeout
    )
  end

  def connection_credentials
    username = params[:connection_login_id].to_s.strip.presence || device_login_id
    password = params[:connection_password].to_s.presence || device_password
    raise ArgumentError, "Device admin Login ID and password are required." if username.blank? || password.nil?

    [username, password]
  end

  def connection_credentials_supplied?
    params[:connection_password].present? ||
      params[:connection_login_id].to_s.strip != device_login_id.to_s
  end

  def render_settings_error(message, settings, status = :unprocessable_entity)
    respond_to do |format|
      format.html do
        @settings = settings
        @employees = export_employees
        flash.now[:alert] = message
        render :show, status: status
      end
      format.json { render json: { ok: false, message: message }, status: status }
    end
  end

  def settings_payload(settings)
    {
      auto_sync_enabled: settings.auto_sync_enabled?,
      sync_interval_minutes: settings.sync_interval_minutes,
      sync_lookback_days: settings.sync_lookback_days,
      device_name: settings.device_name,
      device_host: settings.device_host,
      device_port: settings.device_port
    }
  end
end
