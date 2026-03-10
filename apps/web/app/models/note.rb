class Note < ApplicationRecord
  include SyncableRecord

  belongs_to :library_entry
  belongs_to :device
  belongs_to :highlight, optional: true

  validates :external_id, uniqueness: { scope: :library_entry_id }

  def api_payload
    sync_payload.merge(
      body: body,
      highlight_external_id: highlight&.external_id
    )
  end
end
