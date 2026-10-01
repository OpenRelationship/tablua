defmodule MossWeb.Router do
  use MossWeb, :router

  import MossWeb.Auth, only: [require_person: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MossWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # a computer's app: its own page, no layout, no CSRF token (MossWeb.AppController)
  pipeline :app do
    plug :fetch_session
    plug :require_person
  end

  scope "/computers/:id/app", MossWeb do
    pipe_through :app

    match :*, "/*path", AppController, :serve
  end

  scope "/", MossWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # every page past here is a signed-in person's (MossWeb.Auth)
  scope "/", MossWeb do
    pipe_through [:browser, :require_person]

    live_session :person, on_mount: {MossWeb.Auth, :person} do
      live "/computers/:id", ComputerLive
      live "/mail", MailLive
    end
  end
end
