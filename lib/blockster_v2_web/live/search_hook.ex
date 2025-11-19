defmodule BlocksterV2Web.SearchHook do
  @moduledoc """
  LiveView on_mount hook to add search functionality to all LiveView pages.
  """
  import Phoenix.LiveView
  import Phoenix.Component
  alias BlocksterV2.Blog

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_search_results, false)
     |> attach_hook(:handle_search_events, :handle_event, &handle_search_event/3)}
  end

  defp handle_search_event("search_posts", %{"value" => query}, socket) do
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
  end

  defp handle_search_event("close_search", _params, socket) do
    {:halt,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_search_results, false)}
  end

  defp handle_search_event(_event, _params, socket) do
    {:cont, socket}
  end
end
