class AddHiddenPortalPagesToAppSettings < ActiveRecord::Migration[7.1]
  # Employee portal pages the admin has switched off (keys of AppSetting::PORTAL_PAGES).
  def change
    add_column :app_settings, :hidden_portal_pages, :string, array: true, null: false, default: []
  end
end
