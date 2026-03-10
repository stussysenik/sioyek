class LibraryEntry < ApplicationRecord
  belongs_to :user
  belongs_to :document

  has_many :reader_sessions, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :highlights, dependent: :destroy
  has_many :notes, dependent: :destroy

  validates :document_id, uniqueness: { scope: :user_id }

  def display_title
    custom_title.presence || document.display_title
  end

  def latest_reader_session
    reader_sessions.order(last_opened_at: :desc, updated_at: :desc).first
  end

  def api_payload
    {
      id: id,
      title: display_title,
      custom_title: custom_title,
      last_opened_at: last_opened_at,
      document: document.api_payload
    }
  end
end
