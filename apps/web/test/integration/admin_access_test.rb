require "test_helper"

class AdminAccessTest < ActionDispatch::IntegrationTest
  test "member users are redirected away from admin pages" do
    member = create_user(name: "Member")

    sign_in_as(member)
    get admin_users_path

    assert_redirected_to root_path
  end

  test "admin users can open the admin pages" do
    admin = create_admin(name: "Admin")
    create_user(name: "Student")
    create_library_entry(user: admin, document: create_document(title: "Physics"))

    sign_in_as(admin)

    get admin_users_path
    assert_response :success
    assert_includes response.body, "Student"

    get admin_documents_path
    assert_response :success
    assert_includes response.body, "Physics"
  end
end
