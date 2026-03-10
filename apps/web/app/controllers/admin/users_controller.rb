class Admin::UsersController < Admin::BaseController
  def index
    @users = User.includes(:devices, :library_entries).order(created_at: :desc)
  end
end
