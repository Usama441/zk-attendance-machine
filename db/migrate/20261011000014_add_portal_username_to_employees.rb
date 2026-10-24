class AddPortalUsernameToEmployees < ActiveRecord::Migration[7.1]
  # Employee portal login name (e.g. "usama.arshad"), stored lowercase. Blank = sign in with employee ID.
  def change
    add_column :employees, :portal_username, :string
    add_index :employees, :portal_username, unique: true
  end
end
