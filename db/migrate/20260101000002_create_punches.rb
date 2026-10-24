class CreatePunches < ActiveRecord::Migration[7.1]
  def change
    create_table :punches do |t|
      t.references :employee, null: false, foreign_key: true
      t.datetime :punched_at, null: false
      t.string   :s1
      t.string   :s2
      t.timestamps
    end
    # Dedupe: one row per employee per exact timestamp (used by insert_all upsert).
    add_index :punches, [:employee_id, :punched_at], unique: true
  end
end
