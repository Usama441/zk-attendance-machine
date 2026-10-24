class CreateHolidays < ActiveRecord::Migration[7.1]
  # Office holidays (Settings → Holidays). A weekday holiday with no punch is not absent.
  def change
    create_table :holidays do |t|
      t.string :name, null: false
      t.date   :starts_on, null: false
      t.date   :ends_on, null: false
      t.timestamps
    end
    add_index :holidays, %i[starts_on ends_on]
  end
end
