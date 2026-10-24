class CreateWorkingSaturdays < ActiveRecord::Migration[7.1]
  # Saturday rule: 1st and 3rd Saturdays of a month are off, 2nd / 4th / 5th are working days.
  # working_saturdays lists 1st/3rd Saturdays an admin has turned into working days.
  # saturday_rule_from: the rule applies from this date; before it every Saturday is off.
  def change
    create_table :working_saturdays do |t|
      t.date :date, null: false
      t.timestamps
    end
    add_index :working_saturdays, :date, unique: true

    add_column :app_settings, :saturday_rule_from, :date
  end
end
