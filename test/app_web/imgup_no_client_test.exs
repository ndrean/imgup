assert AppWeb.ImgupNoClientLive.clean_name("Screen at 1.2.3.png") == "Screenat123"

assert AppWeb.ImgupNoClientLive.build_thumb_name("aze.png") == "aze-th.png"

assert AppWeb.ImgupNoClientLive.build_url_path("aze.png") == "/aze.png"

assert AppWeb.ImgupNoClientLive.build_image_url("aze.png") ==
         "http://localhost:4000/image_uploads/aze.png"

assert AppWeb.ImgupNoClientLive.build_dest("aze.png") ==
         "/Users/nevendrean/code/elixir/imgup/_build/dev/lib/app/priv/static/image_uploads/aze.png"
