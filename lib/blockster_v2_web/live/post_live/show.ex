defmodule BlocksterV2Web.PostLive.Show do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog
  alias BlocksterV2.TimeTracker
  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.BuxMinter
  alias BlocksterV2.Social
  alias BlocksterV2Web.PostLive.TipTapRenderer

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug} = _params, _url, socket) do
    post = Blog.get_post_by_slug!(slug)

    # Unsubscribe from previous post if navigating between posts
    if socket.assigns[:post] do
      EngagementTracker.unsubscribe_from_post_bux(socket.assigns.post.id)
    end

    # Subscribe to BUX updates for this post
    EngagementTracker.subscribe_to_post_bux(post.id)

    # Increment view count
    # {:ok, updated_post} = Blog.increment_view_count(post)

    # Add bux_balance from Mnesia
    updated_post = Blog.with_bux_balances(post)

    # Get existing time spent for this user on this post
    user_id = get_user_id(socket)
    time_spent = safe_get_time(user_id, post.id)

    # Calculate word count for engagement tracking
    word_count = EngagementTracker.count_words(post.content)

    # Get existing engagement data if any
    engagement = safe_get_engagement(user_id, post.id)

    # Get user multiplier for BUX calculation
    user_multiplier = safe_get_user_multiplier(user_id)

    # Get existing rewards for this post
    rewards = safe_get_rewards(user_id, post.id)

    # Check if user already received read reward for this post
    {bux_earned, already_rewarded, read_tx_id} =
      case rewards do
        %{read_bux: read_bux, read_tx_id: tx_id} when is_number(read_bux) and read_bux > 0 ->
          {read_bux, true, tx_id}
        %{read_bux: read_bux} when is_number(read_bux) and read_bux > 0 ->
          {read_bux, true, nil}
        _ ->
          {nil, false, nil}
      end

    # Get base BUX reward for panel display
    base_bux_reward = updated_post.base_bux_reward || 1

    # Initial score/BUX always starts at 1 for fresh sessions (unless already rewarded)
    # Score builds up as user engages with the article
    {current_score, current_bux} =
      if already_rewarded do
        # Already rewarded - show final earned values
        {engagement && engagement.engagement_score || 10, bux_earned}
      else
        # Fresh session - always start at 1
        {1, EngagementTracker.calculate_bux_earned(1, base_bux_reward, user_multiplier)}
      end

    # Load X connection and share campaign for logged-in users
    {x_connection, share_campaign, share_reward} =
      case socket.assigns[:current_user] do
        nil ->
          {nil, nil, nil}

        current_user ->
          x_conn = Social.get_x_connection_for_user(current_user.id)
          campaign = Social.get_campaign_for_post(post.id)
          reward =
            if campaign do
              Social.get_share_reward(current_user.id, campaign.id)
            end

          {x_conn, campaign, reward}
      end

    {:noreply,
     socket
     |> assign(:page_title, post.title)
     |> assign(:post, updated_post)
     |> assign(:time_spent, time_spent)
     |> assign(:word_count, word_count)
     |> assign(:engagement, engagement)
     |> assign(:user_multiplier, user_multiplier)
     |> assign(:base_bux_reward, base_bux_reward)
     |> assign(:rewards, rewards)
     |> assign(:bux_earned, bux_earned)
     |> assign(:already_rewarded, already_rewarded)
     |> assign(:article_completed, already_rewarded)
     |> assign(:current_score, current_score)
     |> assign(:current_bux, current_bux)
     |> assign(:read_tx_id, read_tx_id)
     |> assign(:x_connection, x_connection)
     |> assign(:share_campaign, share_campaign)
     |> assign(:share_reward, share_reward)
     |> assign(:show_share_modal, false)
     |> assign(:share_status, nil)}
  end

  @impl true
  def handle_event("time_update", %{"seconds" => seconds}, socket) do
    user_id = get_user_id(socket)
    post_id = socket.assigns.post.id

    # Update the TimeTracker GenServer (fire and forget)
    # Client manages its own display incrementally - no need to push back
    # The initial time is loaded on page mount, JS adds to it locally
    TimeTracker.update_time(user_id, post_id, seconds)

    {:noreply, socket}
  end

  defp get_user_id(socket) do
    case socket.assigns[:current_user] do
      nil -> "anonymous"
      user -> user.id
    end
  end

  defp safe_get_time(user_id, post_id) do
    TimeTracker.get_time(user_id, post_id)
  catch
    :exit, _ -> 0
  end

  defp safe_get_engagement(user_id, post_id) do
    EngagementTracker.get_engagement_map(user_id, post_id)
  catch
    :exit, _ -> nil
  end

  defp safe_get_user_multiplier("anonymous"), do: 1
  defp safe_get_user_multiplier(user_id) do
    EngagementTracker.get_user_multiplier(user_id)
  catch
    :exit, _ -> 1
  end

  defp safe_get_rewards("anonymous", _post_id), do: nil
  defp safe_get_rewards(user_id, post_id) do
    EngagementTracker.get_rewards_map(user_id, post_id)
  catch
    :exit, _ -> nil
  end

  @impl true
  def handle_event("article-visited", %{"min_read_time" => min_read_time} = _params, socket) do
    user_id = get_user_id(socket)
    post_id = socket.assigns.post.id

    # Only track for logged-in users
    if user_id != "anonymous" do
      EngagementTracker.record_visit(user_id, post_id, min_read_time)
      # Refresh engagement data
      engagement = safe_get_engagement(user_id, post_id)
      {:noreply, assign(socket, :engagement, engagement)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("engagement-update", params, socket) do
    user_id = get_user_id(socket)
    post_id = socket.assigns.post.id

    # Only track for logged-in users who haven't already been rewarded
    if user_id != "anonymous" and not socket.assigns.already_rewarded do
      case EngagementTracker.update_engagement(user_id, post_id, params) do
        {:ok, score} ->
          # Only update socket if score actually changed
          if score != socket.assigns.current_score do
            # Calculate current BUX value
            base_bux_reward = socket.assigns.post.base_bux_reward || 1
            user_multiplier = socket.assigns.user_multiplier || 1
            current_bux = EngagementTracker.calculate_bux_earned(score, base_bux_reward, user_multiplier)

            # Refresh engagement data
            engagement = safe_get_engagement(user_id, post_id)

            {:noreply,
             socket
             |> assign(:engagement, engagement)
             |> assign(:current_score, score)
             |> assign(:current_bux, current_bux)}
          else
            {:noreply, socket}
          end

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("article-read", params, socket) do
    user_id = get_user_id(socket)
    post_id = socket.assigns.post.id

    # Only track for logged-in users
    if user_id != "anonymous" do
      # First record the engagement data
      case EngagementTracker.record_read(user_id, post_id, params) do
        {:ok, score} ->
          # Calculate BUX earned
          base_bux_reward = socket.assigns.post.base_bux_reward || 1
          user_multiplier = socket.assigns.user_multiplier || 1
          bux_earned = EngagementTracker.calculate_bux_earned(score, base_bux_reward, user_multiplier)

          # Try to record the read reward
          case EngagementTracker.record_read_reward(user_id, post_id, bux_earned) do
            {:ok, recorded_bux} ->
              # New reward recorded - mark article as completed
              engagement = safe_get_engagement(user_id, post_id)
              rewards = safe_get_rewards(user_id, post_id)

              # Mint BUX tokens to user's smart wallet (async with callback to update tx_id)
              if socket.assigns[:current_user] do
                wallet = socket.assigns.current_user.smart_wallet_address
                if wallet && wallet != "" do
                  lv_pid = self()
                  Task.start(fn ->
                    case BuxMinter.mint_bux(wallet, recorded_bux, user_id, post_id) do
                      {:ok, %{"transactionHash" => tx_hash}} ->
                        send(lv_pid, {:mint_completed, tx_hash})
                      _ ->
                        :ok
                    end
                  end)
                end
              end

              {:noreply,
               socket
               |> assign(:engagement, engagement)
               |> assign(:rewards, rewards)
               |> assign(:bux_earned, recorded_bux)
               |> assign(:already_rewarded, false)
               |> assign(:article_completed, true)
               |> assign(:current_score, score)
               |> assign(:current_bux, recorded_bux)
               |> assign(:read_tx_id, nil)}

            {:already_rewarded, existing_bux} ->
              # User already received reward for this article
              engagement = safe_get_engagement(user_id, post_id)
              rewards = safe_get_rewards(user_id, post_id)
              tx_id = rewards && Map.get(rewards, :read_tx_id)
              {:noreply,
               socket
               |> assign(:engagement, engagement)
               |> assign(:rewards, rewards)
               |> assign(:bux_earned, existing_bux)
               |> assign(:already_rewarded, true)
               |> assign(:article_completed, true)
               |> assign(:read_tx_id, tx_id)}

            {:error, _} ->
              {:noreply, socket}
          end

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:mint_completed, tx_hash}, socket) do
    {:noreply, assign(socket, :read_tx_id, tx_hash)}
  end

  @impl true
  def handle_info({:bux_update, post_id, new_balance}, socket) do
    # Only update if this is for the current post
    if socket.assigns.post.id == post_id do
      updated_post = Map.put(socket.assigns.post, :bux_balance, new_balance)
      {:noreply, assign(socket, :post, updated_post)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("publish", _params, socket) do
    {:ok, post} = Blog.publish_post(socket.assigns.post)

    {:noreply,
     socket
     |> put_flash(:info, "Post published successfully")
     |> assign(:post, post)}
  end

  @impl true
  def handle_event("unpublish", _params, socket) do
    {:ok, post} = Blog.unpublish_post(socket.assigns.post)

    {:noreply,
     socket
     |> put_flash(:info, "Post unpublished successfully")
     |> assign(:post, post)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:ok, _} = Blog.delete_post(socket.assigns.post)

    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("open_share_modal", _params, socket) do
    {:noreply, assign(socket, :show_share_modal, true)}
  end

  @impl true
  def handle_event("close_share_modal", _params, socket) do
    {:noreply, assign(socket, :show_share_modal, false)}
  end

  @impl true
  def handle_event("share_to_x", _params, socket) do
    user = socket.assigns.current_user
    x_connection = socket.assigns.x_connection
    share_campaign = socket.assigns.share_campaign

    cond do
      is_nil(user) ->
        {:noreply,
         socket
         |> assign(:share_status, {:error, "Please log in to share"})}

      is_nil(x_connection) ->
        {:noreply,
         socket
         |> assign(:share_status, {:error, "Please connect your X account first"})}

      is_nil(share_campaign) || !share_campaign.is_active ->
        # No active campaign, just open regular X share intent
        post = socket.assigns.post
        share_url = BlocksterV2Web.Endpoint.url() <> "/posts/#{post.slug}"
        share_text = URI.encode_www_form("#{post.title}")

        {:noreply,
         socket
         |> push_event("open_external_url", %{
           url: "https://twitter.com/intent/tweet?url=#{URI.encode_www_form(share_url)}&text=#{share_text}"
         })}

      socket.assigns.share_reward != nil ->
        # User already shared
        {:noreply,
         socket
         |> assign(:share_status, {:info, "You've already shared this article!"})}

      true ->
        # Active campaign - initiate tracked retweet
        initiate_tracked_share(socket, user, x_connection, share_campaign)
    end
  end

  defp initiate_tracked_share(socket, user, x_connection, share_campaign) do
    post = socket.assigns.post

    # Create pending reward
    case Social.create_pending_reward(user.id, share_campaign.id, x_connection.id) do
      {:ok, reward} ->
        # Get decrypted access token
        access_token = Social.XConnection.decrypt_access_token(x_connection)

        if access_token do
          # Retweet the campaign's specified tweet
          campaign_tweet_id = share_campaign.tweet_id
          x_user_id = x_connection.x_user_id

          # Retweet the campaign tweet via API
          case Social.XApiClient.create_retweet(access_token, x_user_id, campaign_tweet_id) do
            {:ok, _retweet_data} ->
              # Verify and record the tweet
              case Social.verify_share_reward(reward, campaign_tweet_id) do
                {:ok, verified_reward} ->
                  # Award BUX
                  bux_amount = share_campaign.bux_reward

                  # Update campaign share count
                  Social.increment_campaign_shares(share_campaign)

                  # Mint BUX to user's wallet
                  wallet = user.smart_wallet_address
                  if wallet && wallet != "" do
                    Task.start(fn ->
                      BuxMinter.mint_bux(wallet, bux_amount, user.id, post.id)
                    end)
                  end

                  {:ok, final_reward} = Social.mark_rewarded(verified_reward, bux_amount)

                  {:noreply,
                   socket
                   |> assign(:share_reward, final_reward)
                   |> assign(:share_status, {:success, "Shared! You earned #{bux_amount} BUX!"})
                   |> assign(:show_share_modal, false)}

                {:error, _} ->
                  {:noreply,
                   socket
                   |> assign(:share_status, {:error, "Failed to verify share"})}
              end

            {:error, reason} ->
              # Mark reward as failed
              Social.mark_failed(reward, "Tweet failed: #{reason}")

              {:noreply,
               socket
               |> assign(:share_status, {:error, "Failed to post tweet: #{reason}"})}
          end
        else
          Social.mark_failed(reward, "Token decryption failed")

          {:noreply,
           socket
           |> assign(:share_status, {:error, "Failed to authenticate with X. Please reconnect your account."})}
        end

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:share_status, {:error, "Failed to initiate share"})}
    end
  end

  # Handle TipTap format
  defp render_content(%{"type" => "doc"} = content) do
    TipTapRenderer.render_content(content)
  end

  # Fallback for empty or invalid content
  defp render_content(_), do: ""

  # Legacy Quill format handler (deprecated - kept for reference only)
  # All content should now be in TipTap format
  defp _render_legacy_quill_content(%{"ops" => ops}) when is_list(ops) do
    IO.puts("=== LEGACY QUILL FORMAT DETECTED ===")
    IO.inspect(ops, label: "OPS", limit: :infinity)

    html_parts =
      ops
      |> Enum.with_index()
      |> Enum.map(fn {op, index} ->
        next_op = Enum.at(ops, index + 1)
        result = render_single_op(op, next_op)
        IO.inspect({op, result}, label: "OP -> RESULT")
        result
      end)
      |> List.flatten()
      |> tap(fn parts -> IO.inspect(parts, label: "BEFORE REJECT", limit: :infinity) end)
      |> Enum.reject(fn x -> x == "" || x == nil end)
      |> tap(fn parts -> IO.inspect(parts, label: "AFTER REJECT", limit: :infinity) end)
      |> wrap_inline_paragraphs()
      |> Enum.join("\n")
      |> wrap_list_items() # Groups list items with formatted content

    Phoenix.HTML.raw(html_parts)
  end

  # Wrap consecutive inline text/formatted elements in paragraph tags
  defp wrap_inline_paragraphs(parts) do
    {result, current_para} = Enum.reduce(parts, {[], []}, fn part, {acc, para} ->
      cond do
        # If it's a block-level element (starts with known block tags), flush current paragraph
        String.starts_with?(part, ["<h1", "<h2", "<h3", "<h4", "<h5", "<h6", "<blockquote", "<ul", "<ol", "<div", "<img", "<p "]) ->
          if length(para) > 0 do
            # Wrap accumulated inline content in a paragraph
            wrapped = ~s(<p class="mt-4 mb-8 text-[#343434] leading-[1.6]">#{Enum.join(para, "")}</p>)
            {acc ++ [wrapped, part], []}
          else
            {acc ++ [part], []}
          end

        # Otherwise, accumulate inline content
        true ->
          {acc, para ++ [part]}
      end
    end)

    # Handle remaining accumulated inline content
    if length(current_para) > 0 do
      wrapped = ~s(<p class="mt-4 mb-8 text-[#343434] leading-[1.6]">#{Enum.join(current_para, "")}</p>)
      result ++ [wrapped]
    else
      result
    end
  end

  # Wrap consecutive list items in ul/ol tags and blockquote paragraphs in blockquote tags
  defp wrap_list_items(html) do
    html
    |> String.replace(
      ~r/<li class="[^"]*list-item-ordered">.*?<\/li>/s,
      fn match ->
        # Check if already wrapped
        if String.contains?(match, "<ol") do
          match
        else
          match
        end
      end
    )
    # Wrap bullet list items
    |> String.replace(
      ~r/(<li class="[^"]*list-item-bullet">.*?<\/li>)+/s,
      fn matches ->
        ~s(<ul class="list-disc pl-6 mb-4">#{matches}</ul>)
      end
    )
    # Wrap ordered list items
    |> String.replace(
      ~r/(<li class="[^"]*list-item-ordered">.*?<\/li>)+/s,
      fn matches ->
        ~s(<ol class="list-decimal pl-6 mb-4">#{matches}</ol>)
      end
    )
    # Wrap consecutive blockquote paragraphs in a single blockquote
    |> wrap_blockquotes()
  end

  # Wrap consecutive blockquote-line paragraphs
  defp wrap_blockquotes(html) do
    IO.puts("=== WRAP_BLOCKQUOTES CALLED ===")
    IO.inspect(String.contains?(html, "blockquote-line"), label: "Contains blockquote-line?")

    # Split HTML into lines and process sequentially
    lines = String.split(html, "\n")
    IO.inspect(length(lines), label: "Number of lines")

    {result, current_group} = Enum.reduce(lines, {[], []}, fn line, {acc, group} ->
      cond do
        # If line contains blockquote-line opening tag
        String.contains?(line, ~s(<p class="blockquote-line">)) ->
          {acc, [line | group]}

        # If we have accumulated blockquote lines and this isn't one, wrap them
        length(group) > 0 and not String.contains?(line, "blockquote-line") ->
          # Process the group - mark last paragraph as attribution
          reversed_group = Enum.reverse(group)
          cleaned_lines = reversed_group
          |> Enum.with_index()
          |> Enum.map(fn {l, idx} ->
            # Last item gets attribution class
            if idx == length(reversed_group) - 1 do
              String.replace(l, ~s(<p class="blockquote-line">), ~s(<p class="blockquote-attribution">))
            else
              String.replace(l, ~s(<p class="blockquote-line">), "<p>")
            end
          end)
          wrapped = ~s(<blockquote class="mt-4 mb-8">#{Enum.join(cleaned_lines, "\n")}</blockquote>)
          {acc ++ [wrapped, line], []}

        # Otherwise just accumulate
        true ->
          {acc ++ [line], group}
      end
    end)

    # Handle remaining group at end
    final_result = if length(current_group) > 0 do
      # Process the group - mark last paragraph as attribution
      reversed_group = Enum.reverse(current_group)
      cleaned_lines = reversed_group
      |> Enum.with_index()
      |> Enum.map(fn {l, idx} ->
        # Last item gets attribution class
        if idx == length(reversed_group) - 1 do
          String.replace(l, ~s(<p class="blockquote-line">), ~s(<p class="blockquote-attribution">))
        else
          String.replace(l, ~s(<p class="blockquote-line">), "<p>")
        end
      end)
      wrapped = ~s(<blockquote class="mt-4 mb-8">#{Enum.join(cleaned_lines, "\n")}</blockquote>)
      result ++ [wrapped]
    else
      result
    end

    Enum.join(final_result, "\n")
  end


  # Handle text that will be followed by a header newline
  defp render_single_op(
         %{"insert" => text},
         %{"insert" => "\n", "attributes" => %{"header" => level}}
       )
       when is_binary(text) do
    # Split the text by newlines
    lines = String.split(text, "\n")

    # All lines except the last are regular paragraphs
    paragraph_lines = Enum.drop(lines, -1)

    # The last line is the header text
    header_text = List.last(lines) |> String.trim()

    # Render paragraphs first (only non-empty ones)
    paragraphs =
      paragraph_lines
      |> Enum.map(fn para ->
        trimmed = String.trim(para)

        if trimmed != "" do
          ~s(<p class="mb-4 text-[#343434] leading-[1.6]">#{trimmed}</p>)
        else
          # Skip empty lines, margins provide spacing
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Render header with proper HTML tag and size
    size_class =
      case level do
        1 -> "text-4xl font-bold"
        2 -> "text-3xl font-bold"
        _ -> "text-2xl font-bold"
      end

    # Add mt-4 mb-8 spacing for h1 and h2 tags
    spacing_class =
      case level do
        1 -> "mt-4 mb-8"
        2 -> "mt-4 mb-8"
        _ -> "mb-4"
      end

    header_tag = "h#{level}"

    header_html =
      ~s(<#{header_tag} class="#{spacing_class} text-[#343434] leading-[1.2] #{size_class}">#{header_text}</#{header_tag}>)

    # Return paragraphs followed by header
    paragraphs ++ [header_html]
  end

  # Handle header newlines - just skip them, margins handle spacing
  defp render_single_op(%{"insert" => text, "attributes" => %{"header" => _}}, _next_op) when is_binary(text) do
    # Check if the text is ONLY newlines (no actual text content)
    if String.trim(text) == "" do
      # Skip newline-only header operations, margins provide spacing
      nil
    else
      # Has actual text content, should be handled by the header+text handler above
      nil
    end
  end

  # Handle blockquote text - mark it as blockquote paragraph, wrapping happens later
  defp render_single_op(
         %{"insert" => text},
         %{"insert" => "\n", "attributes" => %{"blockquote" => true}}
       )
       when is_binary(text) do
    IO.inspect(text, label: "BLOCKQUOTE TEXT")

    # Check if text contains a double newline (paragraph separator)
    # If so, only render paragraphs AFTER the first double newline as blockquote
    # This handles Quill's behavior of including preceding text in blockquote
    result = if String.contains?(text, "\n\n") do
      # Split by double newline to separate paragraphs
      paragraphs = String.split(text, "\n\n")
      IO.inspect(paragraphs, label: "SPLIT PARAGRAPHS")

      # First paragraph(s) before the last one should be rendered as normal text
      # Only the last paragraph(s) should be blockquoted
      {non_blockquote_parts, blockquote_parts} = Enum.split(paragraphs, -1)

      # Render non-blockquote parts as regular paragraphs (skip empty ones)
      regular_html = non_blockquote_parts
      |> Enum.map(fn para ->
        trimmed = String.trim(para)
        if trimmed != "" do
          ~s(<p>#{trimmed}</p>)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

      # Render blockquote parts with blockquote-line class (skip empty lines)
      blockquote_html = blockquote_parts
      |> Enum.flat_map(fn para -> String.split(para, "\n") end)
      |> Enum.map(fn line ->
        trimmed = String.trim(line)
        if trimmed != "" do
          ~s(<p class="blockquote-line">#{trimmed}</p>)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

      # Combine regular and blockquote HTML
      [regular_html, blockquote_html]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    else
      # No double newline - render all as blockquote (skip empty lines)
      lines = String.split(text, "\n")

      lines
      |> Enum.map(fn line ->
        trimmed = String.trim(line)
        if trimmed != "" do
          ~s(<p class="blockquote-line">#{trimmed}</p>)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
    end

    IO.inspect(result, label: "BLOCKQUOTE RESULT")
    result
  end

  # Detect if a line is an attribution (e.g., "John Doe, CEO at Company")
  defp is_attribution?(text) do
    # Pattern: Name, Title at Company or Name, Title
    # Look for patterns like ", CEO at", ", CTO at", etc.
    String.match?(text, ~r/^[^,]+,\s+[A-Z][^,]+ at .+$/) or
    # Also match simpler pattern: just "Name, Position"
    String.match?(text, ~r/^[^,]+,\s+[A-Z][^,]+$/)
  end

  # Skip blockquote newlines (they're processed above)
  defp render_single_op(%{"insert" => "\n", "attributes" => %{"blockquote" => true}}, _next_op) do
    nil
  end

  # Handle list item text (ordered or bullet)
  defp render_single_op(
         %{"insert" => text},
         %{"insert" => "\n", "attributes" => %{"list" => list_type}}
       )
       when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed != "" do
      ~s(<li class="mb-2 text-[#343434] leading-[1.6] list-item-#{list_type}">#{trimmed}</li>)
    else
      ""
    end
  end

  # Skip list newlines (they're processed above)
  defp render_single_op(%{"insert" => "\n", "attributes" => %{"list" => _}}, _next_op) do
    nil
  end

  # Handle text with inline formatting attributes (bold, italic, underline, strike, link)
  # This MUST come before the plain text handler to match more specific patterns first
  defp render_single_op(%{"insert" => text, "attributes" => attrs}, _next_op)
       when is_binary(text) and is_map(attrs) do
    # Don't process if this is a block-level attribute (header, blockquote, list)
    # Those are handled by their specific handlers above
    if Map.has_key?(attrs, "header") or Map.has_key?(attrs, "blockquote") or
         Map.has_key?(attrs, "list") do
      nil
    else
      # Just apply inline formatting without wrapping in <p> tags
      # The wrapping happens later when we join ops together
      content = text

      content =
        if attrs["bold"] do
          ~s(<strong>#{content}</strong>)
        else
          content
        end

      content =
        if attrs["italic"] do
          ~s(<em>#{content}</em>)
        else
          content
        end

      content =
        if attrs["underline"] do
          ~s(<u>#{content}</u>)
        else
          content
        end

      content =
        if attrs["strike"] do
          ~s(<s>#{content}</s>)
        else
          content
        end

      content =
        if attrs["link"] do
          url = attrs["link"]
          ~s(<a href="#{url}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">#{content}</a>)
        else
          content
        end

      content
    end
  end

  # Handle regular text without any formatting
  defp render_single_op(%{"insert" => text}, _next_op) when is_binary(text) do
    # Split by double newlines (paragraph breaks) to preserve paragraph structure
    # Single newlines within paragraphs are ignored
    text
    |> String.split("\n\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn para ->
      # Reject empty strings and separator-only strings like "--"
      para == "" || String.match?(para, ~r/^[-\s]+$/)
    end)
    |> Enum.map(fn para ->
      ~s(<p class="mt-4 mb-8 text-[#343434] leading-[1.6]">#{para}</p>)
    end)
  end

  # Handle images
  defp render_single_op(%{"insert" => %{"image" => url}}, _next_op) do
    ~s(<img src="#{url}" class="max-w-full h-auto rounded-lg my-4" />)
  end

  # Handle spacer embeds
  defp render_single_op(%{"insert" => %{"spacer" => _}}, _next_op) do
    ~s(<div class="text-left text-[#343434] my-4 text-2xl">--</div>)
  end

  # Handle tweet embeds with embedded HTML
  defp render_single_op(%{"insert" => %{"tweet" => %{"html" => html}}}, _next_op) do
    ~s{<div class="my-6">#{html}<script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script></div>}
  end

  # Handle tweet embeds using Twitter's oEmbed API (legacy format with URL)
  defp render_single_op(%{"insert" => %{"tweet" => %{"url" => url}}}, _next_op) do
    # Fetch tweet HTML from Twitter's oEmbed API
    case fetch_tweet_embed(url) do
      {:ok, html} ->
        # Wrap in container for styling
        ~s(<div class="my-6">#{html}</div>)

      {:error, _reason} ->
        # Fallback to simple link if oEmbed fails
        ~s(<p class="my-4"><a href="#{url}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">View Tweet on Twitter</a></p>)
    end
  end

  # Handle tweet embeds with just a URL string (backward compatibility)
  defp render_single_op(%{"insert" => %{"tweet" => url}}, _next_op) when is_binary(url) do
    # Fetch tweet HTML from Twitter's oEmbed API
    case fetch_tweet_embed(url) do
      {:ok, html} ->
        # Wrap in container for styling
        ~s(<div class="my-6">#{html}</div>)

      {:error, _reason} ->
        # Fallback to simple link if oEmbed fails
        ~s(<p class="my-4"><a href="#{url}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">View Tweet on Twitter</a></p>)
    end
  end

  # Handle plain newlines (blank lines) - just skip them, margins handle spacing
  defp render_single_op(%{"insert" => "\n"}, _next_op) do
    nil
  end

  # Catch-all for unknown ops
  defp render_single_op(_op, _next_op), do: nil

  # Fetch tweet embed HTML from Twitter's oEmbed API
  defp fetch_tweet_embed(url) do
    # Twitter's oEmbed endpoint
    oembed_url =
      "https://publish.twitter.com/oembed?url=#{URI.encode_www_form(url)}&theme=light&dnt=true"

    case Req.get(oembed_url) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        # Extract HTML from oEmbed response
        case Map.get(body, "html") do
          html when is_binary(html) ->
            {:ok, html}

          _ ->
            {:error, :invalid_response}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, error}
  end

  # Helper functions for engagement display

  defp format_time(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 ->
        mins = div(seconds, 60)
        secs = rem(seconds, 60)
        "#{mins}m #{secs}s"
      true ->
        hours = div(seconds, 3600)
        mins = div(rem(seconds, 3600), 60)
        "#{hours}h #{mins}m"
    end
  end
  defp format_time(_), do: "0s"

  defp engagement_score_color(score) when is_integer(score) do
    cond do
      score >= 8 -> "bg-green-100 text-green-800 border-2 border-green-300"
      score >= 6 -> "bg-blue-100 text-blue-800 border-2 border-blue-300"
      score >= 4 -> "bg-yellow-100 text-yellow-800 border-2 border-yellow-300"
      true -> "bg-red-100 text-red-800 border-2 border-red-300"
    end
  end
  defp engagement_score_color(_), do: "bg-gray-100 text-gray-800 border-2 border-gray-300"

  defp engagement_score_label(score) when is_integer(score) do
    cond do
      score >= 9 -> "Excellent Reader"
      score >= 7 -> "Good Reader"
      score >= 5 -> "Moderate Engagement"
      score >= 3 -> "Light Skimmer"
      true -> "Quick Glance"
    end
  end
  defp engagement_score_label(_), do: "Not Rated"
end
