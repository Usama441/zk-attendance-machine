class AddRoleToEmployees < ActiveRecord::Migration[7.1]
  # App role for sign-in: 0 = employee (portal), 1 = admin (full app). See Employee.roles.
  def change
    add_column :employees, :role, :integer, null: false, default: 0
    add_index :employees, :role
  end
end
