defmodule App.Gallery do
  @moduledoc false
  import Ecto.Query, warn: false
  alias App.Repo
  alias App.Gallery.Url
  alias App.Accounts.User

  @json_lib Phoenix.json_library()

  def save_file_urls_for(user: user = %User{}, file_urls: file_urls) when is_map(file_urls) do
    urls = %Url{
      public_url: file_urls.public_url,
      compressed_url: file_urls.compressed_url,
      key: file_urls.key
    }

    Ecto.build_assoc(user, :urls, urls)
    |> Repo.insert()
  end

  def get_urls_by_user(user = %User{}) do
    query =
      from(
        u in Url,
        where: u.user_id == ^user.id
      )

    Repo.all(query)
    |> dbg()
  end
end
