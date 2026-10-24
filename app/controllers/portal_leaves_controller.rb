# frozen_string_literal: true

# Employee side of leave requests: apply, see status, cancel while still pending.
class PortalLeavesController < PortalController
  def index
    @leaves = current_employee.leave_requests.order(start_date: :desc, created_at: :desc)
    @leave  = current_employee.leave_requests.new(start_date: Date.tomorrow, end_date: Date.tomorrow)
  end

  def create
    @leave = current_employee.leave_requests.new(leave_params.merge(status: "pending"))
    if @leave.save
      redirect_to portal_leaves_path, notice: "Leave request sent for #{@leave.days} day(s). An admin will review it."
    else
      @leaves = current_employee.leave_requests.order(start_date: :desc, created_at: :desc)
      flash.now[:alert] = @leave.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def cancel
    current_employee.leave_requests.find(params[:id]).cancel!
    redirect_to portal_leaves_path, notice: "Leave request cancelled."
  rescue ArgumentError => e
    redirect_to portal_leaves_path, alert: e.message
  end

  private

  def leave_params
    params.require(:leave_request).permit(:leave_type, :start_date, :end_date, :reason)
  end
end
