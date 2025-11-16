defmodule BlocksterV2Web.HubLive.FormComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.Blog

  @impl true
  def update(assigns, socket) do
    hub = Map.get(assigns, :hub, %Blog.Hub{})
    changeset = Blog.change_hub(hub)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"hub" => hub_params}, socket) do
    changeset =
      socket.assigns.hub
      |> Blog.change_hub(hub_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"hub" => hub_params}, socket) do
    save_hub(socket, socket.assigns.action, hub_params)
  end

  defp save_hub(socket, :edit, hub_params) do
    case Blog.update_hub(socket.assigns.hub, hub_params) do
      {:ok, hub} ->
        notify_parent({:saved, hub})

        {:noreply,
         socket
         |> put_flash(:info, "Hub updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_hub(socket, :new, hub_params) do
    case Blog.create_hub(hub_params) do
      {:ok, hub} ->
        notify_parent({:saved, hub})

        {:noreply,
         socket
         |> put_flash(:info, "Hub created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
