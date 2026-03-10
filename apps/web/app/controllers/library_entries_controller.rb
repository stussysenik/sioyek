class LibraryEntriesController < ApplicationController
  before_action :set_library_entry, only: %i[show]

  def index
    @library_entries = current_user.library_entries.includes(:document, :reader_sessions).order(updated_at: :desc)
  end

  def show
    @reader_sessions = @library_entry.reader_sessions.includes(:device).order(updated_at: :desc)
    @bookmarks = @library_entry.bookmarks.active.order(page_index: :asc)
    @highlights = @library_entry.highlights.active.order(page_index: :asc)
    @notes = @library_entry.notes.active.order(updated_at: :desc)
  end

  private

  def set_library_entry
    @library_entry = current_user.library_entries.includes(:document).find(params[:id])
  end
end
