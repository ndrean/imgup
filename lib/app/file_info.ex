defmodule FileMime do
  @moduledoc """
  This module retrives information about files using the unix command "file".
  It just gives you the files MIME-type in a string representation.
  """

  def info(names) when is_list(names) do
    Enum.map(names, &info(&1))
  end

  def info(name) when is_binary(name) do
    case File.exists?(name) do
      false ->
        {:error, "File does not exist"}

      true ->
        {result, 0} = System.cmd("file", ["--mime-type" | [name]])

        [n, mime] =
          result
          |> String.split("\n")
          |> Stream.filter(&(&1 !== ""))
          |> Stream.map(&String.split(&1, ": "))
          |> Enum.into([])
          |> List.flatten()

        {:ok, %{short_name: Path.basename(n), type: mime, path: name, ext: Path.extname(name)}}
    end
  end
end
