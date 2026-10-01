defmodule VolvoxServerWeb.Router do
  use VolvoxServerWeb, :router

  import VolvoxServerWeb.Auth, only: [require_person: 2]

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

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # every page past here is a signed-in person's (VolvoxServerWeb.Auth)
  scope "/", VolvoxServerWeb do
    pipe_through [:browser, :require_person]

    live_session :person, on_mount: {VolvoxServerWeb.Auth, :person} do
      live "/runs/:id", RunLive
      live "/computers/:id", ComputerLive
      live "/mail", MailLive
    end
  end
end
