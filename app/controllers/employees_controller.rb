# frozen_string_literal: true

# Settings → Machine access: rename an employee, on the machine and in this app.
# The full name is used everywhere here (exports, payroll, portal) and is kept on later
# device syncs; the machine stores at most 24 characters, so a longer name is cut there.
class EmployeesController < ApplicationController
  NAME_MAX = 100

  # POST /settings/employees/:id/name — name=<new name>
  def rename
    emp = Employee.find(params[:id])
    name = params[:name].to_s.squish
    raise ArgumentError, "Name cannot be blank." if name.blank?
    raise ArgumentError, "Name is too long (max #{NAME_MAX} characters)." if name.length > NAME_MAX

    # Machine first: if it refuses, nothing changes here either, so the two stay in step.
    # People no longer enrolled on the machine are renamed here only.
    machine = begin
      device_name = AppSetting.current.zk_sdk_client.set_name(emp.uid, name).name
      device_name == name ? " on the machine and here" : " (shown as \"#{device_name}\" on the machine — 24 character limit)"
    rescue ZkSdkClient::Error => e
      raise unless e.message.include?("not enrolled")

      " here only (ID #{emp.uid} is not on the machine)"
    end

    old = emp.name
    emp.update!(name: name, name_locked: true)
    render json: { ok: true, message: "Renamed #{old.presence || emp.uid} to #{emp.name} (ID #{emp.uid})#{machine}.",
                   employee: { id: emp.id, name: emp.name } }
  rescue ZkSdkClient::Error => e
    render json: { ok: false, message: "Machine error, name not changed: #{e.message}" }, status: :bad_gateway
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { ok: false, message: e.message }, status: :unprocessable_entity
  end
end
