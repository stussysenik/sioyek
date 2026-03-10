class Api::V1::NotesController < Api::V1::BaseController
  def index
    library_entry = find_library_entry!
    render json: { notes: library_entry.notes.order(:page_index, :updated_at).map(&:api_payload) }
  end

  def upsert
    library_entry = find_library_entry!
    synced = sync_payloads(payload_key: :notes).map do |payload|
      highlight = if payload[:highlight_external_id].present?
        library_entry.highlights.find_by!(external_id: payload[:highlight_external_id])
      end

      record = library_entry.notes.find_or_initialize_by(external_id: payload[:external_id])
      record.assign_attributes(
        device: current_device,
        highlight: highlight,
        page_index: payload[:page_index],
        body: payload[:body],
        client_updated_at: parse_client_time(payload[:client_updated_at]),
        deleted_at: payload[:deleted_at].present? ? parse_client_time(payload[:deleted_at]) : nil
      )
      record.save!
      record.api_payload
    end

    render json: { notes: synced }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors!(e.record)
  end

  private

  def sync_payloads(payload_key:)
    permitted_array(payload_key, :external_id, :page_index, :body, :highlight_external_id, :client_updated_at, :deleted_at)
  end
end
