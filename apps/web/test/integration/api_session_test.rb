require "test_helper"

class ApiSessionTest < ActionDispatch::IntegrationTest
  test "creates a device session for the Zig client" do
    create_user(name: "Zig Reader", email: "reader@example.com")

    post api_v1_session_path,
         params: {
           email: "READER@example.com",
           password: "verysecure123!",
           device: {
             name: "Classroom Mac",
             platform: "macOS",
             app_version: "0.2.0"
           }
         }.to_json,
         headers: json_headers

    assert_response :created

    payload = JSON.parse(response.body)
    assert_equal "reader@example.com", payload.dig("user", "email")
    assert_equal "Classroom Mac", payload.dig("device", "name")
    assert payload.dig("device", "access_token").present?
  end

  test "rejects invalid credentials" do
    create_user(email: "reader@example.com")

    post api_v1_session_path,
         params: {
           email: "reader@example.com",
           password: "wrong-password",
           device: { name: "Classroom Mac", platform: "macOS" }
         }.to_json,
         headers: json_headers

    assert_response :unauthorized
    assert_equal "invalid_credentials", JSON.parse(response.body).fetch("error")
  end
end
