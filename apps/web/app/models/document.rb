class Document < ApplicationRecord
  has_many :library_entries, dependent: :destroy

  validates :fingerprint, presence: true, uniqueness: true
  validates :filename, presence: true

  def display_title
    title.presence || filename
  end

  def api_payload
    {
      id: id,
      fingerprint: fingerprint,
      title: display_title,
      filename: filename,
      page_count: page_count,
      metadata: metadata
    }
  end
end
