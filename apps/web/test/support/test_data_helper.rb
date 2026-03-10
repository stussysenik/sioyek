module TestDataHelper
  def create_user(name: "Test User", email: unique_email, password: "verysecure123!")
    User.create!(
      name: name,
      email: email,
      password: password,
      password_confirmation: password
    )
  end

  def create_admin(name: "Admin User", email: unique_email, password: "verysecure123!")
    User.create!(
      name: name,
      email: email,
      password: password,
      password_confirmation: password,
      role: :admin
    )
  end

  def create_device(user:, name: "MacBook", platform: "macOS", app_version: "0.1.0")
    user.devices.create!(
      name: name,
      platform: platform,
      app_version: app_version,
      last_seen_at: Time.current
    )
  end

  def create_document(fingerprint: unique_fingerprint, filename: "algebra.pdf", title: "Algebra", page_count: 240, metadata: {})
    Document.create!(
      fingerprint: fingerprint,
      filename: filename,
      title: title,
      page_count: page_count,
      metadata: metadata
    )
  end

  def create_library_entry(user:, document:, custom_title: nil)
    user.library_entries.create!(
      document: document,
      custom_title: custom_title,
      last_opened_at: Time.current
    )
  end

  def json_headers(token = nil)
    headers = {
      "ACCEPT" => "application/json",
      "CONTENT_TYPE" => "application/json"
    }
    headers["Authorization"] = "Bearer #{token}" if token.present?
    headers
  end

  def sign_in_as(user, password: "verysecure123!")
    post login_path, params: { email: user.email, password: password }
  end

  private

  def unique_email
    "user-#{SecureRandom.hex(4)}@example.com"
  end

  def unique_fingerprint
    "sha256:#{SecureRandom.hex(16)}"
  end
end

class ActiveSupport::TestCase
  include TestDataHelper
end

class ActionDispatch::IntegrationTest
  include TestDataHelper
end
