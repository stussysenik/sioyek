class ApplicationController < ActionController::Base
  before_action :require_login

  helper_method :current_user, :logged_in?

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    current_user.present?
  end

  def require_login
    return if logged_in?

    redirect_to login_path, alert: "Sign in to access the sync service."
  end

  def require_admin
    return if current_user&.admin?

    redirect_to root_path, alert: "Admin access is required."
  end
end
