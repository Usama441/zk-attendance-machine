class CreateAppSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :app_settings do |t|
      t.string :key, null: false
      t.boolean :auto_sync_enabled, null: false, default: false
      t.integer :sync_interval_minutes, null: false, default: 15
      t.integer :sync_lookback_days, null: false, default: 31
      t.datetime :last_sync_at
      t.string :last_sync_status
      t.string :last_sync_message
      t.timestamps
    end

    add_index :app_settings, :key, unique: true
  end
end
