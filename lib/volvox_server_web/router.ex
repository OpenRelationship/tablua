defmodule VolvoxServerWeb.Router do
  use VolvoxServerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VolvoxServerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", VolvoxServerWeb do
    pipe_through :browser

    live "/runs/:id", RunLive
    live "/computers/:id", ComputerLive
  end
end
