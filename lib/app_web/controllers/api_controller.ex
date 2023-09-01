defmodule AppWeb.ApiController do
  use AppWeb, :controller
  require Logger

  def create(conn, %{"" => params}) do
    # Check if content_type e.g: "image/png"
    if String.contains?(params.content_type, "image") do
      case App.Upload.upload(params) do
        {:ok, body} ->
          render(conn, :success, body)

        {:error, :failure_read} ->
          render(conn |> put_status(400), %{body: "Error uploading file. Failure reading file."})

        {:error, :invalid_extension} ->
          render(conn |> put_status(400), %{
            body: "Error uploading file. The content type of the uploaded file is not valid."
          })

        {:error, :invalid_cid} ->
          render(conn |> put_status(400), %{
            body:
              "Error uploading file. The contents of the uploaded file may be empty or invalid."
          })

        _ ->
          render(conn |> put_status(400), %{
            body: "There was an error uploading the file. Please try again later."
          })
      end
    else
      render(conn |> put_status(400), %{body: "Uploaded file is not a valid image."})
    end
  end

  # Preserve backward compatibility with "image" keyword:
  def create(conn, %{"image" => image}) do
    create(conn, %{"" => image})
  end
end
