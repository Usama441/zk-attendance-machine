# frozen_string_literal: true

# Serves the user photos pulled from the machine. Admins see everyone's; a portal
# employee only their own.
class EmployeePhotosController < ApplicationController
  skip_before_action :require_login

  # GET /employees/:id/photo
  def show
    head :forbidden and return unless logged_in? || current_employee&.id == params[:id].to_i

    photo = EmployeePhoto.find_by!(employee_id: params[:id])
    expires_in 1.day, public: false # the URL carries ?v=<fetched_at>, so a new photo gets a new URL
    send_data photo.data, type: "image/jpeg", disposition: "inline"
  end
end
