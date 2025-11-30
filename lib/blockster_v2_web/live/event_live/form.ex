defmodule BlocksterV2Web.EventLive.Form do
  use BlocksterV2Web, :live_view

  import Ecto.Query

  alias BlocksterV2.Events
  alias BlocksterV2.Events.Event
  alias BlocksterV2.Blog
  alias BlocksterV2.Repo

  @impl true
  def mount(params, _session, socket) do
    # Check if user is admin
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      event =
        case params do
          %{"id" => id} ->
            Events.get_event!(id)
            |> Repo.preload([:organizer, :hub, :tags])

          _ ->
            %Event{status: "draft"}
        end

      changeset = Events.change_event(event)
      form = to_form(changeset)
      hubs = Blog.list_hubs()
      tags = Blog.list_tags()
      authors = get_all_authors()

      {:ok,
       socket
       |> assign(:event, event)
       |> assign(:form, form)
       |> assign(:hubs, hubs)
       |> assign(:tags, tags)
       |> assign(:authors, authors)
       |> assign(:page_title, page_title(socket.assigns.live_action))
       |> assign(:selected_tag_ids, get_selected_tag_ids(event))}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be an admin to access this page.")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Event")
    |> assign(:event, %Event{status: "draft"})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    event = Events.get_event!(id) |> Repo.preload([:organizer, :hub, :tags])

    socket
    |> assign(:page_title, "Edit Event")
    |> assign(:event, event)
    |> assign(:selected_tag_ids, get_selected_tag_ids(event))
  end

  @impl true
  def handle_event("validate", %{"event" => event_params}, socket) do
    changeset =
      socket.assigns.event
      |> Events.change_event(event_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"event" => event_params}, socket) do
    # Extract tag IDs from params
    tag_ids =
      case event_params["tag_ids"] do
        nil ->
          []

        tag_ids_map when is_map(tag_ids_map) ->
          tag_ids_map
          |> Map.values()
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&String.to_integer/1)

        _ ->
          []
      end

    # Remove tag_ids from event_params as it's not a field on the Event schema
    event_params = Map.delete(event_params, "tag_ids")

    save_event(socket, socket.assigns.live_action, event_params, tag_ids)
  end

  @impl true
  def handle_event("toggle_tag", %{"tag-id" => tag_id}, socket) do
    tag_id = String.to_integer(tag_id)
    selected_tag_ids = socket.assigns.selected_tag_ids

    new_selected_tag_ids =
      if tag_id in selected_tag_ids do
        List.delete(selected_tag_ids, tag_id)
      else
        [tag_id | selected_tag_ids]
      end

    {:noreply, assign(socket, :selected_tag_ids, new_selected_tag_ids)}
  end

  defp save_event(socket, :edit, event_params, tag_ids) do
    case Events.update_event(socket.assigns.event, event_params) do
      {:ok, event} ->
        # Update tags
        tags = Repo.all(from(t in BlocksterV2.Blog.Tag, where: t.id in ^tag_ids))

        event
        |> Repo.preload(:tags)
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:tags, tags)
        |> Repo.update!()

        {:noreply,
         socket
         |> put_flash(:info, "Event updated successfully")
         |> push_navigate(to: ~p"/admin/events")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_event(socket, :new, event_params, tag_ids) do
    # Set organizer_id to current user if not provided
    event_params =
      if event_params["organizer_id"] == "" || is_nil(event_params["organizer_id"]) do
        Map.put(event_params, "organizer_id", socket.assigns.current_user.id)
      else
        event_params
      end

    case Events.create_event(event_params) do
      {:ok, event} ->
        # Update tags
        tags = Repo.all(from(t in BlocksterV2.Blog.Tag, where: t.id in ^tag_ids))

        event
        |> Repo.preload(:tags)
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:tags, tags)
        |> Repo.update!()

        {:noreply,
         socket
         |> put_flash(:info, "Event created successfully")
         |> push_navigate(to: ~p"/admin/events")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp page_title(:new), do: "New Event"
  defp page_title(:edit), do: "Edit Event"

  defp get_all_authors do
    alias BlocksterV2.Accounts.User
    import Ecto.Query

    from(u in User,
      where: u.is_author == true or u.is_admin == true,
      select: %{id: u.id, name: u.username, email: u.email},
      order_by: [asc: u.username]
    )
    |> Repo.all()
  end

  defp get_selected_tag_ids(%Event{tags: tags}) when is_list(tags) do
    Enum.map(tags, & &1.id)
  end

  defp get_selected_tag_ids(_), do: []
end
