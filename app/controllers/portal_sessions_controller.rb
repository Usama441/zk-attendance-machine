# frozen_string_literal: true

# Employees sign in on the shared page (SessionsController); this only signs them out.
class PortalSessionsController < ApplicationController
  skip_before_action :require_login

  # DELETE /portal/logout
  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out."
  end
end
