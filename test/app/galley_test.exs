defmodule App.GalleryTest do
  use ExUnit.Case

  # Make sure to set up your test environment appropriately before running the tests.

  describe "get_urls_by_user/1" do
    # {:ok, _} = Ecto.Adapters.SQL.Sandbox.checkout(App.Repo)

    test "returns a list of URLs for a user" do
      # Create a user record for testing (you may need to use your user creation logic)
      user = insert_user()

      # Create some URLs associated with the user (you may need to use your URL creation logic)
      urls = [
        insert_url(user_id: user.id, public_url: "https://example.com/image1.jpg"),
        insert_url(user_id: user.id, public_url: "https://example.com/image2.jpg")
      ]

      # Call the function being tested
      retrieved_urls = App.Gallery.get_urls_by_user(user)

      # Assert that the retrieved_urls match the expected URLs
      assert retrieved_urls == urls
    end

    test "returns an empty list for a user with no URLs" do
      # Create a user record for testing
      user = insert_user()

      # Call the function being tested
      retrieved_urls = App.Gallery.get_urls_by_user(user)

      # Assert that the retrieved_urls is an empty list
      assert retrieved_urls == []
    end
  end

  # You can define helper functions here to insert users and URLs for testing.
  defp insert_user do
    user_changeset = %App.Accounts.User{
      email: "test@example.com",
      hashed_password: "hashed_password",
      inserted_at: NaiveDateTime.from_iso8601!("2015-01-23T23:50:07"),
      updated_at: NaiveDateTime.from_iso8601!("2015-01-23T23:50:07")
    }

    {:ok, user} = App.Repo.insert(user_changeset)
    user
  end

  defp insert_url(_attrs) do
    url_changeset = %App.Gallery.Url{
      public_url: "https://example.com/image.jpg",
      compressed_url: "https://example.com/image_compressed.jpg",
      key: "image_key",
      user_id: insert_user().id
    }

    {:ok, url} = App.Repo.insert(url_changeset)
    url
  end
end
