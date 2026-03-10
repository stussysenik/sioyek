require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes email before validation" do
    user = User.create!(
      name: "Student Reader",
      email: "  Student@Example.COM ",
      password: "verysecure123!",
      password_confirmation: "verysecure123!"
    )

    assert_equal "student@example.com", user.email
  end

  test "requires a strong enough password when provided" do
    user = User.new(
      name: "Short Password",
      email: unique_email,
      password: "short",
      password_confirmation: "short"
    )

    assert_not user.valid?
    assert_includes user.errors[:password], "is too short (minimum is 12 characters)"
  end
end
