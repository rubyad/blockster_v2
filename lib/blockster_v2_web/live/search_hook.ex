defmodule BlocksterV2Web.SearchHook do
  @moduledoc """
  LiveView on_mount hook to add search functionality to all LiveView pages.
  """
  import Phoenix.LiveView
  import Phoenix.Component
  alias BlocksterV2.Blog

  def on_mount(:default, _params, _session, socket) do
    IO.puts("🔍 SearchHook on_mount called!")

    socket =
      socket
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:show_search_results, false)
      |> attach_hook(:search_events, :handle_event, fn
        "search_posts", %{"value" => query}, socket ->
          IO.puts("🔍 SearchHook handling search_posts event")
          IO.inspect(query, label: "Query")

          results = if String.length(query) >= 2 do
            Blog.search_posts_fulltext(query, limit: 20)
          else
            []
          end

          IO.inspect(length(results), label: "Results count")
          IO.inspect(String.length(query) >= 2, label: "Show dropdown")

          {:halt,
           socket
           |> assign(:search_query, query)
           |> assign(:search_results, results)
           |> assign(:show_search_results, String.length(query) >= 2)}

        "close_search", _params, socket ->
          IO.puts("🔍 SearchHook handling close_search event")
          {:halt,
           socket
           |> assign(:search_query, "")
           |> assign(:search_results, [])
           |> assign(:show_search_results, false)}

        _event, _params, socket ->
          {:cont, socket}
      end)

    IO.puts("🔍 SearchHook attach_hook completed")
    {:cont, socket}
  end
end
