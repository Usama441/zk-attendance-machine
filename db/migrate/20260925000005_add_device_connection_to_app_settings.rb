class AddDeviceConnectionToAppSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :app_settings, :device_name, :string, null: false, default: "Main Attendance Machine"
    add_column :app_settings, :device_host, :string, null: false, default: "192.168.10.15"
    add_column :app_settings, :device_port, :integer, null: false, default: 80
    add_column :app_settings, :device_open_timeout, :integer, null: false, default: 5
    add_column :app_settings, :device_read_timeout, :integer, null: false, default: 30
  end
end
