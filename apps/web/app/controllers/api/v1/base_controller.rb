class Api::V1::BaseController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate_device!

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  private

  attr_reader :current_device, :current_user

  def authenticate_device!
    @current_device = authenticate_with_http_token do |token, _options|
      Device.includes(:user).find_by(access_token: token)
    end

    if @current_device.blank?
      render json: { error: "unauthorized" }, status: :unauthorized
      return
    end

    @current_user = @current_device.user
    @current_device.touch_last_seen!
  end

  def library_entry_scope
    current_user.library_entries.includes(:document)
  end

  def find_library_entry!
    library_entry_scope.find(params[:library_entry_id] || params[:id])
  end

  def parse_client_time(value)
    value.present? ? Time.zone.parse(value) : Time.current
  rescue ArgumentError
    Time.current
  end

  def render_validation_errors!(record)
    render json: { error: "validation_failed", details: record.errors.full_messages }, status: :unprocessable_entity
  end

  def permitted_array(payload_key, *fields)
    Array.wrap(params.require(payload_key)).map do |entry|
      if entry.respond_to?(:permit)
        entry.permit(*fields).to_h.symbolize_keys
      else
        entry.to_h.symbolize_keys.slice(*fields)
      end
    end
  end
end
