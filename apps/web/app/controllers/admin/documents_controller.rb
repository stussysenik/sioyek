class Admin::DocumentsController < Admin::BaseController
  def index
    @documents = Document.includes(:library_entries).order(updated_at: :desc)
  end
end
