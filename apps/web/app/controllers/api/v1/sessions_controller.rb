class Api::V1::SessionsController < Api::V1::BaseController
  skip_before_action :authenticate_device!, only: :create

  def create
    user = User.find_by(email: session_params[:email].to_s.strip.downcase)
    unless user&.authenticate(session_params[:password].to_s)
      render json: { error: "invalid_credentials" }, status: :unauthorized
      return
    end

    device = user.devices.find_or_initialize_by(
      name: device_params[:name].to_s.strip,
      platform: device_params[:platform].to_s.strip
    )
    device.app_version = device_params[:app_version].to_s.strip.presence
    device.last_seen_at = Time.current
    device.regenerate_access_token if device.persisted?

    if device.save
      render json: {
        user: {
          id: user.id,
          name: user.name,
          email: user.email,
          role: user.role
        },
        device: device.api_payload,
        library_entries_count: user.library_entries.count
      }, status: :created
    else
      render_validation_errors!(device)
    end
  end

  def destroy
    current_device.regenerate_access_token
    current_device.save!
    head :no_content
  end

  private

  def session_params
    params.permit(:email, :password)
  end

  def device_params
    raw_device_params = params[:device]
    raw_device_params = ActionController::Parameters.new(raw_device_params.to_h) unless raw_device_params.respond_to?(:permit)
    raw_device_params ||= ActionController::Parameters.new
    raw_device_params.permit(:name, :platform, :app_version)
  end
end
