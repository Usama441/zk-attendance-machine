# frozen_string_literal: true

# Employee side of parking stickers: request this month's sticker (bike or car + vehicle number),
# see its status, cancel while still pending. A sticker expires at month end, so the employee
# requests again each month. Prices come from Settings (admin → Parking).
class PortalParkingController < PortalController
  def index
    load_page
    last = current_employee.parking_requests.order(created_at: :desc).first
    @request = current_employee.parking_requests.new(
      vehicle_type: last&.vehicle_type || "bike",
      vehicle_number: last&.vehicle_number
    )
  end

  def create
    @request = current_employee.parking_requests.new(request_params.merge(month: Date.today, status: "pending"))
    if @request.save
      redirect_to portal_parking_path,
                  notice: "Parking sticker requested for #{@request.vehicle_number} (#{@request.month.strftime('%B %Y')}). An admin will review it."
    else
      load_page
      flash.now[:alert] = @request.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def cancel
    current_employee.parking_requests.find(params[:id]).cancel!
    redirect_to portal_parking_path, notice: "Parking request cancelled."
  rescue ArgumentError => e
    redirect_to portal_parking_path, alert: e.message
  end

  private

  def portal_page = "parking"

  def load_page
    @settings = AppSetting.current
    @month    = Date.today.beginning_of_month
    @requests = current_employee.parking_requests.order(month: :desc, created_at: :desc).to_a
    @current  = @requests.select { |q| q.month == @month && (q.approved? || q.pending?) }
  end

  def request_params
    params.require(:parking_request).permit(:vehicle_type, :vehicle_number)
  end
end
