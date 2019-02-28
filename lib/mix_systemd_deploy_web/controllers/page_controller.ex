defmodule MixSystemdDeployWeb.PageController do
  use MixSystemdDeployWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
