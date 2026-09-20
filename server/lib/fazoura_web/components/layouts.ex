defmodule FazouraWeb.Layouts do
  @moduledoc "Layouts for the admin dashboard — the only HTML this server renders."

  use FazouraWeb, :html

  @doc "Page shell: styles and the LiveView client."
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Fazoura admin</title>
        <style>
          <%= raw(styles()) %>
        </style>
        <script defer src="/admin/js/phoenix/phoenix.min.js">
        </script>
        <script defer src="/admin/js/live/phoenix_live_view.min.js">
        </script>
        <script defer src={~p"/assets/admin.js"}>
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  @doc "Dashboard chrome: nav and flash messages around each LiveView."
  def admin(assigns) do
    ~H"""
    <main class="wrap">
      <header class="top">
        <div class="brand">FAZOURA <span>admin</span></div>
        <nav>
          <.link navigate={~p"/admin"} class={nav_class(@page, :stats)}>Stats</.link>
          <.link navigate={~p"/admin/quizzes"} class={nav_class(@page, :quizzes)}>Quizzes</.link>
          <.link navigate={~p"/admin/tags"} class={nav_class(@page, :tags)}>Tags</.link>
        </nav>
      </header>

      <p :if={Phoenix.Flash.get(@flash, :info)} class="flash ok" id="flash-info">
        {Phoenix.Flash.get(@flash, :info)}
      </p>
      <p :if={Phoenix.Flash.get(@flash, :error)} class="flash bad" id="flash-error">
        {Phoenix.Flash.get(@flash, :error)}
      </p>

      {@inner_content}
    </main>
    """
  end

  defp nav_class(page, page), do: "tab on"
  defp nav_class(_page, _tab), do: "tab"

  defp styles do
    """
    :root {
      --bg: #0E0D0C; --panel: #1A1917; --line: #2C2A27; --ink: #FBF6EC;
      --dim: #9A9284; --ac: #FFC400; --ac2: #FF4D6D; --ok: #4ADE80;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; background: var(--bg); color: var(--ink);
      font: 14px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    }
    a { color: inherit; }
    .wrap { max-width: 1040px; margin: 0 auto; padding: 24px 20px 64px; }
    .top {
      display: flex; align-items: center; justify-content: space-between;
      gap: 16px; flex-wrap: wrap; border-bottom: 1px solid var(--line);
      padding-bottom: 16px; margin-bottom: 24px;
    }
    .brand { font-weight: 800; letter-spacing: .14em; color: var(--ac); }
    .brand span { color: var(--dim); font-weight: 400; letter-spacing: .2em; }
    nav { display: flex; gap: 8px; }
    .tab {
      text-decoration: none; padding: 7px 14px; border-radius: 999px;
      border: 1px solid var(--line); color: var(--dim);
    }
    .tab.on { background: var(--ac); border-color: var(--ac); color: var(--bg); }
    h2 { font-size: 15px; letter-spacing: .12em; text-transform: uppercase;
         color: var(--dim); margin: 32px 0 12px; font-weight: 600; }
    .cards { display: grid; gap: 12px; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); }
    .card { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; padding: 16px; }
    .card .label { color: var(--dim); font-size: 11px; letter-spacing: .14em; text-transform: uppercase; }
    .card .value { font-size: 34px; font-weight: 800; margin: 6px 0 2px; }
    .card .hint { color: var(--dim); font-size: 11.5px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--line); vertical-align: top; }
    th { color: var(--dim); font-size: 11px; letter-spacing: .12em; text-transform: uppercase; font-weight: 600; }
    tr:last-child td { border-bottom: 0; }
    .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 14px; overflow: hidden; }
    .empty { color: var(--dim); padding: 16px; }
    .pill {
      display: inline-block; padding: 2px 9px; border-radius: 999px; font-size: 11px;
      border: 1px solid var(--line); color: var(--dim); margin-right: 5px;
    }
    .pill.preset { color: var(--ok); border-color: var(--ok); }
    .pill.live { color: var(--ac); border-color: var(--ac); }
    button {
      font: inherit; cursor: pointer; border-radius: 999px; padding: 6px 13px;
      border: 1px solid var(--line); background: transparent; color: var(--ink);
    }
    button:hover { border-color: var(--ac); }
    button.danger { color: var(--ac2); border-color: rgba(255,77,109,.4); }
    button.primary { background: var(--ac); border-color: var(--ac); color: var(--bg); font-weight: 700; }
    input[type=text], textarea {
      font: inherit; width: 100%; background: #121110; color: var(--ink);
      border: 1px solid var(--line); border-radius: 10px; padding: 10px 12px;
    }
    textarea { min-height: 160px; resize: vertical; }
    input[type=file] { font: inherit; color: var(--dim); max-width: 100%; }
    form.row { display: flex; gap: 8px; align-items: center; }
    .flash { padding: 11px 14px; border-radius: 12px; margin: 0 0 18px; }
    .flash.ok { background: rgba(74,222,128,.12); color: var(--ok); }
    .flash.bad { background: rgba(255,77,109,.12); color: var(--ac2); }
    .tags { display: flex; flex-wrap: wrap; gap: 8px; }
    .tagchip {
      display: inline-flex; align-items: center; gap: 8px; padding: 6px 8px 6px 13px;
      border-radius: 999px; border: 1px solid var(--line); background: var(--panel);
    }
    .tagchip button { border: 0; padding: 0 4px; color: var(--dim); }
    .muted { color: var(--dim); }
    details summary { cursor: pointer; color: var(--dim); margin: 24px 0 12px; }
    """
  end
end
