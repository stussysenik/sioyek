class ReaderSession < ApplicationRecord
  belongs_to :library_entry
  belongs_to :device

  validates :current_page, numericality: { greater_than_or_equal_to: 0 }
  validates :zoom, numericality: { greater_than: 0 }
  validates :library_entry_id, uniqueness: { scope: :device_id }

  def api_payload
    {
      id: id,
      library_entry_id: library_entry_id,
      device_id: device_id,
      current_page: current_page,
      zoom: zoom,
      fit_to_window: fit_to_window,
      last_opened_at: last_opened_at,
      client_updated_at: client_updated_at,
      updated_at: updated_at
    }
  end
end
