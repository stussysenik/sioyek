class Api::V1::BookmarksController < Api::V1::BaseController
  def index
    library_entry = find_library_entry!
    render json: { bookmarks: library_entry.bookmarks.order(:page_index, :updated_at).map(&:api_payload) }
  end

  def upsert
    library_entry = find_library_entry!
    synced = sync_payloads(payload_key: :bookmarks).map do |payload|
      record = library_entry.bookmarks.find_or_initialize_by(external_id: payload[:external_id])
      record.assign_attributes(
        device: current_device,
        page_index: payload[:page_index],
        label: payload[:label],
        note: payload[:note],
        client_updated_at: parse_client_time(payload[:client_updated_at]),
        deleted_at: payload[:deleted_at].present? ? parse_client_time(payload[:deleted_at]) : nil
      )
      record.save!
      record.api_payload
    end

    render json: { bookmarks: synced }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors!(e.record)
  end

  private

  def sync_payloads(payload_key:)
    permitted_array(payload_key, :external_id, :page_index, :label, :note, :client_updated_at, :deleted_at)
  end
end
