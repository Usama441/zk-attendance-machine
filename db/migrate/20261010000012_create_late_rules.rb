class CreateLateRules < ActiveRecord::Migration[7.1]
  # Late cut-off time, effective from a date: a first punch at or after late_at counts as late.
  # Office rule: 09:15 up to 5 Oct 2026, 08:50 from 6 Oct 2026.
  def up
    create_table :late_rules do |t|
      t.date   :effective_from, null: false
      t.string :late_at, null: false, limit: 5
      t.timestamps
    end
    add_index :late_rules, :effective_from, unique: true

    now = connection.quote(Time.current)
    execute <<~SQL
      INSERT INTO late_rules (effective_from, late_at, created_at, updated_at) VALUES
        ('2026-01-01', '09:15', #{now}, #{now}),
        ('2026-10-06', '08:50', #{now}, #{now})
    SQL
  end

  def down
    drop_table :late_rules
  end
end
