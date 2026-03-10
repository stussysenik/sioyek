class User < ApplicationRecord
  enum :role, { member: 0, admin: 1 }, default: :member

  has_secure_password

  has_many :devices, dependent: :destroy
  has_many :library_entries, dependent: :destroy
  has_many :documents, through: :library_entries

  before_validation :normalize_email

  validates :name, presence: true
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, if: -> { password.present? }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
