require "test_helper"

class SessionsFlowTest < ActionDispatch::IntegrationTest
  test "login is required for the dashboard and sign in works" do
    user = create_user(name: "Reader Kid")

    get root_path
    assert_redirected_to login_path

    post login_path, params: { email: user.email.upcase, password: "verysecure123!" }
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Sync overview"
  end

  test "logout clears the session" do
    user = create_user

    sign_in_as(user)
    delete logout_path

    assert_redirected_to login_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Sign in"
  end
end
