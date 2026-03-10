class DashboardController < ApplicationController
  def index
    @library_entries = current_user.library_entries.includes(:document).order(updated_at: :desc).limit(8)
    @device_count = current_user.devices.count
    @bookmark_count = current_user.library_entries.joins(:bookmarks).merge(Bookmark.active).count
    @highlight_count = current_user.library_entries.joins(:highlights).merge(Highlight.active).count
    @note_count = current_user.library_entries.joins(:notes).merge(Note.active).count
  end
end
