class AddPayrollAndPortalToEmployees < ActiveRecord::Migration[7.1]
  def change
    # monthly_salary: set by an admin on the Payroll page; deductions are computed from it.
    # password_digest: employee self-service portal password (set by an admin; blank = no portal access).
    add_column :employees, :monthly_salary, :decimal, precision: 12, scale: 2, null: false, default: 0
    add_column :employees, :password_digest, :string
  end
end
