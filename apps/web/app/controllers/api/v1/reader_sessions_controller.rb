class Api::V1::ReaderSessionsController < Api::V1::BaseController
  def show
    library_entry = find_library_entry!
    session_record = library_entry.reader_sessions.order(last_opened_at: :desc, updated_at: :desc).first

    render json: {
      reader_session: session_record&.api_payload
    }
  end

  def upsert
    library_entry = find_library_entry!
    session_record = library_entry.reader_sessions.find_or_initialize_by(device: current_device)
    session_record.assign_attributes(
      current_page: reader_session_params[:current_page],
      zoom: reader_session_params[:zoom],
      fit_to_window: reader_session_params[:fit_to_window],
      last_opened_at: parse_client_time(reader_session_params[:last_opened_at]),
      client_updated_at: parse_client_time(reader_session_params[:client_updated_at])
    )

    if session_record.save
      render json: { reader_session: session_record.api_payload }, status: :ok
    else
      render_validation_errors!(session_record)
    end
  end

  private

  def reader_session_params
    params.permit(:library_entry_id, :current_page, :zoom, :fit_to_window, :last_opened_at, :client_updated_at)
  end
end
