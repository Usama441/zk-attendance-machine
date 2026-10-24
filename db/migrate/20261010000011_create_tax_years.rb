class CreateTaxYears < ActiveRecord::Migration[7.1]
  # Pakistan salaried income tax (Income Tax Ordinance 2001, First Schedule, Part I, Div I, clause 1A).
  # Each tax year runs 1 July – 30 June. Slabs are [{ "from" => income, "rate" => percent }, ...]:
  # income above "from" (up to the next slab) is taxed at "rate"; fixed amounts are derived.
  FINANCE_ACT_2026 = [
    { "from" => 0,         "rate" => 0 },
    { "from" => 600_000,   "rate" => 1 },
    { "from" => 1_200_000, "rate" => 11 },
    { "from" => 2_200_000, "rate" => 20 },
    { "from" => 3_200_000, "rate" => 25 },
    { "from" => 4_100_000, "rate" => 29 },
    { "from" => 5_600_000, "rate" => 32 },
    { "from" => 7_000_000, "rate" => 35 }
  ].freeze

  def up
    create_table :tax_years do |t|
      t.string :label, null: false
      t.date   :starts_on, null: false
      t.jsonb  :slabs, null: false, default: []
      t.timestamps
    end
    add_index :tax_years, :starts_on, unique: true

    add_column :app_settings, :salary_tax_enabled, :boolean, null: false, default: true

    now = Time.current
    execute <<~SQL
      INSERT INTO tax_years (label, starts_on, slabs, created_at, updated_at)
      VALUES ('2026-27', '2026-07-01', #{connection.quote(FINANCE_ACT_2026.to_json)}::jsonb,
              #{connection.quote(now)}, #{connection.quote(now)})
    SQL
  end

  def down
    remove_column :app_settings, :salary_tax_enabled
    drop_table :tax_years
  end
end
