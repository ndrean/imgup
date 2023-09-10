setup do
  file_element =
    %{
      progress: 100,
      __struct__: Phoenix.LiveView.UploadEntry,
      errors: [],
      valid?: true,
      ref: "0",
      client_size: 2_504_782,
      client_name: "action.jpg",
      client_type: "image/jpeg",
      uuid: "38809d8d-e080-4f14-a137-13e50cd23c56",
      compressed_path:
        "/Users/nevendrean/code/elixir/imgup/_build/dev/lib/app/priv/static/image_uploads/action-comp.jpg",
      done?: true,
      image_url: "http://localhost:4000/image_uploads/action.jpg",
      compressed_name: "action-comp.jpg",
      upload_ref: "phx-F4JGIKN9v6ORWQXC",
      preflighted?: true,
      upload_config: :image_list,
      cancelled?: false,
      client_last_modified: 1_693_731_232_407,
      client_relative_path: ""
    }

  entry =
    %Phoenix.LiveView.UploadEntry{
      progress: 100,
      preflighted?: true,
      upload_config: :image_list,
      upload_ref: "phx-F4NSgF6BAJ2Dng8C",
      ref: "0",
      uuid: "808e6ae7-c6fe-4f8e-acdb-812497b4fe0f",
      valid?: true,
      done?: true,
      cancelled?: false,
      client_name: "Screenshot 2023-06-06 at 17.52.01.png",
      client_relative_path: "",
      client_size: 99_767,
      client_type: "image/png",
      client_last_modified: 1_686_066_727_004
    }

  %{element: file_element, entry: entry}
end

describe "temp files created when preloading" do
end

describe "temp files removed when remove-selected" do
end

describe "temp files removed when uploaded" do
end

describe "db updated when uploaded" do
end

describe "bucket updated when uploaded" do
end

describe "deleted from db when delete-uploaded" do
end

describe "delete from bucket when delete-uploaded" do
end

describe "utilities tests" do
  assert AppWeb.ImgupNoClientLive.clean_name("Screen at 1.2.3.png") == "Screenat123"

  assert AppWeb.ImgupNoClientLive.build_thumb_name("aze.png") == "aze-th.png"

  assert AppWeb.ImgupNoClientLive.build_url_path("aze.png") == "/aze.png"

  assert AppWeb.ImgupNoClientLive.build_image_url("aze.png") ==
           "http://localhost:4000/image_uploads/aze.png"

  assert AppWeb.ImgupNoClientLive.build_dest("aze.png") ==
           "/Users/nevendrean/code/elixir/imgup/_build/dev/lib/app/priv/static/image_uploads/aze.png"
end
