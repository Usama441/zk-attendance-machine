class CreateLeaveRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :leave_requests do |t|
      t.references :employee, null: false, foreign_key: true
      t.string   :leave_type, null: false
      t.date     :start_date, null: false
      t.date     :end_date,   null: false
      t.text     :reason,     null: false
      # pending -> approved | rejected (admin), or cancelled (employee, while pending)
      t.string   :status,     null: false, default: "pending"
      t.string   :reviewed_by
      t.datetime :reviewed_at
      t.string   :admin_note
      t.timestamps
    end
    add_index :leave_requests, [:employee_id, :start_date]
    add_index :leave_requests, :status
  end
end
