defmodule BlocksterV2Web.SearchHook do
  @moduledoc """
  LiveView on_mount hook to add search functionality to all LiveView pages.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]
  alias BlocksterV2.Blog

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:show_search_results, false)
      |> attach_hook(:search_events, :handle_event, fn
        "search_posts", %{"value" => query}, socket ->
          results = if String.length(query) >= 2 do
            Blog.search_posts_fulltext(query, limit: 20)
          else
            []
          end

          {:halt,
           socket
           |> assign(:search_query, query)
           |> assign(:search_results, results)
           |> assign(:show_search_results, String.length(query) >= 2)}

        "close_search", _params, socket ->
          # Only update if search is currently shown to avoid unnecessary assigns
          if socket.assigns[:show_search_results] do
            {:halt,
             socket
             |> assign(:search_query, "")
             |> assign(:search_results, [])
             |> assign(:show_search_results, false)}
          else
            {:halt, socket}
          end

        _event, _params, socket ->
          {:cont, socket}
      end)

    {:cont, socket}
  end
end
