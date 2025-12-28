defmodule ComoWeb.Router do
  use ComoWeb, :router

  import ComoWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ComoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :redirect_if_authenticated do
    plug :redirect_if_user_is_authenticated
  end

  pipeline :require_authenticated do
    plug :require_authenticated_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ComoWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", ComoWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/signin", AuthController, :index
    post "/signin", AuthController, :send_magic_link
    get "/signin/token/:token", AuthController, :signin_with_token
    get "/signup/token/:token", AuthController, :signup_with_token
  end

  # Other scopes may use custom stacks.
  # scope "/api", ComoWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:como, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ComoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
