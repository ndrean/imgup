defmodule App.OneTapControllerTest do
  use App.ConnCase

  setup do
    {:ok, conn: Phoenix.ConnTest.conn()}
  end

  test "received", %{conn: conn} do
    profile = %{
      "aud" => "something.apps.googleusercontent.com",
      "azp" => "something.apps.googleusercontent.comm",
      "email" => "me@gmail.com",
      "email_verified" => true,
      "exp" => 1_693_383_363,
      "family_name" => "D",
      "given_name" => "N",
      "iat" => 1_693_379_763,
      "iss" => "https://accounts.google.com",
      "jti" => "1ea91bcf363fd8ee02e0e24721720f7221b218d3",
      "locale" => "fr",
      "name" => "ND",
      "nbf" => 1_693_379_463,
      "nonce" => "C7Xky04jn8263F_KVAQw4g",
      "picture" =>
        "https://lh3.googleusercontent.com/a/AAcHTteP-xfF3Dbf5MQtnFoPhMZPZNnkEpBsxBiD4o_zobpW=s96-c",
      "sub" => "1013538695105826384"
    }
  end
end
