class Api::V1::LibraryEntriesController < Api::V1::BaseController
  def index
    render json: {
      library_entries: library_entry_scope.order(updated_at: :desc).map(&:api_payload)
    }
  end

  def register
    ActiveRecord::Base.transaction do
      document = Document.find_or_initialize_by(fingerprint: registration_params[:fingerprint])
      document.assign_attributes(
        title: registration_params[:title].presence,
        filename: registration_params[:filename],
        page_count: registration_params[:page_count],
        metadata: registration_params[:metadata].presence || document.metadata || {}
      )
      document.save!

      library_entry = current_user.library_entries.find_or_initialize_by(document: document)
      library_entry.custom_title = registration_params[:custom_title].presence
      library_entry.last_opened_at = Time.current
      library_entry.save!

      render json: {
        library_entry: library_entry.api_payload,
        reader_session: library_entry.latest_reader_session&.api_payload,
        bookmark_count: library_entry.bookmarks.active.count,
        highlight_count: library_entry.highlights.active.count,
        note_count: library_entry.notes.active.count
      }, status: library_entry.previous_changes.key?("id") ? :created : :ok
    end
  rescue ActiveRecord::RecordInvalid => e
    render_validation_errors!(e.record)
  end

  private

  def registration_params
    params.permit(:fingerprint, :title, :filename, :page_count, :custom_title, metadata: {})
  end
end
