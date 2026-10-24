class AddNameLockedToEmployees < ActiveRecord::Migration[7.1]
  def change
    # name_locked: set when an admin renames someone in Settings, so the next
    # device sync keeps that name instead of overwriting it with the machine's.
    add_column :employees, :name_locked, :boolean, null: false, default: false
  end
end
