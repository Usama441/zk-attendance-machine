class AddExportVisibilityToEmployees < ActiveRecord::Migration[7.1]
  def change
    # device_admin: refreshed from the machine's user list on every sync.
    # hidden_from_export: chosen in Settings; such employees are left out of bulk exports.
    add_column :employees, :device_admin, :boolean, null: false, default: false
    add_column :employees, :hidden_from_export, :boolean, null: false, default: false
  end
end
