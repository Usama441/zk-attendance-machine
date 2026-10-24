# frozen_string_literal: true

# Settings → Machine access: add users to, and activate / deactivate employees on, the ZK machine itself.
# A deactivated user stays enrolled (fingerprints, card and history are kept) but the
# machine refuses their finger/card/password, so they can no longer punch or open the door.
# This is the only part of the app that writes to the device.
class DeviceAccessController < ApplicationController
  # POST /settings/device_access/refresh — re-read every user's status and photo from the machine.
  def refresh
    client = AppSetting.current.zk_sdk_client
    users = client.users
    changed = Employee.refresh_device_status!(users)
    known = Employee.pluck(:uid).to_set
    missing = users.count { |u| !known.include?(u.user_id.to_i) }

    message = "Read #{users.size} users from the machine; #{changed} status change(s)."
    message += " #{missing} user(s) on the machine have no punches here yet and are not listed." if missing.positive?
    # Photos are best-effort: a failure here must not hide the status refresh above.
    begin
      photos = EmployeePhoto.sync!(client.user_photos)
      message += " #{photos} user photo(s) pulled — reload the page to see them."
    rescue ZkSdkClient::Error => e
      message += " Photos skipped: #{e.message}."
    end
    render json: { ok: true, message: message, employees: payload(Employee.all) }
  rescue ZkSdkClient::Error => e
    render json: { ok: false, message: "Machine error: #{e.message}" }, status: :bad_gateway
  end

  # POST /settings/device_access/:id — enabled=1 activates, enabled=0 deactivates.
  def update
    emp = Employee.find(params[:id])
    enable = params[:enabled] == "1"
    guard_deactivation!(emp) unless enable

    AppSetting.current.zk_sdk_client.set_enabled(emp.uid, enable)
    emp.device_enabled = enable
    emp.device_status_changed_at = Time.current
    emp.device_status_changed_by = current_admin
    emp.save!

    verb = enable ? "activated" : "deactivated"
    render json: { ok: true, message: "#{emp.name} (ID #{emp.uid}) #{verb} on the machine.",
                   employee: payload([emp]).first }
  rescue ZkSdkClient::Error => e
    render json: { ok: false, message: "Machine error: #{e.message}" }, status: :bad_gateway
  rescue ArgumentError => e
    render json: { ok: false, message: e.message }, status: :unprocessable_entity
  end

  # POST /settings/device_access — enroll a new user on the machine (user_id, name,
  # optional password / card). Fingerprints are then added at the machine itself.
  def create
    user_id = params[:user_id].to_s.strip
    name = params[:name].to_s.squish
    password = params[:password].to_s.strip
    card = params[:card].to_s.strip
    raise ArgumentError, "Employee ID must be a number (up to 9 digits)." unless user_id.match?(/\A[1-9]\d{0,8}\z/)
    raise ArgumentError, "Name cannot be blank." if name.blank?
    raise ArgumentError, "Name is too long for the machine (max 24 characters)." if name.bytesize > 24
    raise ArgumentError, "Password must be 1–8 digits." unless password.empty? || password.match?(/\A\d{1,8}\z/)
    raise ArgumentError, "Card number must be digits only." unless card.empty? || (card.match?(/\A\d{1,10}\z/) && card.to_i < 2**32)

    AppSetting.current.zk_sdk_client.add_user(user_id: user_id, name: name, password: password, card: card)

    emp = Employee.find_or_initialize_by(uid: user_id.to_i)
    emp.name = name
    emp.device_enabled = true
    emp.device_status_changed_at = Time.current
    emp.device_status_changed_by = current_admin
    emp.save!

    render json: { ok: true, message: "#{emp.name} (ID #{emp.uid}) added to the machine. Enroll their fingerprint at the machine: Menu → User Mng → find ID #{emp.uid} → Edit." }
  rescue ZkSdkClient::Error => e
    render json: { ok: false, message: "Machine error: #{e.message}" }, status: :bad_gateway
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { ok: false, message: e.message }, status: :unprocessable_entity
  end

  private

  def guard_deactivation!(emp)
    raise ArgumentError, "You cannot deactivate the account you are signed in with." if emp == current_admin_employee || emp.uid.to_s == session[:zk_user].to_s
    if emp.device_admin? && Employee.where(device_admin: true, device_enabled: true).where.not(id: emp.id).none?
      raise ArgumentError, "#{emp.name} is the last active admin on the machine."
    end
  end

  def payload(employees)
    employees.map do |e|
      { id: e.id, enabled: e.device_enabled?,
        changed: e.device_status_changed_at && [
          e.device_status_changed_at.getlocal(ENV.fetch("TZ_OFFSET", "+05:00")).strftime("%d %b %Y %H:%M"),
          e.device_status_changed_by
        ].compact.join(" by ") }
    end
  end
end
