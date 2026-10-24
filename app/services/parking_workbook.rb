# frozen_string_literal: true
require "caxlsx"

# One-sheet Excel list of a month's parking sticker requests: employee, vehicle type and number,
# price and status, with approved totals at the bottom.
class ParkingWorkbook
  HEADERS = ["Sr. No.", "Employee Name", "Employee ID", "Vehicle", "Vehicle Number", "Price (Rs)",
             "Status", "Requested On", "Reviewed By"].freeze

  def initialize(requests, month:)
    @requests = requests
    @month    = month
  end

  def to_stream
    pkg = Axlsx::Package.new
    wb  = pkg.workbook
    grid = { style: :thin, color: "A6A6A6" }
    hdr   = wb.styles.add_style(bg_color: "1F4E78", fg_color: "FFFFFF", b: true, sz: 10, border: { style: :thin, color: "FFFFFF" },
                                alignment: { horizontal: :center, vertical: :center })
    title = wb.styles.add_style(b: true, sz: 13)
    cell  = wb.styles.add_style(border: grid, sz: 10)
    plate = wb.styles.add_style(border: grid, sz: 10, b: true, bg_color: "FFF8D6")
    money = wb.styles.add_style(border: grid, sz: 10, num_fmt: 3)
    total = wb.styles.add_style(b: true, sz: 10, num_fmt: 3)
    label = wb.styles.add_style(b: true, sz: 10)

    wb.add_worksheet(name: "Parking #{@month.strftime('%b %Y')}") do |sh|
      sh.add_row ["Parking stickers — #{@month.strftime('%B %Y')}"], style: title
      sh.add_row []
      sh.add_row HEADERS, style: hdr, height: 18
      @requests.each_with_index do |q, i|
        sh.add_row [i + 1, q.employee.name, q.employee.uid, q.vehicle_label, q.vehicle_number, q.price.to_f,
                    q.status.capitalize, q.created_at.strftime("%d %b %Y"), q.reviewed_by.to_s],
                   style: [cell, cell, cell, cell, plate, money, cell, cell, cell],
                   types: [:integer, :string, :string, :string, :string, :float, :string, :string, :string]
      end

      approved = @requests.select(&:approved?)
      sh.add_row []
      ParkingRequest::VEHICLES.each do |key, name|
        list = approved.select { |q| q.vehicle_type == key }
        sh.add_row ["", "Approved #{name.downcase}s", list.size, "", "", list.sum(&:price).to_f], style: [nil, label, label, nil, nil, total]
      end
      sh.add_row ["", "Approved total", approved.size, "", "", approved.sum(&:price).to_f], style: [nil, label, label, nil, nil, total]
      sh.column_widths 8, 26, 12, 10, 18, 12, 12, 15, 16
    end

    pkg.to_stream.read
  end
end
