# frozen_string_literal: true

# Admin side of parking stickers: review a month's requests, set the bike / car sticker prices,
# and export the month's vehicle list to Excel.
class ParkingRequestsController < ApplicationController
  # GET /parking?month=YYYY-MM
  def index
    @month    = selected_month
    @settings = AppSetting.current
    @requests = ParkingRequest.for_month(@month).includes(:employee).order(:status, :created_at).to_a
  end

  # POST /parking/:id/review  decision=approved|rejected
  def review
    req = ParkingRequest.find(params[:id])
    req.review!(params[:decision].to_s, by: current_admin, note: params[:admin_note])
    redirect_to parking_requests_path(month: req.month.strftime("%Y-%m")),
                notice: "#{req.employee.name}'s sticker (#{req.vehicle_number}) #{req.status}."
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to parking_requests_path(month: params[:month]), alert: "Could not update: #{e.message}"
  end

  # POST /parking/prices — sticker prices for new requests (existing requests keep their price).
  def prices
    settings = AppSetting.current
    if settings.update(parking_bike_price: params[:bike_price], parking_car_price: params[:car_price])
      redirect_to parking_requests_path(month: params[:month]), notice: "Sticker prices saved: bike #{helpers.money(settings.parking_bike_price)}, car #{helpers.money(settings.parking_car_price)}."
    else
      redirect_to parking_requests_path(month: params[:month]), alert: settings.errors.full_messages.to_sentence
    end
  end

  # GET /parking/export?month=YYYY-MM — the month's vehicles (cancelled requests left out).
  def export
    month = selected_month
    requests = ParkingRequest.for_month(month).where.not(status: "cancelled").includes(:employee)
                             .order(:vehicle_type, :vehicle_number).to_a
    send_data ParkingWorkbook.new(requests, month: month).to_stream,
              filename: "parking-stickers-#{month.strftime('%Y-%m')}.xlsx",
              type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              disposition: "attachment"
  end
end
