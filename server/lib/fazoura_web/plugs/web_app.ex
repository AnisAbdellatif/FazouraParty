defmodule FazouraWeb.Plugs.WebApp do
  @moduledoc """
  Serves the built Flutter web app (the PWA) from `:web_dir`, next to the API it talks to.

  Caching is left to the service worker, which is keyed by a hash of the bundle
  (`app/tool/build_web.dart`): every file here is served with an ETag and
  `max-age=0, must-revalidate`, so a client either gets a cheap `304` or the new bytes,
  and never a stale app shell. Repeat visits don't reach the network at all — the worker
  answers from its own cache.

  Compression is precomputed. The build writes a brotli copy beside each compressible
  file and `Plug.Static` hands that out when the client accepts `br`, which is about a
  quarter smaller than gzip across the boot path and costs the server nothing per
  request. Anything without a `.br` — or a client that doesn't want one — falls through
  to Caddy, which compresses on the fly as it always did.

  With `:web_dir` unset or missing (a server that only serves the API), this does nothing.
  """

  @behaviour Plug

  # Everything `flutter build web` emits that a browser may ask for.
  @served ~w(
    assets canvaskit icons
    apple-touch-icon.png build-manifest.json favicon.png flutter.js flutter_bootstrap.js
    flutter_service_worker.js index.html main.dart.js main.dart.wasm main.dart.mjs
    manifest.json version.json
  )

  # The deferred chunks dart2js emits for the screens a guest never opens
  # (`main.dart.js_1.part.js`). Their names carry a number, so they cannot be
  # listed: `:only` matches a whole first segment, `:only_matching` a prefix.
  # Without this they 404, which takes the screens *and* the service worker
  # with them — one 404 inside `cache.addAll` rejects the whole install.
  @served_prefixes ~w(main.dart.js_)

  @cache_control "public, max-age=0, must-revalidate"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case dir() do
      nil -> conn
      dir -> serve(conn, dir)
    end
  end

  @doc "The directory the web app is served from, or nil when there isn't one."
  @spec dir() :: String.t() | nil
  def dir do
    case Application.get_env(:fazoura, :web_dir) do
      path when is_binary(path) -> if File.dir?(path), do: path
      _ -> nil
    end
  end

  defp serve(%{path_info: []} = conn, dir), do: conn |> protect() |> send_index(dir)

  defp serve(conn, dir) do
    Plug.Static.call(
      protect(conn),
      Plug.Static.init(
        at: "/",
        from: dir,
        only: @served,
        only_matching: @served_prefixes,
        brotli: true,
        cache_control_for_etags: @cache_control,
        cache_control_for_vsn_requests: @cache_control
      )
    )
  end

  # No other site may frame the app: a host's controls under somebody else's page are
  # a click away from ending a party or removing a player. A full CSP is left out on
  # purpose — Flutter's renderer needs `wasm-unsafe-eval` and inline bootstrap, and a
  # policy loose enough for that buys little — but framing is the one it can refuse.
  defp protect(conn) do
    Plug.Conn.merge_resp_headers(conn, [
      {"content-security-policy", "frame-ancestors 'none'"},
      {"x-frame-options", "DENY"},
      {"x-content-type-options", "nosniff"},
      {"referrer-policy", "no-referrer"}
    ])
  end

  # The app is a single page: "/" is the shell.
  defp send_index(conn, dir) do
    index = Path.join(dir, "index.html")

    if File.regular?(index) do
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.put_resp_header("cache-control", @cache_control)
      |> Plug.Conn.send_file(200, index)
      |> Plug.Conn.halt()
    else
      conn
    end
  end
end
