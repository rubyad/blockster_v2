defmodule BlocksterV2Web.PostLive.FormComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.Blog

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-6 py-12">
      <div class="bg-gradient-to-br from-purple-900/50 to-blue-900/50 rounded-2xl p-8 border border-white/10">
        <h2 class="text-3xl font-bold text-white mb-8">
          {@title}
        </h2>

        <.form
          for={@form}
          id="post-form"
          phx-target={@myself}
          phx-submit="save"
          class="space-y-6"
        >
          <!-- Title Input -->
          <div>
            <label class="block text-sm font-semibold text-purple-300 mb-2">
              Title
            </label>
            <.input
              field={@form[:title]}
              type="text"
              placeholder="Enter your post title..."
              class="w-full bg-white/10 text-white placeholder:text-gray-400 border-white/20 focus:border-purple-400 focus:ring focus:ring-purple-300 focus:ring-opacity-50 rounded-lg px-4 py-3 text-lg"
              error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
            />
          </div>
          
    <!-- Featured Image Upload -->
          <div>
            <label class="block text-sm font-semibold text-purple-300 mb-2">
              Featured Image
            </label>
            <%= if @form[:featured_image].value do %>
              <div class="mb-3">
                <img
                  src={@form[:featured_image].value}
                  alt="Featured image preview"
                  class="w-full max-w-md h-48 object-cover rounded-lg border border-white/20"
                />
                <button
                  type="button"
                  phx-click="remove_featured_image"
                  phx-target={@myself}
                  phx-submit="save"
                  class="mt-2 text-sm text-red-400 hover:text-red-300 transition-colors"
                >
                  Remove image
                </button>
              </div>
            <% end %>
            <div class="flex gap-3">
              <input
                type="file"
                id="featured-image-input"
                accept="image/*"
                phx-hook="FeaturedImageUpload"
                data-target={@myself}
                class="hidden"
              />
              <button
                type="button"
                onclick="document.getElementById('featured-image-input').click()"
                class="px-4 py-2 bg-purple-500/20 text-purple-300 rounded-lg font-semibold hover:bg-purple-500/30 transition-all border border-purple-500/30"
              >
                <.icon name="hero-photo" class="w-5 h-5 inline mr-2" />
                {if @form[:featured_image].value, do: "Change Image", else: "Upload Image"}
              </button>
              <input type="hidden" name="post[featured_image]" value={@form[:featured_image].value} />
            </div>
            <p class="mt-2 text-xs text-gray-400">
              Upload a featured image for your post (max 5MB)
            </p>
          </div>
          
    <!-- Author Name Input -->
          <div>
            <label class="block text-sm font-semibold text-purple-300 mb-2">
              Author Name
            </label>
            <.input
              field={@form[:author_name]}
              type="text"
              placeholder="Your name..."
              class="w-full bg-white/10 text-white placeholder:text-gray-400 border-white/20 focus:border-purple-400 focus:ring focus:ring-purple-300 focus:ring-opacity-50 rounded-lg px-4 py-3"
              error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
            />
          </div>
          
    <!-- Category Input -->
          <div>
            <label class="block text-sm font-semibold text-purple-300 mb-2">
              Category
            </label>
            <.input
              field={@form[:category]}
              type="select"
              options={[
                {"Select a category", ""},
                {"Blockchain", "Blockchain"},
                {"Trading", "Trading"},
                {"Gaming", "Gaming"},
                {"Events", "Events"},
                {"News", "News"}
              ]}
              class="w-full bg-white/10 text-white border-white/20 focus:border-purple-400 focus:ring focus:ring-purple-300 focus:ring-opacity-50 rounded-lg px-4 py-3"
              error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
            />
          </div>
          
    <!-- Excerpt Input -->
          <div>
            <label class="block text-sm font-semibold text-purple-300 mb-2">
              Excerpt (optional)
            </label>
            <.input
              field={@form[:excerpt]}
              type="textarea"
              placeholder="A brief summary of your post..."
              class="w-full bg-white/10 text-white placeholder:text-gray-400 border-white/20 focus:border-purple-400 focus:ring focus:ring-purple-300 focus:ring-opacity-50 rounded-lg px-4 py-3 min-h-[100px]"
              error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
            />
          </div>
          
    <!-- Quill Editor -->
          <div>
            <label class="block text-sm font-semibold text-purple-300 mb-2">
              Content
            </label>
            <div
              id="quill-editor"
              phx-hook="QuillEditor"
              data-content={
                if @form[:content].value, do: Jason.encode!(@form[:content].value), else: "{}"
              }
              class="bg-white rounded-lg text-gray-900"
            >
              <div class="editor-container" style="min-height: 400px;"></div>
              <input
                type="hidden"
                name="post[content]"
                value={if @form[:content].value, do: Jason.encode!(@form[:content].value), else: "{}"}
              />
            </div>
            <p class="mt-2 text-xs text-gray-400">
              Use the toolbar to format your text and add images from S3
            </p>
          </div>
          
    <!-- Action Buttons -->
          <div class="flex items-center justify-between gap-4 pt-4">
            <.link
              navigate={~p"/"}
              class="px-6 py-3 bg-gray-500/20 text-gray-300 rounded-lg font-semibold hover:bg-gray-500/30 transition-all border border-gray-500/30"
            >
              Cancel
            </.link>

            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-8 py-3 bg-gradient-to-r from-purple-500 to-pink-500 text-white rounded-lg font-semibold hover:shadow-lg hover:shadow-purple-500/50 transition-all"
            >
              {if @action == :edit, do: "Update Post", else: "Create Post"}
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{post: post} = assigns, socket) do
    changeset = Blog.change_post(post)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"post" => post_params}, socket) do
    # Parse content if it's a JSON string
    post_params = parse_content(post_params)

    changeset =
      socket.assigns.post
      |> Blog.change_post(post_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"post" => post_params}, socket) do
    # Parse content if it's a JSON string
    post_params = parse_content(post_params)

    save_post(socket, socket.assigns.action, post_params)
  end

  def handle_event("remove_featured_image", _params, socket) do
    changeset =
      socket.assigns.post
      |> Blog.change_post(%{featured_image: nil})
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("set_featured_image", %{"url" => url}, socket) do
    changeset =
      socket.assigns.post
      |> Blog.change_post(%{featured_image: url})
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  defp save_post(socket, :edit, post_params) do
    case Blog.update_post(socket.assigns.post, post_params) do
      {:ok, post} ->
        notify_parent({:saved, post})

        {:noreply,
         socket
         |> put_flash(:info, "Post updated successfully")
         |> push_navigate(to: ~p"/posts/#{post}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_post(socket, :new, post_params) do
    case Blog.create_post(post_params) do
      {:ok, post} ->
        notify_parent({:saved, post})

        {:noreply,
         socket
         |> put_flash(:info, "Post created successfully")
         |> push_navigate(to: ~p"/posts/#{post}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp parse_content(%{"content" => content} = params) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> Map.put(params, "content", decoded)
      {:error, _} -> params
    end
  end

  defp parse_content(params), do: params
end
