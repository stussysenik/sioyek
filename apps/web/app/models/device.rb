class Device < ApplicationRecord
  belongs_to :user

  has_many :reader_sessions, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :highlights, dependent: :destroy
  has_many :notes, dependent: :destroy

  has_secure_token :access_token

  before_validation :normalize_strings

  validates :name, :platform, :access_token, presence: true
  validates :access_token, uniqueness: true

  def touch_last_seen!
    touch(:last_seen_at)
  end

  def api_payload
    {
      id: id,
      name: name,
      platform: platform,
      app_version: app_version,
      access_token: access_token,
      last_seen_at: last_seen_at
    }
  end

  private

  def normalize_strings
    self.name = name.to_s.strip
    self.platform = platform.to_s.strip
    self.app_version = app_version.to_s.strip.presence
  end
end
