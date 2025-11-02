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
      
    <!-- Form wraps EVERYTHING -->
      <.form for={@form} id="post-form" phx-target={@myself} phx-change="validate" phx-submit="save">
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
                <input
                  type="hidden"
                  name="post[featured_image]"
                  value={@form[:featured_image].value}
                />
              </div>
    <!-- Author (NOW INSIDE FORM) -->
              <div class="bg-white rounded-[16px] p-6 border border-[#E7E8F1]">
                <h3 class="text-sm font-haas_medium_65 text-[#141414] mb-4">Author</h3>

                <%= if @current_user && @current_user.is_admin do %>
                  <!-- Admin: Autocomplete dropdown -->
                  <div class="relative">
                    <.input
                      field={@form[:author_name]}
                      type="text"
                      placeholder="Start typing author name..."
                      phx-change="search_authors"
                      phx-target={@myself}
                      autocomplete="off"
                      class="w-full bg-white text-[#141414] placeholder:text-[#14141466] border-[#E7E8F1] focus:border-[#8AE388] focus:ring focus:ring-[#8AE38833] rounded-lg px-4 py-2 text-sm"
                      error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
                    />
                    <%= if assigns[:filtered_authors] && length(@filtered_authors) > 0 && assigns[:show_author_dropdown] do %>
                      <div class="absolute z-10 w-full mt-1 bg-white border border-[#E7E8F1] rounded-lg shadow-lg max-h-48 overflow-y-auto">
                        <%= for author <- @filtered_authors do %>
                          <button
                            type="button"
                            phx-click="select_author"
                            phx-value-username={author.username}
                            phx-target={@myself}
                            class="w-full text-left px-4 py-2 hover:bg-[#F3F5FF] text-sm text-[#141414] transition-colors"
                          >
                            {author.username}
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% else %>
                  <!-- Normal author: Read-only field -->
                  <div class="w-full bg-gray-50 text-[#141414] border border-[#E7E8F1] rounded-lg px-4 py-2 text-sm">
                    <%= @form[:author_name].value || @current_user.username || "Not set" %>
                  </div>
                  <input type="hidden" name="post[author_name]" value={@form[:author_name].value || @current_user.username} />
                <% end %>
              </div>

    <!-- Tags -->
              <div class="bg-white rounded-[16px] p-6 border border-[#E7E8F1]">
                <h3 class="text-sm font-haas_medium_65 text-[#141414] mb-4">Tags</h3>

                <!-- Selected Tags Section -->
                <%= if length(@selected_tags || []) > 0 do %>
                  <div class="mb-4">
                    <p class="text-xs text-[#141414A3] mb-2 font-haas_medium_65">Selected Tags</p>
                    <div class="flex flex-wrap gap-2 p-3 bg-[#F7F8FA] rounded-lg border border-[#E7E8F1]">
                      <%= for tag <- (@selected_tags || []) do %>
                        <button
                          type="button"
                          phx-click="remove_tag"
                          phx-value-tag={tag}
                          phx-target={@myself}
                          class="inline-flex items-center gap-1 px-3 py-1.5 bg-gradient-to-b from-[#8AE388] to-[#BAF55F] text-[#141414] rounded-full text-xs font-haas_medium_65 hover:shadow-md transition-all"
                        >
                          <%= tag %>
                          <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                            <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                          </svg>
                        </button>
                      <% end %>
                    </div>
                  </div>
                <% end %>

                <!-- Search Tags Section -->
                <div class="mb-4">
                  <p class="text-xs text-[#141414A3] mb-2 font-haas_medium_65">Search Tags (type and press Enter to create new)</p>
                  <div class="relative">
                    <input
                      type="text"
                      id="tag-search-input"
                      phx-hook="TagInput"
                      phx-keyup="search_tags"
                      phx-target={@myself}
                      phx-debounce="300"
                      data-component-id={@myself}
                      placeholder="Search or create tag..."
                      value={@tag_search || ""}
                      class="w-full px-4 py-2 border border-[#E7E8F1] rounded-lg text-sm focus:border-[#8AE388] focus:ring focus:ring-[#8AE38833] outline-none"
                      autocomplete="off"
                    />
                  </div>
                </div>

                <!-- Available Tags Section -->
                <div>
                  <p class="text-xs text-[#141414A3] mb-2 font-haas_medium_65">Available Tags</p>
                  <div class="flex flex-wrap gap-2 max-h-[400px] overflow-y-auto p-2">
                    <%= for tag <- @filtered_tags do %>
                      <%= unless tag in (@selected_tags || []) do %>
                        <button
                          type="button"
                          phx-click="add_tag"
                          phx-value-tag={tag}
                          phx-target={@myself}
                          class="px-3 py-1.5 bg-white border border-[#E7E8F1] text-[#141414] rounded-full text-xs font-haas_medium_65 hover:bg-[#F3F5FF] hover:border-[#8AE388] transition-all"
                        >
                          <%= tag %>
                        </button>
                      <% end %>
                    <% end %>
                  </div>
                </div>

                <!-- Hidden input to store tags as JSON -->
                <input type="hidden" name="post[tags]" value={Jason.encode!(@selected_tags || [])} />
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

              <div class="space-y-6">
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
                    SEO Description
                    <span class="text-[#141414A3] font-haas_roman_55 ml-2">0/100</span>
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
                    options={@category_options}
                    class="w-full bg-white text-[#141414] border-[#E7E8F1] focus:border-[#8AE388] focus:ring focus:ring-[#8AE38833] rounded-lg px-4 py-3 font-haas_roman_55"
                    error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
                  />
                </div>

    <!-- Custom Published Date (Admin Only) -->
                <%= if @current_user && @current_user.is_admin do %>
                  <div>
                    <label class="block text-sm font-haas_medium_65 text-[#141414] mb-2">
                      Custom Published Date <span class="text-[#8AE388]">(Admin Only)</span>
                    </label>
                    <.input
                      field={@form[:custom_published_at]}
                      type="datetime-local"
                      class="w-full bg-white text-[#141414] border-[#E7E8F1] focus:border-[#8AE388] focus:ring focus:ring-[#8AE38833] rounded-lg px-4 py-3 font-haas_roman_55"
                      error_class="border-red-400 focus:border-red-500 focus:ring focus:ring-red-300"
                    />
                    <p class="text-xs text-[#141414A3] mt-1">Leave empty to use current date when publishing. Set a date in the past to backdate the article.</p>
                  </div>
                <% end %>

    <!-- Quill Editor -->
                <div>
                  <label class="block text-sm font-haas_medium_65 text-[#141414] mb-2">
                    Content
                  </label>
                  <div
                    id="quill-editor"
                    phx-update="ignore"
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
                        if @form[:content].value,
                          do: Jason.encode!(@form[:content].value),
                          else: "{}"
                      }
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    post = Map.get(assigns, :post, %Blog.Post{})

    # Auto-populate author_name with username for new posts
    post = if !post.id && !post.author_name && assigns[:current_user] do
      %{post | author_name: assigns.current_user.username}
    else
      post
    end

    changeset = Blog.change_post(post)

    # Load all tags from database
    available_tags = Blog.list_tags() |> Enum.map(& &1.name)

    # Load existing tags for this post if editing
    selected_tags =
      if post.id do
        post.tags |> Enum.map(& &1.name)
      else
        []
      end

    # Load all categories from database
    categories = Blog.list_categories()
    category_options = [{"Select a category", ""}] ++ Enum.map(categories, &{&1.name, &1.name})

    # Initialize author autocomplete state
    authors = Map.get(assigns, :authors, [])
    filtered_authors = authors
    show_author_dropdown = false

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_tags, selected_tags)
     |> assign(:available_tags, available_tags)
     |> assign(:filtered_tags, available_tags)
     |> assign(:tag_search, "")
     |> assign(:category_options, category_options)
     |> assign(:filtered_authors, filtered_authors)
     |> assign(:show_author_dropdown, show_author_dropdown)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"post" => post_params}, socket) do
    post_params =
      post_params
      |> parse_content()
      |> parse_custom_published_at()

    # Preserve featured_image if not present in params (e.g., during tag changes)
    post_params =
      if is_nil(post_params["featured_image"]) || post_params["featured_image"] == "" do
        current_featured_image = socket.assigns.post.featured_image
        if current_featured_image do
          Map.put(post_params, "featured_image", current_featured_image)
        else
          post_params
        end
      else
        post_params
      end

    # Auto-generate slug from title if title exists and slug is empty
    post_params =
      if post_params["title"] && post_params["title"] != "" &&
           (is_nil(post_params["slug"]) or post_params["slug"] == "") do
        slug =
          post_params["title"]
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        Map.put(post_params, "slug", slug)
      else
        post_params
      end

    changeset =
      socket.assigns.post
      |> Blog.change_post(post_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"post" => post_params}, socket) do
    # Parse content and custom published date
    post_params =
      post_params
      |> parse_content()
      |> parse_custom_published_at()

    # Auto-generate slug from title if title exists and slug is empty
    post_params =
      if post_params["title"] && post_params["title"] != "" &&
           (is_nil(post_params["slug"]) or post_params["slug"] == "") do
        slug =
          post_params["title"]
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        Map.put(post_params, "slug", slug)
      else
        post_params
      end

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

  def handle_event("search_tags", %{"value" => search_term}, socket) do
    filtered_tags =
      if String.trim(search_term) == "" do
        socket.assigns.available_tags
      else
        socket.assigns.available_tags
        |> Enum.filter(fn tag ->
          String.downcase(tag) =~ String.downcase(search_term)
        end)
      end

    {:noreply,
     socket
     |> assign(:tag_search, search_term)
     |> assign(:filtered_tags, filtered_tags)}
  end

  def handle_event("add_tag_from_input", %{"value" => tag_value}, socket) do
    tag = String.trim(tag_value)

    if tag != "" && tag not in socket.assigns.selected_tags do
      selected_tags = socket.assigns.selected_tags ++ [tag]

      # Create tag in database if it doesn't exist
      available_tags =
        if tag not in socket.assigns.available_tags do
          case Blog.get_or_create_tag(tag) do
            {:ok, _tag_record} ->
              socket.assigns.available_tags ++ [tag]

            {:error, _changeset} ->
              socket.assigns.available_tags
          end
        else
          socket.assigns.available_tags
        end

      {:noreply,
       socket
       |> assign(:selected_tags, selected_tags)
       |> assign(:available_tags, available_tags)
       |> assign(:filtered_tags, available_tags)
       |> assign(:tag_search, "")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_tag", %{"tag" => tag}, socket) do
    if tag not in socket.assigns.selected_tags do
      selected_tags = socket.assigns.selected_tags ++ [tag]
      {:noreply, assign(socket, :selected_tags, selected_tags)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_tag", %{"tag" => tag}, socket) do
    selected_tags = Enum.reject(socket.assigns.selected_tags, &(&1 == tag))
    {:noreply, assign(socket, :selected_tags, selected_tags)}
  end

  @impl true
  def handle_event("search_authors", %{"post" => %{"author_name" => search_term}}, socket) do
    authors = socket.assigns[:authors] || []

    filtered_authors = if String.trim(search_term) == "" do
      authors
    else
      Enum.filter(authors, fn author ->
        String.contains?(String.downcase(author.username), String.downcase(search_term))
      end)
    end

    show_dropdown = String.trim(search_term) != "" && length(filtered_authors) > 0

    {:noreply, assign(socket, filtered_authors: filtered_authors, show_author_dropdown: show_dropdown)}
  end

  @impl true
  def handle_event("select_author", %{"username" => username}, socket) do
    # Update the form with the selected username
    changeset =
      socket.assigns.form.source
      |> Ecto.Changeset.put_change(:author_name, username)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:show_author_dropdown, false)
     |> assign_form(changeset)}
  end

  defp save_post(socket, :edit, post_params) do
    IO.inspect(post_params, label: "Updating post with params")

    # Extract and decode tags if present
    tags =
      case post_params["tags"] do
        tags_json when is_binary(tags_json) ->
          case Jason.decode(tags_json) do
            {:ok, decoded_tags} -> decoded_tags
            {:error, _} -> []
          end

        tags_list when is_list(tags_list) ->
          tags_list

        _ ->
          []
      end

    # Remove tags from post_params since we'll handle it separately
    post_params = Map.delete(post_params, "tags")

    case Blog.update_post(socket.assigns.post, post_params) do
      {:ok, post} ->
        # Update tags after updating post
        Blog.update_post_tags(post, tags)

        notify_parent({:saved, post})

        {:noreply,
         socket
         |> put_flash(:info, "Post updated successfully")
         |> push_navigate(to: ~p"/#{post.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        IO.inspect(changeset.errors, label: "Post update validation errors")
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_post(socket, :new, post_params) do
    IO.inspect(post_params, label: "Creating new post with params")

    # Extract and decode tags if present
    tags =
      case post_params["tags"] do
        tags_json when is_binary(tags_json) ->
          case Jason.decode(tags_json) do
            {:ok, decoded_tags} -> decoded_tags
            {:error, _} -> []
          end

        tags_list when is_list(tags_list) ->
          tags_list

        _ ->
          []
      end

    # Remove tags from post_params since we'll handle it separately
    post_params = Map.delete(post_params, "tags")

    case Blog.create_post(post_params) do
      {:ok, post} ->
        # Update tags after creating post
        Blog.update_post_tags(post, tags)

        notify_parent({:saved, post})

        {:noreply,
         socket
         |> put_flash(:info, "Post created successfully")
         |> push_navigate(to: ~p"/#{post.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        IO.inspect(changeset.errors, label: "Post creation validation errors")
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

  # Parse custom_published_at from datetime-local input format to UTC DateTime
  defp parse_custom_published_at(%{"custom_published_at" => datetime_str} = params)
       when is_binary(datetime_str) and datetime_str != "" do
    case NaiveDateTime.from_iso8601(datetime_str) do
      {:ok, naive_dt} ->
        # Convert NaiveDateTime to UTC DateTime
        utc_datetime = DateTime.from_naive!(naive_dt, "Etc/UTC")
        Map.put(params, "custom_published_at", utc_datetime)

      {:error, _} ->
        params
    end
  end

  defp parse_custom_published_at(params), do: params

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
