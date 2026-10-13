Code.require_file("utils/json.ex", __DIR__)
Code.require_file("utils/banner.ex", __DIR__)

defmodule MBuxBot do
  @moduledoc false

  @my_project "Moneybux Miniapp"
  @base_url "https://money-bux.pro"
  @referral "r_6004380466"
  @secret "rAhET?)8–x6hx6^L"
  @ads_max 50

  @reset "\e[0m"
  @bold "\e[1m"
  @red "\e[91m"
  @green "\e[92m"
  @yellow "\e[93m"
  @width 63

  def run do
    :logger.set_primary_config(:level, :error)
    install_signal_handler()

    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    Banner.set_title(@my_project)
    Banner.show_banner(@my_project)

    accounts = load_lines("data.txt")

    if accounts == [] do
      red("File data.txt is empty, please add your initData entries")
      System.halt(1)
    end

    proxies = load_lines("proxy.txt")
    settings = load_settings()

    loop(accounts, proxies, settings, 1)
  end

  defp loop(accounts, proxies, settings, cycle) do
    yellow("Starting automation cycle number #{cycle}")

    accounts
    |> Enum.with_index()
    |> Enum.each(fn {line, index} ->
      if index > 0, do: IO.puts("")

      proxy = proxy_for(proxies, index)

      case proxy do
        nil -> yellow("Running without proxy for this account")
        entry -> yellow("Using proxy #{mask_proxy(entry)}")
      end

      try do
        process_account(line, index + 1, proxy)
      rescue
        _error -> red("Account #{index + 1} was skipped after an error")
      end
    end)

    yellow("All accounts processed for cycle number #{cycle}")

    countdown(sleep_seconds(settings), "Next cycle starts in")

    Banner.show_banner(@my_project)

    loop(accounts, proxies, settings, cycle + 1)
  end

  defp process_account(line, label, proxy) do
    case init_data_of(line) do
      {:ok, init, profile} ->
        state = %{
          init: init,
          label: label,
          username: get(profile, "username", ""),
          first_name: get(profile, "firstName", "")
        }

        case sign_in(state, proxy) do
          {:ok, session} ->
            handle =
              shorten(clean_text(get(profile, "username", state.first_name), "account"), "account", 16)

            state =
              state
              |> Map.put(:handle, handle)
              |> Map.put(:sess, get(session, "sess", ""))

            green(
              "Signed in #{handle} gold #{money(get(session, "gold", 0))} diamonds #{money(get(session, "diamonds", 0))}"
            )

            state
            |> process_checkin(proxy)
            |> process_games(proxy)

          {:error, reason} ->
            red("Account #{label} refused with #{short_reason(reason)}")
        end

      :error ->
        red("Account #{label} line has no usable initData")
    end
  end

  defp sign_in(state, proxy) do
    body = "initData=" <> URI.encode_www_form(state.init) <> "&tgUplineId=" <> @referral

    case post_raw(state, "/authorization", body, "", proxy) do
      {:ok, raw, headers} ->
        case session_of(headers) do
          "" -> {:error, "no session cookie was issued"}
          sess -> {:ok, Map.put(decode_map(raw), "sess", sess)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_checkin(state, proxy) do
    body = "category=daily&id=1&data%5Bpayload%5D=&data%5Bsignature%5D="

    case post_json(state, "/tasks/claimTaskReward", body, proxy) do
      {:ok, data} ->
        case get(data, "icon", "") do
          "success" -> green("Daily check in credited #{money(get(data, "gold", 0))} gold")
          _other -> yellow("Daily check in was already received")
        end

      {:error, reason} ->
        yellow("Daily check in refused with #{short_reason(reason)}")
    end

    state
  end

  defp process_games(state, proxy) do
    case post_raw(state, "/load/games", "", state.sess, proxy) do
      {:ok, html, _headers} ->
        html
        |> game_slugs()
        |> Enum.each(fn slug -> run_game(state, slug, proxy) end)

      {:error, reason} ->
        yellow("Game list refused with #{short_reason(reason)}")
    end

    state
  end

  defp run_game(state, "wheel", proxy), do: process_wheel(state, proxy)
  defp run_game(state, "treasury", proxy), do: process_treasury(state, proxy)
  defp run_game(state, "raiders", proxy), do: process_raiders(state, proxy)
  defp run_game(_state, _slug, _proxy), do: :ok

  defp process_wheel(state, proxy) do
    case game_page(state, "wheel", proxy) do
      {:ok, html} ->
        ads = span_number(html, "adsWatchedToday")
        spins = span_number(html, "spinsCount")
        remaining = max(@ads_max - ads, 0)

        yellow("Spin Wheel #{spins} spins, ads watched #{ads} of #{@ads_max}")

        collect_ads(state, "wheel", "/games/wheel/getAdSpins", remaining, proxy)

        spins =
          case game_page(state, "wheel", proxy) do
            {:ok, fresh} -> span_number(fresh, "spinsCount")
            {:error, _reason} -> spins
          end

        if spins > 0 do
          yellow("Spinning the wheel with #{spins} spins")
          used = spin_all(state, proxy, 0)
          green("Spin Wheel finished with #{used} spins used")
        else
          yellow("No spin is available for this account")
        end

      {:error, reason} ->
        yellow("Spin Wheel page refused with #{short_reason(reason)}")
    end

    state
  end

  defp spin_all(state, proxy, used) do
    case post_json(state, "/games/wheel/startRotation", "multiplier=1", proxy) do
      {:ok, data} ->
        case get(data, "icon", "") do
          "warning" ->
            if used == 0, do: yellow("No spin is available for this account")
            used

          _other ->
            left = whole(get(data, "spins_count", 0), 0)
            green("Spin #{used + 1} done with #{count(left)} spins left")

            if left <= 0 do
              used + 1
            else
              spin_all(state, proxy, used + 1)
            end
        end

      {:error, _reason} ->
        used
    end
  end

  defp process_treasury(state, proxy) do
    case game_page(state, "treasury", proxy) do
      {:ok, html} ->
        ads = span_number(html, "adsWatchedToday")
        keys = span_number(html, "keysCount")
        remaining = max(@ads_max - ads, 0)

        yellow("Treasury #{keys} keys, ads watched #{ads} of #{@ads_max}")

        collect_ads(state, "treasury", "/games/treasury/getAdKeys", remaining, proxy)

        keys =
          case game_page(state, "treasury", proxy) do
            {:ok, fresh} -> span_number(fresh, "keysCount")
            {:error, _reason} -> keys
          end

        if keys > 0 do
          yellow("Opening chests with #{keys} keys")
          opened = chest_all(state, proxy, 0)
          green("Treasury finished with #{opened} chests opened")
        else
          yellow("No key is available for this account")
        end

      {:error, reason} ->
        yellow("Treasury page refused with #{short_reason(reason)}")
    end

    state
  end

  defp chest_all(state, proxy, opened) do
    case post_json(state, "/games/treasury/openChest", "multiplier=1", proxy) do
      {:ok, data} ->
        case get(data, "icon", "") do
          "warning" ->
            if opened == 0, do: yellow("No key is available for this account")
            opened

          _other ->
            left = whole(get(data, "keys_count", 0), 0)

            green(
              "Chest #{opened + 1} opened with #{money(get(data, "gold", 0))} gold, #{count(left)} keys left"
            )

            if left <= 0 do
              opened + 1
            else
              chest_all(state, proxy, opened + 1)
            end
        end

      {:error, _reason} ->
        opened
    end
  end

  defp process_raiders(state, proxy) do
    case game_page(state, "raiders", proxy) do
      {:ok, html} ->
        ads = span_number(html, "adsWatchedToday")
        remaining = max(@ads_max - ads, 0)

        yellow("Raiders ads watched #{ads} of #{@ads_max}")

        if remaining > 0 do
          collect_ads(state, "raiders", "/games/raiders/getAdRaidPasses", remaining, proxy)
        else
          yellow("Raiders ad quota is already full today")
        end

        green("Raiders finished for this account")

      {:error, reason} ->
        yellow("Raiders page refused with #{short_reason(reason)}")
    end

    state
  end

  defp collect_ads(state, _slug, _endpoint, remaining, _proxy) when remaining <= 0, do: state

  defp collect_ads(state, slug, endpoint, remaining, proxy) do
    case post_json(state, endpoint, nil, proxy) do
      {:ok, data} ->
        case get(data, "validation_hash", nil) do
          hash when is_binary(hash) and hash != "" ->
            claim_ad(state, slug, endpoint, hash, proxy)
            collect_ads(state, slug, endpoint, remaining - 1, proxy)

          _other ->
            state
        end

      {:error, _reason} ->
        state
    end
  end

  defp claim_ad(state, slug, endpoint, hash, proxy) do
    payload = "#{hash}:#{state.sess}:#{System.system_time(:second)}:#{nonce()}"
    signature = :crypto.mac(:hmac, :sha256, @secret, payload) |> Base.encode16(case: :lower)

    body =
      "data%5Bpayload%5D=" <> URI.encode_www_form(payload) <> "&data%5Bsignature%5D=" <> signature

    case post_json(state, endpoint, body, proxy) do
      {:ok, data} ->
        case get(data, "icon", "") do
          "success" ->
            green(
              "#{game_label(slug)} ad claimed, ads watched #{count(whole(get(data, "ads_watched_today", 0), 0))} of #{@ads_max}"
            )

          _other ->
            yellow("#{game_label(slug)} ad was refused by the server")
        end

      {:error, _reason} ->
        yellow("#{game_label(slug)} ad was refused by the server")
    end

    state
  end

  defp game_page(state, slug, proxy) do
    case post_raw(state, "/load/games/" <> slug, "", state.sess, proxy) do
      {:ok, raw, _headers} -> {:ok, raw}
      {:error, reason} -> {:error, reason}
    end
  end

  defp post_json(state, path, body, proxy) do
    case post_raw(state, path, body, state.sess, proxy) do
      {:ok, raw, _headers} -> decode_json(raw)
      {:error, reason} -> {:error, reason}
    end
  end

  defp post_raw(_state, path, body, sess, proxy) do
    {profile, auth} = proxy_setup(proxy)
    url = String.to_charlist(@base_url <> path)

    headers =
      [
        {~c"accept", ~c"*/*"},
        {~c"accept-language", ~c"en-US,en;q=0.9"},
        {~c"origin", String.to_charlist(@base_url)},
        {~c"referer", String.to_charlist(@base_url <> "/?tgWebAppStartParam=" <> @referral)},
        {~c"user-agent",
         ~c"Mozilla/5.0 (Linux; Android 16; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.7922.18 Mobile Safari/537.36 Telegram-Android/12.8.1 (Oppo CPH2631; Android 16; SDK 36; HIGH)"},
        {~c"x-requested-with", ~c"XMLHttpRequest"}
      ] ++ session_header(sess)

    options = [ssl: [verify: :verify_none], timeout: 30_000, connect_timeout: 15_000] ++ auth

    handle(
      :httpc.request(
        :post,
        {url, headers, ~c"application/x-www-form-urlencoded; charset=UTF-8", to_charlist(body)},
        options,
        [body_format: :binary],
        profile
      )
    )
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp handle({:ok, {{_version, status, _reason}, headers, response}})
       when status >= 200 and status < 300 do
    {:ok, to_string(response), headers}
  end

  defp handle({:ok, {{_version, status, _reason}, _headers, response}}) do
    {:error, error_of(to_string(response), status)}
  end

  defp handle({:error, reason}), do: {:error, stringify(reason)}

  defp error_of(raw, status) do
    case decode_json(raw) do
      {:ok, data} ->
        first_text(
          [get(data, "title", ""), get(data, "error", ""), get(data, "message", "")],
          "HTTP #{status}"
        )

      {:error, _reason} ->
        "HTTP #{status}"
    end
  end

  defp first_text(values, fallback) do
    case Enum.find(values, fn value -> is_binary(value) and value != "" end) do
      nil -> fallback
      text -> text
    end
  end

  defp decode_json(raw) do
    case YuurisanJSON.decode(raw) do
      {:ok, %{} = data} -> {:ok, data}
      _other -> {:error, "unreadable response"}
    end
  end

  defp decode_map(raw) do
    case decode_json(raw) do
      {:ok, data} -> data
      {:error, _reason} -> %{}
    end
  end

  defp session_header(""), do: []
  defp session_header(sess), do: [{~c"cookie", to_charlist("PHPSESSID=" <> sess)}]

  defp session_of(headers) do
    Enum.find_value(headers, "", fn {name, value} ->
      if String.downcase(to_string(name)) == "set-cookie" do
        case Regex.run(~r/PHPSESSID=([^;]+)/, to_string(value)) do
          [_all, token] -> token
          _other -> nil
        end
      end
    end)
  end

  defp game_slugs(html) do
    slugs =
      ~r/transition\('([^']+)'\)/
      |> Regex.scan(html)
      |> Enum.map(fn [_all, slug] -> slug end)
      |> Enum.reject(fn slug ->
        slug in ["tasks", "friends", "addTask", "earnings", "wallet", "games"]
      end)
      |> Enum.uniq()

    if slugs == [], do: ["wheel", "treasury", "raiders"], else: slugs
  end

  defp game_label("wheel"), do: "Spin Wheel"
  defp game_label("treasury"), do: "Treasury"
  defp game_label("raiders"), do: "Raiders"
  defp game_label(_slug), do: "Game"

  defp span_number(html, id) do
    case Regex.run(~r/id="#{id}">([^<]*)</, html) do
      [_all, value] -> to_number(value)
      _other -> 0
    end
  end

  defp to_number(value) do
    text = value |> String.trim() |> String.replace(",", "")

    case Integer.parse(text) do
      {number, _rest} ->
        number

      :error ->
        case Float.parse(text) do
          {number, _rest} -> trunc(number)
          :error -> 0
        end
    end
  end

  defp nonce, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp init_data_of(line) do
    value =
      line
      |> String.trim()
      |> String.trim_leading("\"")
      |> String.trim_trailing("\"")
      |> extract_init_data()

    if value == "" do
      :error
    else
      try do
        case URI.decode_query(value) do
          %{"user" => raw} ->
            case YuurisanJSON.decode(raw) do
              {:ok, %{"id" => _id} = profile} -> {:ok, value, profile}
              _other -> :error
            end

          _other ->
            :error
        end
      rescue
        _error -> :error
      end
    end
  end

  defp extract_init_data(value) do
    if String.contains?(value, "tgWebAppData=") do
      value
      |> String.split("tgWebAppData=")
      |> List.last()
      |> String.split("&tgWebApp")
      |> List.first()
      |> URI.decode_www_form()
    else
      value
      |> String.trim_leading("?")
      |> String.trim_leading("#")
      |> String.split("&tgUplineId=")
      |> List.first()
    end
  end

  defp proxy_setup(nil), do: {:default, []}

  defp proxy_setup(line) do
    case parse_proxy(line) do
      {host, port, user, pass} -> proxy_profile(host, port, user, pass)
      {host, port} -> proxy_profile(host, port, "", "")
      nil -> {:default, []}
    end
  end

  defp proxy_profile(host, port, user, pass) do
    name = String.to_atom("proxy_#{host}_#{port}")
    address = {String.to_charlist(host), port}

    case :inets.start(:httpc, profile: name) do
      {:ok, _pid} ->
        :httpc.set_options([proxy: {address, []}, https_proxy: {address, []}], name)

      {:error, {:already_started, _pid}} ->
        :ok

      _other ->
        :ok
    end

    case user do
      "" -> {name, []}
      _ -> {name, [proxy_auth: {String.to_charlist(user), String.to_charlist(pass)}]}
    end
  end

  defp parse_proxy(line) do
    value =
      line
      |> String.trim()
      |> String.replace_prefix("http://", "")
      |> String.replace_prefix("https://", "")
      |> String.replace_prefix("socks5://", "")

    case String.split(value, "@") do
      [credentials, host_part] ->
        case String.split(credentials, ":") do
          [user, pass] -> with_host_port(host_part, user, pass)
          _other -> with_host_port(host_part, "", "")
        end

      [host_part] ->
        case String.split(host_part, ":") do
          [host, port] -> with_port(host, port)
          [host, port, user, pass] -> with_port_creds(host, port, user, pass)
          _other -> nil
        end
    end
  end

  defp with_host_port(host_part, user, pass) do
    case String.split(host_part, ":") do
      [host, port] -> with_port_creds(host, port, user, pass)
      _other -> nil
    end
  end

  defp with_port(host, port) do
    case Integer.parse(port) do
      {number, ""} -> {host, number}
      _other -> nil
    end
  end

  defp with_port_creds(host, port, user, pass) do
    case Integer.parse(port) do
      {number, ""} -> {host, number, user, pass}
      _other -> nil
    end
  end

  defp mask_proxy(line) do
    case parse_proxy(line) do
      {host, port, _user, _pass} -> "http://user:pass@#{mask_host(host)}:#{port}"
      {host, port} -> "http://user:pass@#{mask_host(host)}:#{port}"
      nil -> "http://user:pass@***:***"
    end
  end

  defp mask_host(host) do
    parts = String.split(host, ".")

    case parts do
      [a, _b, _c, d] ->
        "#{a}*****#{d}"

      _other ->
        if String.length(host) > 4 do
          String.slice(host, 0, 2) <> "*****" <> String.slice(host, -2, 2)
        else
          "***"
        end
    end
  end

  defp proxy_for([], _index), do: nil
  defp proxy_for(proxies, index), do: Enum.at(proxies, rem(index, length(proxies)))

  defp load_lines(name) do
    case File.read(Path.join(__DIR__, name)) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:error, _reason} ->
        []
    end
  end

  defp load_settings do
    case File.read(Path.join(__DIR__, "config.json")) do
      {:ok, content} ->
        case YuurisanJSON.decode(content) do
          {:ok, %{"settings" => settings}} when is_map(settings) -> settings
          _other -> %{}
        end

      {:error, _reason} ->
        %{}
    end
  end

  defp sleep_seconds(settings), do: whole(get(settings, "sleep_seconds", 3600), 3600)

  defp install_signal_handler do
    handler = fn ->
      IO.write("\n" <> @red <> @bold <> "Script stopped by user" <> @reset <> "\n")
      System.halt(0)
    end

    for signal <- [:sigterm, :sighup, :sigquit] do
      try do
        System.trap_signal(signal, handler)
      rescue
        _error -> :ok
      end
    end
  end

  defp clean_text(value, fallback) do
    text =
      value
      |> stringify()
      |> String.replace(
        ["[", "]", "|", "#", "!", "@", "$", "%", "^", "&", "*", "(", ")", "-"],
        " "
      )

    case String.split(text) |> Enum.join(" ") do
      "" -> fallback
      cleaned -> cleaned
    end
  end

  defp short_reason(reason), do: shorten(clean_text(reason, "reason"), "reason", 26)

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_integer(value), do: Integer.to_string(value)
  defp stringify(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp stringify({:failed_connect, _reason}), do: "no network connection"
  defp stringify({:failed_connect, _reason, _host}), do: "no network connection"
  defp stringify({:timeout, _reason}), do: "the request timed out"
  defp stringify(value), do: inspect(value)

  defp get(map, key, default) when is_map(map), do: Map.get(map, key, default)
  defp get(_other, _key, default), do: default

  defp whole(value, _fallback) when is_integer(value), do: value
  defp whole(value, _fallback) when is_float(value), do: trunc(value)
  defp whole(_value, fallback), do: fallback

  defp money(value) do
    value |> stringify() |> String.replace(",", "") |> shorten("0", 9)
  end

  defp count(value) do
    value |> stringify() |> shorten("0", 8)
  end

  defp shorten(value, fallback, limit) do
    text = value |> to_string() |> String.trim()

    case String.slice(text, 0, limit) do
      "" -> fallback
      short -> String.trim(short)
    end
  end

  defp fit(text) do
    value = to_string(text)
    if String.length(value) <= @width, do: value, else: String.slice(value, 0, @width)
  end

  defp countdown(seconds, label) do
    left = max(trunc(seconds), 0)

    if left >= 1 do
      width = frame(label, left, 0)
      tick(left, label, width)
    end
  end

  defp tick(0, _label, width) do
    IO.write("\r" <> String.duplicate(" ", width) <> "\r")
  end

  defp tick(left, label, width) do
    width = frame(label, left, width)
    :timer.sleep(1000)
    tick(left - 1, label, width)
  end

  defp frame(label, left, width) do
    text = label <> " " <> format_duration(left)
    IO.write("\r" <> @yellow <> @bold <> text <> @reset)
    max(width, String.length(text))
  end

  defp format_duration(total) do
    days = div(total, 86_400)
    hours = div(rem(total, 86_400), 3600)
    minutes = div(rem(total, 3600), 60)
    seconds = rem(total, 60)

    if days > 0 do
      pad(days) <> ":" <> pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    else
      pad(hours) <> ":" <> pad(minutes) <> ":" <> pad(seconds)
    end
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")

  defp green(message), do: IO.puts(@green <> @bold <> fit(message) <> @reset)
  defp yellow(message), do: IO.puts(@yellow <> @bold <> fit(message) <> @reset)
  defp red(message), do: IO.puts(@red <> @bold <> fit(message) <> @reset)
end

MBuxBot.run()
