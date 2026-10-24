class AddDeviceAccessToEmployees < ActiveRecord::Migration[7.1]
  def change
    # device_enabled mirrors the machine's per-user Enable/Disable flag (SDK, port 4370).
    add_column :employees, :device_enabled, :boolean, null: false, default: true
    add_column :employees, :device_status_changed_at, :datetime
    add_column :employees, :device_status_changed_by, :string

    add_column :app_settings, :device_sdk_port, :integer, null: false, default: 4370
    add_column :app_settings, :device_comm_key, :integer, null: false, default: 0
  end
end
