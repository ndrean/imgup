defmodule App.Gallery do
  @moduledoc """
  Module for managing user gallery URLs.

  This module provides functions to save and retrieve URLs associated with a user.
  """

  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Gallery.Url
  alias App.Accounts.User

  @doc """
    Save file URLs for a user.

    This function associates file URLs with a user in the database. It expects a user struct and a map containing file URLs to be associated with the user.
    It returns `{:ok, App.Gallery.Url{}}` or `{:error, _}`

    ## Parameters

    - `user`: The user struct to whom the file URLs will be associated. Should be a `%User{}` struct.
    - `file_urls`: A map containing the file URLs to be associated with the user, including `public_url`, `compressed_url`, and `key`.

    ## Examples

        ```
        user = %User{}
        file_urls = %{
          public_url: "https://example.com/key",
          compressed_url: "https://example.com/image_compressed.jpg",
          key: "image_key"
        }
        App.Gallery.save_file_urls_for(user, file_urls)
        ```

  """

  def save_file_urls_for(user: user = %User{}, file_urls: file_urls) when is_map(file_urls) do
    urls = %Url{
      public_url: file_urls.public_url,
      compressed_url: file_urls.compressed_url,
      key: file_urls.key
    }

    Ecto.build_assoc(user, :urls, urls)
    |> Repo.insert()
  end

  @doc """
  Get URLs associated with a user.

  This function retrieves all URLs associated with the specified user from the database.

  It returns a list of `%App.Galley.Url{}` structs or `nil`.

  ## Parameters

  - `user`: The user struct for whom URLs are being retrieved. Should be a `%User{}` struct.

  ## Examples

        ```
        user = %User{}
        urls = App.Gallery.get_urls_by_user(user)
        [%App.Galley.Url{}, %App.Galley.Url{}]
        ```
  """

  def get_urls_by_user(user = %User{}) do
    query =
      from(
        u in Url,
        where: u.user_id == ^user.id
      )

    Repo.all(query)
  end
end
