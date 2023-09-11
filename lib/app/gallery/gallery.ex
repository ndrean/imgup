defmodule App.Gallery do
  @moduledoc """
  Module for managing user gallery URLs.

  This module provides functions to save and retrieve URLs associated with a user.
  """

  import Ecto.Query, warn: false
  alias App.Accounts.User
  alias App.Gallery.{Url, Thumb}
  alias App.Repo

  def get_thumbs_by_user(%User{} = user) do
    query =
      from(
        u in Thumb,
        where: u.user_id == ^user.id
      )

    Repo.all(query)
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

  def get_urls_by_user(%User{} = user) do
    query =
      from(
        u in Url,
        where: u.user_id == ^user.id
      )

    Repo.all(query)
  end

  def get_limited_urls_by_user(%User{} = user, limit, offset) do
    query =
      from(
        u in Url,
        where: u.user_id == ^user.id,
        limit: ^limit,
        offset: ^offset
      )

    Repo.all(query)
  end
end
