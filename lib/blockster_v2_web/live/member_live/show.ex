defmodule BlocksterV2Web.MemberLive.Show do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :active_tab, "following")}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _url, socket) do
    case Accounts.get_user_by_slug(slug) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Member not found")
         |> push_navigate(to: ~p"/")}

      member ->
        {:noreply,
         socket
         |> assign(:page_title, member.username || "Member")
         |> assign(:member, member)}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end
end
