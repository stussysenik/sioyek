require "test_helper"

class ApiSyncFlowTest < ActionDispatch::IntegrationTest
  test "registers a document and syncs reader state, bookmarks, highlights, and notes" do
    user = create_user(name: "Sync Student")
    device = create_device(user: user, name: "Lab iMac")

    post register_api_v1_library_entries_path,
         params: {
           fingerprint: "sha256:reader-doc-1",
           filename: "chemistry.pdf",
           title: "Chemistry 101",
           page_count: 512,
           metadata: { source: "desktop-import" }
         }.to_json,
         headers: json_headers(device.access_token)

    assert_response :created
    registration_payload = JSON.parse(response.body)
    library_entry_id = registration_payload.dig("library_entry", "id")
    assert_equal "Chemistry 101", registration_payload.dig("library_entry", "title")
    assert_equal 0, registration_payload.fetch("bookmark_count")

    post upsert_api_v1_reader_session_path,
         params: {
           library_entry_id: library_entry_id,
           current_page: 42,
           zoom: 1.35,
           fit_to_window: false,
           last_opened_at: "2026-03-10T11:00:00Z",
           client_updated_at: "2026-03-10T11:00:00Z"
         }.to_json,
         headers: json_headers(device.access_token)

    assert_response :ok
    session_payload = JSON.parse(response.body).fetch("reader_session")
    assert_equal 42, session_payload.fetch("current_page")
    assert_equal false, session_payload.fetch("fit_to_window")

    post upsert_api_v1_bookmarks_path,
         params: {
           library_entry_id: library_entry_id,
           bookmarks: [
             {
               external_id: "bookmark-1",
               page_index: 42,
               label: "Key chapter",
               note: "Review this before class",
               client_updated_at: "2026-03-10T11:01:00Z"
             }
           ]
         }.to_json,
         headers: json_headers(device.access_token)

    assert_response :ok
    assert_equal 1, JSON.parse(response.body).fetch("bookmarks").length

    post upsert_api_v1_highlights_path,
         params: {
           library_entry_id: library_entry_id,
           highlights: [
             {
               external_id: "highlight-1",
               page_index: 43,
               quote: "Atoms bond by sharing electrons.",
               color: "yellow",
               anchor: "page=43&x=10&y=22",
               annotation_text: "Core definition",
               client_updated_at: "2026-03-10T11:02:00Z"
             }
           ]
         }.to_json,
         headers: json_headers(device.access_token)

    assert_response :ok
    highlight_payload = JSON.parse(response.body).fetch("highlights").first
    assert_equal "highlight-1", highlight_payload.fetch("external_id")

    post upsert_api_v1_notes_path,
         params: {
           library_entry_id: library_entry_id,
           notes: [
             {
               external_id: "note-1",
               page_index: 43,
               body: "Ask about ionic bonds next lesson.",
               highlight_external_id: "highlight-1",
               client_updated_at: "2026-03-10T11:03:00Z"
             }
           ]
         }.to_json,
         headers: json_headers(device.access_token)

    assert_response :ok
    note_payload = JSON.parse(response.body).fetch("notes").first
    assert_equal "highlight-1", note_payload.fetch("highlight_external_id")

    get api_v1_library_entries_path, headers: json_headers(device.access_token)
    assert_response :success
    assert_equal 1, JSON.parse(response.body).fetch("library_entries").length

    get api_v1_reader_session_path, params: { library_entry_id: library_entry_id }, headers: json_headers(device.access_token)
    assert_response :success
    assert_equal 42, JSON.parse(response.body).dig("reader_session", "current_page")

    get api_v1_bookmarks_path, params: { library_entry_id: library_entry_id }, headers: json_headers(device.access_token)
    assert_response :success
    assert_equal "bookmark-1", JSON.parse(response.body).fetch("bookmarks").first.fetch("external_id")

    get api_v1_highlights_path, params: { library_entry_id: library_entry_id }, headers: json_headers(device.access_token)
    assert_response :success
    assert_equal "highlight-1", JSON.parse(response.body).fetch("highlights").first.fetch("external_id")

    get api_v1_notes_path, params: { library_entry_id: library_entry_id }, headers: json_headers(device.access_token)
    assert_response :success
    assert_equal "note-1", JSON.parse(response.body).fetch("notes").first.fetch("external_id")
  end
end
