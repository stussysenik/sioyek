module SyncableRecord
  extend ActiveSupport::Concern

  included do
    scope :active, -> { where(deleted_at: nil) }

    validates :external_id, presence: true
    validates :client_updated_at, presence: true
    validates :page_index, numericality: { greater_than_or_equal_to: 0 }
  end

  def deleted?
    deleted_at.present?
  end

  def sync_payload
    {
      external_id: external_id,
      page_index: page_index,
      client_updated_at: client_updated_at,
      deleted_at: deleted_at,
      updated_at: updated_at
    }
  end
end
