class CreateEmployeeComments < ActiveRecord::Migration[7.1]
  # A note about an employee for a date range; shown in the export's Comments column and
  # deleted automatically once its end date has passed.
  def change
    create_table :employee_comments do |t|
      t.references :employee, null: false, foreign_key: true
      t.text   :body, null: false
      t.date   :starts_on, null: false
      t.date   :ends_on, null: false
      t.string :created_by
      t.timestamps
    end
    add_index :employee_comments, :ends_on
  end
end
