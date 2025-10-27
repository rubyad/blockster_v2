defmodule BlocksterV2Web.PostLive.FormComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.Blog

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#F7F8FA]">
      <!-- Header matching reference -->
      <div class="main-header-banner pt-24 lg:pt-0 pb-5 lg:mt-0 px-6 lg:pl-11 lg:pr-7 fixed top-0 left-0 right-0 w-full z-50 bg-white border-b border-[#E7E8F1]">
        <header class="pt-6 flex items-center justify-between gap-4">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/"} class="text-[#101D36] font-haas_medium_65 text-sm">
              Cancel
            </.link>
          </div>

          <div class="flex items-center gap-3">
            <button
              type="submit"
              form="post-form"
              phx-disable-with="Publishing..."
              class="px-6 py-2 bg-gradient-to-b from-[#8AE388] to-[#BAF55F] text-[#141414] rounded-full font-haas_medium_65 text-sm hover:shadow-lg transition-all"
            >
              {if @action == :edit, do: "Update Article", else: "Publish Article"}
            </button>
            <button
              type="button"
              class="px-6 py-2 bg-white border border-[#E7E8F1] text-[#141414] rounded-full font-haas_medium_65 text-sm hover:bg-gray-50 transition-all"
            >
              Save as Drafts
            </button>
            <button
              type="button"
              class="px-6 py-2 bg-white border border-[#E7E8F1] text-[#141414] rounded-full font-haas_medium_65 text-sm hover:bg-gray-50 transition-all"
            >
              Preview
            </button>
          </div>
        </header>
      </div>
      
    <!-- Main Content Area -->
      <div class="container mx-auto flex gap-8 pt-32 px-6 max-w-[1400px]">
        <!-- Left Sidebar -->
        <div class="w-[320px] shrink-0">
          <div class="sticky top-32 space-y-6">
            <!-- Business Account Card -->
            <div class="bg-white rounded-[16px] p-6 border border-[#E7E8F1]">
              <h3 class="text-sm font-haas_medium_65 text-[#141414] mb-4">Business Account</h3>
              <div class="flex items-center gap-3 mb-4">
                <div class="w-12 h-12 bg-gradient-to-br from-purple-500 to-blue-500 rounded-full flex items-center justify-center text-white font-bold">
                  M
                </div>
                <div>
                  <p class="text-sm font-haas_medium_65 text-[#141414]">Moonpay</p>
                </div>
              </div>

              <div class="mb-4">
                <p class="text-xs text-[#141414A3] mb-2">Total Balance</p>
                <div class="flex items-baseline gap-1">
                  <span class="text-2xl font-haas_medium_65 text-[#141414]">20,264</span>
                  <span class="text-sm text-[#141414A3]">/ 40,000</span>
                </div>
              </div>

              <div class="mb-4">
                <label class="block text-xs text-[#141414A3] mb-2">Add $BUX to Article</label>
                <input
                  type="number"
                  placeholder="0"
                  class="w-full px-4 py-2 border border-[#E7E8F1] rounded-lg text-sm"
                />
              </div>
            </div>
            
    <!-- Featured Image -->
            <div class="bg-white rounded-[16px] p-6 border border-[#E7E8F1]">
              <%= if @form[:featured_image].value do %>
                <div class="mb-3">
                  <img
                    src={@form[:featured_image].value}
                    alt="Article cover"
                    class="w-full h-48 object-cover rounded-lg border border-[#E7E8F1]"
                  />
                  <button
                    type="button"
                    phx-click="remove_featured_image"
                    phx-target={@myself}
                    class="mt-2 text-sm text-red-400 hover:text-red-300 transition-colors"
                  >
                    Remove image
                  </button>
                </div>
              <% end %>

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
                phx-click={JS.dispatch("click", to: "#featured-image-input")}
                phx-target={@myself}
                class="w-full px-4 py-3 bg-[#F3F5FF] text-[#141414] rounded-lg font-haas_medium_65 text-sm hover:bg-[#E7E8F1] transition-all border border-[#E7E8F1] flex items-center justify-center gap-2"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  width="20"
                  height="20"
                  viewBox="0 0 20 20"
                  fill="none"
                >
                  <path
                    d="M17 13V17H3V13H1V17C1 18.1 1.9 19 3 19H17C18.1 19 19 18.1 19 17V13H17ZM16 9L14.59 7.59L11 11.17V1H9V11.17L5.41 7.59L4 9L10 15L16 9Z"
                    fill="#141414"
                  />
                </svg>
                {if @form[:featured_image].value, do: "Change Cover", else: "Add Article Cover"}
              </button>
              <input type="hidden" name="post[featured_image]" value={@form[:featured_image].value} />
            </div>
            
    <!-- Categories -->
            <div class="bg-white rounded-[16px] p-6 border border-[#E7E8F1]">
              <h3 class="text-sm font-haas_medium_65 text-[#141414] mb-4">categories</h3>
              <div class="space-y-2">
                <label class="flex items-center gap-2 cursor-pointer">
                  <input type="checkbox" class="checkbox checkbox-sm" />
                  <span class="text-sm text-[#141414]">People</span>
                </label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input type="checkbox" class="checkbox checkbox-sm" />
                  <span class="text-sm text-[#141414]">Fashion</span>
                </label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input type="checkbox" class="checkbox checkbox-sm" />
                  <span class="text-sm text-[#141414]">Art</span>
                </label>
                <label class="flex items-center gap-2 cursor-pointer">
                  <input type="checkbox" class="checkbox checkbox-sm" />
                  <span class="text-sm text-[#141414]">Music</span>
                </label>
              </div>
            </div>
            
    <!-- Author -->
            <div class="bg-white rounded-[16px] p-6 border border-[#E7E8F1]">
              <h3 class="text-sm font-haas_medium_65 text-[#141414] mb-4">Author</h3>
              <.input
                field={@form[:author_name]}
                type="text"
                placeholder="Author name..."
                class="w-full bg-white text-[#141414] placeholder:text-[#14141466] border-[#E7E8F1] focus:border-[#8AE388] focus:ring focus:ring-[#8AE38833] rounded-lg px-4 py-2 text-sm"
                error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
              />
            </div>
            
    <!-- Tags -->
            <div class="bg-white rounded-[16px] p-6 border border-[#E7E8F1]">
              <h3 class="text-sm font-haas_medium_65 text-[#141414] mb-4">tags</h3>
              <div class="flex flex-wrap gap-2">
                <span class="px-3 py-1 bg-[#F3F5FF] text-[#141414] rounded-full text-xs font-haas_medium_65">
                  Ethereum
                </span>
                <span class="px-3 py-1 bg-[#F3F5FF] text-[#141414] rounded-full text-xs font-haas_medium_65">
                  NFT
                </span>
                <span class="px-3 py-1 bg-[#F3F5FF] text-[#141414] rounded-full text-xs font-haas_medium_65">
                  Solana
                </span>
                <span class="px-3 py-1 bg-[#F3F5FF] text-[#141414] rounded-full text-xs font-haas_medium_65">
                  Interview
                </span>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Right Content Area -->
        <div class="flex-1 max-w-[800px]">
          <div class="bg-white rounded-[16px] p-8 border border-[#E7E8F1]">
            <.link
              navigate={~p"/"}
              class="inline-flex items-center gap-2 text-[#141414A3] hover:text-[#141414] mb-6 text-sm font-haas_medium_65"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="16"
                height="16"
                viewBox="0 0 16 16"
                fill="none"
              >
                <path
                  d="M10 12L6 8L10 4"
                  stroke="currentColor"
                  stroke-width="1.5"
                  stroke-linecap="square"
                />
              </svg>
              Back
            </.link>

            <h1 class="text-[32px] font-haas_medium_65 text-[#141414] mb-8">New Post</h1>

            <.form for={@form} id="post-form" phx-target={@myself} phx-submit="save" class="space-y-6">
              <!-- Title -->
              <div>
                <label class="block text-sm font-haas_medium_65 text-[#141414] mb-2">
                  Title <span class="text-[#141414A3] font-haas_roman_55 ml-2">0/100</span>
                </label>
                <.input
                  field={@form[:title]}
                  type="text"
                  placeholder="Enter article title..."
                  class="w-full bg-white text-[#141414] placeholder:text-[#14141466] border-[#E7E8F1] focus:border-[#8AE388] focus:ring focus:ring-[#8AE38833] rounded-lg px-4 py-3 text-lg font-haas_roman_55"
                  error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
                />
              </div>
              
    <!-- SEO Description -->
              <div>
                <label class="block text-sm font-haas_medium_65 text-[#141414] mb-2">
                  SEO Description <span class="text-[#141414A3] font-haas_roman_55 ml-2">0/100</span>
                </label>
                <.input
                  field={@form[:excerpt]}
                  type="textarea"
                  placeholder="Brief description for SEO..."
                  class="w-full bg-white text-[#141414] placeholder:text-[#14141466] border-[#E7E8F1] focus:border-[#8AE388] focus:ring focus:ring-[#8AE38833] rounded-lg px-4 py-3 font-haas_roman_55 min-h-[100px]"
                  error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
                />
              </div>
              
    <!-- URL Slug -->
              <div>
                <label class="block text-sm font-haas_medium_65 text-[#141414] mb-2">
                  blocster.com/ <span class="text-[#141414A3] font-haas_roman_55 ml-2">0/100</span>
                </label>
                <.input
                  field={@form[:slug]}
                  type="text"
                  placeholder="article-url-slug"
                  class="w-full bg-white text-[#141414] placeholder:text-[#14141466] border-[#E7E8F1] focus:border-[#8AE388] focus:ring focus:ring-[#8AE38833] rounded-lg px-4 py-3 font-haas_roman_55"
                  error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
                />
              </div>
              
    <!-- Category Select -->
              <div>
                <label class="block text-sm font-haas_medium_65 text-[#141414] mb-2">
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
                  class="w-full bg-white text-[#141414] border-[#E7E8F1] focus:border-[#8AE388] focus:ring focus:ring-[#8AE38833] rounded-lg px-4 py-3 font-haas_roman_55"
                  error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
                />
              </div>
              
    <!-- Quill Editor -->
              <div>
                <label class="block text-sm font-haas_medium_65 text-[#141414] mb-2">
                  Content
                </label>
                <div
                  id="quill-editor"
                  phx-hook="QuillEditor"
                  data-content={
                    if @form[:content].value, do: Jason.encode!(@form[:content].value), else: "{}"
                  }
                  class="bg-white rounded-lg border border-[#E7E8F1]"
                >
                  <div class="editor-container" style="min-height: 400px;"></div>
                  <input
                    type="hidden"
                    name="post[content]"
                    value={
                      if @form[:content].value, do: Jason.encode!(@form[:content].value), else: "{}"
                    }
                  />
                </div>
              </div>
            </.form>
          </div>
        </div>
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
  def handle_event("save", %{"post" => post_params}, socket) do
    # Parse content if it's a JSON string
    post_params = parse_content(post_params)

    save_post(socket, socket.assigns.action, post_params)
  end

  def handle_event("remove_featured_image", _params, socket) do
    # Get current form data to preserve it
    current_data = get_current_form_data(socket.assigns.form)

    # Update only the featured_image field
    updated_data = Map.put(current_data, "featured_image", nil)

    changeset =
      socket.assigns.post
      |> Blog.change_post(updated_data)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("set_featured_image", %{"url" => url}, socket) do
    # Get current form data to preserve it
    current_data = get_current_form_data(socket.assigns.form)

    # Update only the featured_image field
    updated_data = Map.put(current_data, "featured_image", url)

    changeset =
      socket.assigns.post
      |> Blog.change_post(updated_data)

    {:noreply, assign_form(socket, changeset)}
  end

  defp save_post(socket, :edit, post_params) do
    case Blog.update_post(socket.assigns.post, post_params) do
      {:ok, post} ->
        notify_parent({:saved, post})

        {:noreply,
         socket
         |> put_flash(:info, "Post updated successfully")
         |> push_navigate(to: ~p"/posts/#{post.id}")}	1

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
         |> push_navigate(to: ~p"/posts/#{post.id}")}	1

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

  # Helper to extract current form data
  defp get_current_form_data(form) do
    %{
      "title" => form[:title].value || "",
      "author_name" => form[:author_name].value || "",
      "category" => form[:category].value || "",
      "excerpt" => form[:excerpt].value || "",
      "content" => form[:content].value || %{},
      "featured_image" => form[:featured_image].value,
      "slug" => form[:slug].value || ""
    }
  end
end
