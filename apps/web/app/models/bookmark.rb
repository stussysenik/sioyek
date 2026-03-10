class Bookmark < ApplicationRecord
  include SyncableRecord

  belongs_to :library_entry
  belongs_to :device

  validates :external_id, uniqueness: { scope: :library_entry_id }

  def api_payload
    sync_payload.merge(
      label: label,
      note: note
    )
  end
end
