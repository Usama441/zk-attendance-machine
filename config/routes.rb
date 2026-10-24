Rails.application.routes.draw do
  root "exports#index"

  get    "login",  to: "sessions#new"
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  post "sync",   to: "exports#sync",   as: :sync
  post "export", to: "exports#export", as: :export

  resource :settings, only: %i[show update]
  post "settings/test_connection", to: "settings#test_connection", as: :test_connection_settings
  post "settings/device_access",         to: "device_access#create",  as: :add_device_user
  post "settings/device_access/refresh", to: "device_access#refresh", as: :refresh_device_access
  post "settings/device_access/:id",     to: "device_access#update",  as: :device_access
  get  "employees/:id/photo",           to: "employee_photos#show",  as: :employee_photo
  post "settings/employees/:id/name",    to: "employees#rename",      as: :rename_employee
  get  "settings/late",            to: "late_rules#index",   as: :late_rules
  get  "settings/holidays",            to: "holidays#index",   as: :holidays
  post "settings/holidays",            to: "holidays#create"
  post "settings/holidays/:id",        to: "holidays#update",  as: :holiday
  post "settings/holidays/:id/delete", to: "holidays#destroy", as: :delete_holiday
  post "settings/saturdays/toggle",    to: "holidays#toggle_saturday", as: :toggle_saturday
  post "settings/saturdays/rule",      to: "holidays#saturday_rule",   as: :saturday_rule
  post "settings/late",            to: "late_rules#create"
  post "settings/late/:id",        to: "late_rules#update",  as: :late_rule
  post "settings/late/:id/delete", to: "late_rules#destroy", as: :delete_late_rule

  get  "corrections",      to: "corrections#index",  as: :corrections
  post "corrections",         to: "corrections#create"
  post "corrections/replace", to: "corrections#replace", as: :replace_correction
  post "corrections/void",    to: "corrections#void",    as: :void_correction
  post "corrections/bulk",    to: "corrections#bulk_create", as: :bulk_correction

  # Admin: per-employee comments shown in the export (auto-deleted after their end date)
  get  "comments",            to: "employee_comments#index",   as: :employee_comments
  post "comments",            to: "employee_comments#create"
  post "comments/:id",        to: "employee_comments#update",  as: :employee_comment
  post "comments/:id/delete", to: "employee_comments#destroy", as: :delete_employee_comment

  # Admin: monthly parking sticker requests, prices and vehicle-list export
  get  "parking",            to: "parking_requests#index",  as: :parking_requests
  get  "parking/export",     to: "parking_requests#export", as: :parking_export
  post "parking/prices",     to: "parking_requests#prices", as: :parking_prices
  post "parking/:id/review", to: "parking_requests#review", as: :review_parking_request

  # Admin: leave requests and monthly payroll deductions
  get  "leaves",            to: "leave_requests#index",  as: :leave_requests
  post "leaves",            to: "leave_requests#create"
  post "leaves/:id/review", to: "leave_requests#review", as: :review_leave_request
  get  "payroll",     to: "payroll#index",  as: :payroll
  get  "payroll/tax",       to: "tax_years#index",  as: :tax_years
  post "payroll/tax",       to: "tax_years#create"
  post "payroll/tax/toggle", to: "tax_years#toggle", as: :toggle_tax
  post "payroll/tax/:id",   to: "tax_years#update", as: :tax_year
  get  "payroll/:id", to: "payroll#show",   as: :payroll_employee
  post "payroll/:id", to: "payroll#update", as: :update_payroll_employee

  # Employee self-service portal
  delete "portal/logout",   to: "portal_sessions#destroy", as: :portal_logout
  get    "portal",            to: "portal#show",       as: :portal
  get    "portal/attendance", to: "portal#attendance", as: :portal_attendance
  get    "portal/salary",     to: "portal#salary",     as: :portal_salary
  get    "portal/account",    to: "portal#account",    as: :portal_account
  post   "portal/password", to: "portal#password",         as: :portal_password
  get    "portal/leaves",   to: "portal_leaves#index",     as: :portal_leaves
  get    "portal/parking",            to: "portal_parking#index",  as: :portal_parking
  post   "portal/parking",            to: "portal_parking#create"
  post   "portal/parking/:id/cancel", to: "portal_parking#cancel", as: :cancel_portal_parking
  post   "portal/leaves",   to: "portal_leaves#create"
  post   "portal/leaves/:id/cancel", to: "portal_leaves#cancel", as: :cancel_portal_leave
end
