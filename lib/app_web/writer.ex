defmodule MyWriter do
  @behaviour Phoenix.LiveView.UploadWriter
  require Logger

  @impl true
  def init(_opts) do
    {:ok, %{total_size: 0, file: ""}}
  end

  @impl true
  def meta(state), do: state

  @impl true
  def write_chunk(data, state) do
    {:ok,
     state
     |> Map.update!(:total_size, &(&1 + byte_size(data)))
     |> Map.update!(:file, &(&1 <> data))}
  end

  @impl true
  def close(state, :done) do
    {:ok, state}
  end

  def close(state, reason) do
    {:ok, Map.put(state, :errors, inspect(reason))}
  end
end
