defmodule BlocksterV2.Notifications.EmailBuilder do
  @moduledoc """
  Builds notification emails using a shared base layout.
  Each template returns a Swoosh.Email struct ready for delivery.
  """

  import Swoosh.Email

  @from_address {"Blockster", "notifications@blockster.com"}
  @brand_color "#CAFC00"
  @logo_url "https://ik.imagekit.io/blockster/Blockster-logo-white.png"
  @base_url "https://blockster-v2.fly.dev"

  # ============ Public API ============

  @doc """
  Single article notification email.
  data: %{title, body, image_url, slug, hub_name}
  """
  def single_article(to_email, to_name, unsubscribe_token, data) do
    title = data[:title] || "New Article"
    body = data[:body] || ""
    image_url = data[:image_url]
    slug = data[:slug] || "/"
    hub_name = data[:hub_name]

    subject = if hub_name, do: "New in #{hub_name}: #{title}", else: title

    article_url = "#{@base_url}/#{slug}"

    hero_html =
      if image_url do
        ~s(<a href="#{article_url}" style="text-decoration:none;"><img src="#{image_url}" alt="#{title}" style="width:100%;max-height:300px;object-fit:cover;border-radius:8px;margin-bottom:16px;display:block;" /></a>)
      else
        ""
      end

    html_content = """
    #{hero_html}
    <a href="#{article_url}" style="text-decoration:none;">
      <h2 style="color:#141414;font-size:22px;margin:0 0 8px;">#{escape(title)}</h2>
    </a>
    #{if hub_name, do: ~s(<p style="color:#888;font-size:13px;margin:0 0 12px;">From #{escape(hub_name)}</p>), else: ""}
    <a href="#{article_url}" style="text-decoration:none;">
      <p style="color:#555;font-size:15px;line-height:1.6;margin:0 0 24px;">#{escape(body)}</p>
    </a>
    #{cta_button("Read Article", article_url)}
    """

    text_content = """
    #{title}
    #{if hub_name, do: "From #{hub_name}\n", else: ""}
    #{body}

    Read the full article: #{article_url}
    """

    build_email(to_email, to_name, subject, html_content, text_content, unsubscribe_token)
  end

  @doc """
  Daily digest email with multiple articles.
  data: %{articles: [%{title, body, slug, image_url, hub_name}], date: Date}
  """
  def daily_digest(to_email, to_name, unsubscribe_token, data) do
    articles = data[:articles] || []
    date = data[:date] || Date.utc_today()
    date_str = Calendar.strftime(date, "%B %d, %Y")

    subject = "Your Daily Digest — #{date_str}"

    articles_html =
      Enum.map_join(articles, "\n", fn article ->
        url = "#{@base_url}/#{article[:slug] || "/"}"

        img =
          if article[:image_url] do
            ~s(<img src="#{article[:image_url]}" alt="" width="100" height="100" style="width:100px;height:100px;object-fit:cover;border-radius:8px;display:block;" />)
          else
            ~s(<div style="width:100px;height:100px;background:#{@brand_color};border-radius:8px;"></div>)
          end

        excerpt_html =
          if article[:excerpt] do
            ~s(<p style="color:#666;font-size:13px;margin:4px 0 0;line-height:1.4;">#{escape(article[:excerpt])}</p>)
          else
            ""
          end

        hub_html =
          if article[:hub_name] do
            ~s(<p style="color:#888;font-size:12px;margin:4px 0 0;">#{escape(article[:hub_name])}</p>)
          else
            ""
          end

        ~s"""
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="border-bottom:1px solid #f0f0f0;">
          <tr>
            <td style="padding:12px 0;width:100px;vertical-align:top;">
              <a href="#{url}" style="text-decoration:none;">#{img}</a>
            </td>
            <td style="padding:12px 0 12px 14px;vertical-align:top;">
              <a href="#{url}" style="color:#141414;font-size:15px;font-weight:600;text-decoration:none;">#{escape(article[:title] || "")}</a>
              #{excerpt_html}
              #{hub_html}
            </td>
          </tr>
        </table>
        """
      end)

    html_content = """
    <h2 style="color:#141414;font-size:22px;margin:0 0 4px;">Your Daily Digest</h2>
    <p style="color:#888;font-size:13px;margin:0 0 20px;">#{date_str}</p>
    #{articles_html}
    <div style="margin-top:24px;">
      #{cta_button("Browse All Articles", @base_url)}
    </div>
    """

    articles_text =
      Enum.map_join(articles, "\n\n", fn a ->
        hub = if a[:hub_name], do: " (#{a[:hub_name]})", else: ""
        "- #{a[:title]}#{hub}\n  #{@base_url}/#{a[:slug] || "/"}"
      end)

    text_content = """
    Your Daily Digest — #{date_str}

    #{articles_text}

    Browse all articles: #{@base_url}
    """

    build_email(to_email, to_name, subject, html_content, text_content, unsubscribe_token)
  end

  @doc """
  Promotional/offer email.
  data: %{title, body, image_url, action_url, action_label, discount_code}
  """
  def promotional(to_email, to_name, unsubscribe_token, data) do
    title = data[:title] || "Special Offer"
    body = data[:body] || ""
    image_url = data[:image_url]
    action_url = data[:action_url] || "#{@base_url}/shop"
    action_label = data[:action_label] || "Shop Now"
    discount_code = data[:discount_code]

    subject = title

    hero =
      if image_url do
        ~s(<img src="#{image_url}" alt="#{title}" style="width:100%;max-height:350px;object-fit:cover;border-radius:8px;margin-bottom:16px;" />)
      else
        ""
      end

    discount_html =
      if discount_code do
        ~s(<div style="background:#f8f8f8;border:2px dashed #{@brand_color};border-radius:8px;padding:12px 16px;text-align:center;margin:16px 0;">
          <p style="color:#888;font-size:12px;margin:0;">Use code</p>
          <p style="color:#141414;font-size:20px;font-weight:700;margin:4px 0;letter-spacing:2px;">#{escape(discount_code)}</p>
        </div>)
      else
        ""
      end

    html_content = """
    #{hero}
    <h2 style="color:#141414;font-size:24px;margin:0 0 8px;">#{escape(title)}</h2>
    <div style="color:#555;font-size:15px;line-height:1.6;margin:0 0 16px;">#{body}</div>
    #{discount_html}
    #{cta_button(action_label, action_url)}
    """

    text_content = """
    #{title}

    #{body}
    #{if discount_code, do: "\nUse code: #{discount_code}\n", else: ""}
    #{action_label}: #{action_url}
    """

    build_email(to_email, to_name, subject, html_content, text_content, unsubscribe_token)
  end

  @doc """
  Referral prompt email.
  data: %{referral_link, bux_reward}
  """
  def referral_prompt(to_email, to_name, unsubscribe_token, data) do
    referral_link = data[:referral_link] || @base_url
    bux_reward = data[:bux_reward] || 500

    subject = "Invite friends, earn #{bux_reward} BUX each"

    html_content = """
    <h2 style="color:#141414;font-size:22px;margin:0 0 8px;">Share Blockster, Earn BUX</h2>
    <p style="color:#555;font-size:15px;line-height:1.6;margin:0 0 16px;">
      Invite your friends to Blockster and you'll both earn <strong>#{bux_reward} BUX</strong> when they sign up and start reading.
    </p>
    <div style="background:#f8f8f8;border-radius:8px;padding:12px 16px;margin:16px 0;">
      <p style="color:#888;font-size:12px;margin:0 0 4px;">Your referral link</p>
      <p style="color:#141414;font-size:14px;margin:0;word-break:break-all;">#{referral_link}</p>
    </div>
    #{cta_button("Share Your Link", referral_link)}
    """

    text_content = """
    Share Blockster, Earn BUX

    Invite your friends and you'll both earn #{bux_reward} BUX when they sign up.

    Your referral link: #{referral_link}
    """

    build_email(to_email, to_name, subject, html_content, text_content, unsubscribe_token)
  end

  @doc """
  Weekly reward summary email.
  data: %{total_bux_earned, articles_read, days_active, top_hub}
  """
  def weekly_reward_summary(to_email, to_name, unsubscribe_token, data) do
    total = data[:total_bux_earned] || 0
    articles = data[:articles_read] || 0
    days = data[:days_active] || 0
    top_hub = data[:top_hub]

    subject = "Your Week in Review — #{total} BUX Earned"

    top_hub_html =
      if top_hub do
        ~s(<div style="border-top:1px solid #f0f0f0;padding-top:12px;margin-top:12px;">
          <p style="color:#888;font-size:12px;margin:0;">Most active hub</p>
          <p style="color:#141414;font-size:15px;font-weight:600;margin:4px 0;">#{escape(top_hub)}</p>
        </div>)
      else
        ""
      end

    html_content = """
    <h2 style="color:#141414;font-size:22px;margin:0 0 16px;">Your Week in Review</h2>
    <div style="background:#f8f8f8;border-radius:12px;padding:20px;margin:0 0 20px;">
      <div style="text-align:center;margin-bottom:16px;">
        <p style="color:#888;font-size:13px;margin:0;">BUX Earned This Week</p>
        <p style="color:#141414;font-size:36px;font-weight:700;margin:4px 0;">#{total}</p>
      </div>
      <div style="display:flex;gap:16px;justify-content:center;">
        <div style="text-align:center;">
          <p style="color:#141414;font-size:20px;font-weight:600;margin:0;">#{articles}</p>
          <p style="color:#888;font-size:12px;margin:2px 0 0;">Articles Read</p>
        </div>
        <div style="text-align:center;">
          <p style="color:#141414;font-size:20px;font-weight:600;margin:0;">#{days}</p>
          <p style="color:#888;font-size:12px;margin:2px 0 0;">Days Active</p>
        </div>
      </div>
      #{top_hub_html}
    </div>
    #{cta_button("Keep Earning", @base_url)}
    """

    text_content = """
    Your Week in Review

    BUX Earned: #{total}
    Articles Read: #{articles}
    Days Active: #{days}
    #{if top_hub, do: "Most Active Hub: #{top_hub}", else: ""}

    Keep earning: #{@base_url}
    """

    build_email(to_email, to_name, subject, html_content, text_content, unsubscribe_token)
  end

  @doc """
  Welcome email for new users.
  data: %{username}
  """
  def welcome(to_email, to_name, unsubscribe_token, data) do
    username = data[:username] || to_name || "there"

    subject = "Welcome to Blockster!"

    html_content = """
    <h2 style="color:#141414;font-size:24px;margin:0 0 8px;">Welcome to Blockster, #{escape(username)}!</h2>
    <p style="color:#555;font-size:15px;line-height:1.6;margin:0 0 16px;">
      You're now part of Web3's daily content hub. Here's how to get started:
    </p>
    <div style="margin:20px 0;">
      <div style="display:flex;gap:12px;margin-bottom:16px;">
        <div style="width:32px;height:32px;background:#{@brand_color};border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
          <span style="font-weight:700;font-size:14px;">1</span>
        </div>
        <div>
          <p style="color:#141414;font-weight:600;margin:0;">Read articles to earn BUX</p>
          <p style="color:#888;font-size:13px;margin:4px 0 0;">The more you read, the more you earn.</p>
        </div>
      </div>
      <div style="display:flex;gap:12px;margin-bottom:16px;">
        <div style="width:32px;height:32px;background:#{@brand_color};border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
          <span style="font-weight:700;font-size:14px;">2</span>
        </div>
        <div>
          <p style="color:#141414;font-weight:600;margin:0;">Subscribe to hubs you love</p>
          <p style="color:#888;font-size:13px;margin:4px 0 0;">Follow hubs for personalized content in your feed.</p>
        </div>
      </div>
      <div style="display:flex;gap:12px;margin-bottom:16px;">
        <div style="width:32px;height:32px;background:#{@brand_color};border-radius:50%;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
          <span style="font-weight:700;font-size:14px;">3</span>
        </div>
        <div>
          <p style="color:#141414;font-weight:600;margin:0;">Redeem BUX in the shop</p>
          <p style="color:#888;font-size:13px;margin:4px 0 0;">Use your earned BUX for exclusive merch and deals.</p>
        </div>
      </div>
    </div>
    #{cta_button("Start Exploring", @base_url)}
    """

    text_content = """
    Welcome to Blockster, #{username}!

    Here's how to get started:

    1. Read articles to earn BUX — the more you read, the more you earn.
    2. Subscribe to hubs you love — follow hubs for personalized content.
    3. Redeem BUX in the shop — use your BUX for exclusive merch.

    Start exploring: #{@base_url}
    """

    build_email(to_email, to_name, subject, html_content, text_content, unsubscribe_token)
  end

  @doc """
  Re-engagement email for inactive users.
  data: %{days_inactive, articles: [%{title, slug}], special_offer}
  """
  def re_engagement(to_email, to_name, unsubscribe_token, data) do
    days = data[:days_inactive] || 7
    articles = data[:articles] || []
    special_offer = data[:special_offer]

    subject =
      cond do
        days >= 30 -> "Your hubs miss you — new content is waiting"
        days >= 14 -> "You've been gone a while — here's what you missed"
        days >= 7 -> "Your BUX are waiting"
        true -> "You have unread articles from your hubs"
      end

    articles_html =
      if articles != [] do
        items =
          Enum.map_join(articles, "\n", fn a ->
            url = "#{@base_url}/#{a[:slug] || "/"}"
            ~s(<li style="margin-bottom:8px;"><a href="#{url}" style="color:#141414;font-size:14px;text-decoration:none;font-weight:600;">#{escape(a[:title] || "")}</a></li>)
          end)

        ~s(<h3 style="color:#141414;font-size:16px;margin:16px 0 8px;">What you missed</h3><ul style="padding-left:20px;">#{items}</ul>)
      else
        ""
      end

    offer_html =
      if special_offer do
        ~s(<div style="background:#f3f4f6;border-radius:8px;padding:16px;text-align:center;margin:20px 0;">
          <p style="color:#141414;font-weight:600;font-size:15px;margin:0;">#{escape(special_offer)}</p>
        </div>)
      else
        ""
      end

    html_content = """
    <h2 style="color:#141414;font-size:22px;margin:0 0 8px;">#{escape(subject)}</h2>
    <p style="color:#555;font-size:15px;line-height:1.6;margin:0 0 16px;">
      It's been #{days} days since your last visit. There's plenty of new content waiting for you.
    </p>
    #{articles_html}
    #{offer_html}
    #{cta_button("Come Back", @base_url)}
    """

    articles_text =
      Enum.map_join(articles, "\n", fn a ->
        "- #{a[:title]}: #{@base_url}/#{a[:slug] || "/"}"
      end)

    text_content = """
    #{subject}

    It's been #{days} days since your last visit.

    #{if articles_text != "", do: "What you missed:\n#{articles_text}\n", else: ""}
    #{if special_offer, do: "Special offer: #{special_offer}\n", else: ""}
    Come back: #{@base_url}
    """

    build_email(to_email, to_name, subject, html_content, text_content, unsubscribe_token)
  end

  @doc """
  Order update email.
  data: %{order_number, status, tracking_url, items: [%{title, quantity}]}
  """
  def order_update(to_email, to_name, unsubscribe_token, data) do
    order_number = data[:order_number] || "N/A"
    status = data[:status] || "updated"
    tracking_url = data[:tracking_url]
    items = data[:items] || []

    {subject, status_message, status_color} =
      case status do
        "confirmed" ->
          {"Order ##{order_number} Confirmed", "Your order has been confirmed and is being prepared.", "#4CAF50"}

        "shipped" ->
          {"Order ##{order_number} Shipped!", "Your order is on its way.", "#2196F3"}

        "delivered" ->
          {"Order ##{order_number} Delivered", "Your order has been delivered. Enjoy!", "#4CAF50"}

        "cancelled" ->
          {"Order ##{order_number} Cancelled", "Your order has been cancelled.", "#F44336"}

        _ ->
          {"Order ##{order_number} Update", "Your order status has been updated.", "#888"}
      end

    items_html =
      if items != [] do
        rows =
          Enum.map_join(items, "\n", fn item ->
            ~s(<tr><td style="padding:8px 0;border-bottom:1px solid #f0f0f0;">#{escape(item[:title] || "")}</td><td style="padding:8px 0;border-bottom:1px solid #f0f0f0;text-align:right;">x#{item[:quantity] || 1}</td></tr>)
          end)

        ~s(<table style="width:100%;margin:16px 0;">#{rows}</table>)
      else
        ""
      end

    tracking_html =
      if tracking_url do
        ~s(<div style="margin:16px 0;">#{cta_button("Track Your Order", tracking_url)}</div>)
      else
        ""
      end

    html_content = """
    <div style="background:#{status_color};color:white;padding:8px 16px;border-radius:8px;display:inline-block;font-size:13px;font-weight:600;margin-bottom:16px;">
      #{String.upcase(to_string(status))}
    </div>
    <h2 style="color:#141414;font-size:22px;margin:0 0 8px;">Order ##{escape(order_number)}</h2>
    <p style="color:#555;font-size:15px;line-height:1.6;margin:0 0 16px;">#{escape(status_message)}</p>
    #{items_html}
    #{tracking_html}
    """

    items_text =
      Enum.map_join(items, "\n", fn item ->
        "- #{item[:title]} x#{item[:quantity] || 1}"
      end)

    text_content = """
    Order ##{order_number} — #{String.upcase(to_string(status))}

    #{status_message}

    #{if items_text != "", do: "Items:\n#{items_text}\n", else: ""}
    #{if tracking_url, do: "Track your order: #{tracking_url}", else: ""}
    """

    build_email(to_email, to_name, subject, html_content, text_content, unsubscribe_token)
  end

  # ============ Base Layout ============

  defp build_email(to_email, to_name, subject, html_content, text_content, unsubscribe_token) do
    unsubscribe_url = "#{@base_url}/unsubscribe/#{unsubscribe_token}"
    settings_url = "#{@base_url}/notifications/settings"

    new()
    |> to({to_name || to_email, to_email})
    |> from(@from_address)
    |> subject(subject)
    |> html_body(wrap_html_layout(html_content, unsubscribe_url, settings_url))
    |> text_body(wrap_text_layout(text_content, unsubscribe_url, settings_url))
    |> header("List-Unsubscribe", "<#{unsubscribe_url}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
  end

  defp wrap_html_layout(content, unsubscribe_url, settings_url) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <meta name="color-scheme" content="light dark" />
      <meta name="supported-color-schemes" content="light dark" />
      <title>Blockster</title>
      <style>
        @media (prefers-color-scheme: dark) {
          .email-bg { background-color: #1a1a1a !important; }
          .email-card { background-color: #2a2a2a !important; }
          .email-text { color: #e0e0e0 !important; }
          .email-subtext { color: #999 !important; }
        }
      </style>
    </head>
    <body style="margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background-color:#f5f5f5;" class="email-bg">
      <div style="max-width:600px;margin:0 auto;padding:20px;">
        <!-- Header -->
        <table width="100%" cellpadding="0" cellspacing="0" border="0">
          <tr>
            <td bgcolor="#141414" style="background-color:#141414;border-radius:12px 12px 0 0;padding:20px 24px;text-align:center;">
              <img src="#{@logo_url}" alt="Blockster" style="height:28px;" />
            </td>
          </tr>
        </table>
        <!-- Body -->
        <div style="background:#ffffff;padding:24px 24px 32px;border-radius:0 0 12px 12px;" class="email-card">
          #{content}
        </div>
        <!-- Footer -->
        <div style="padding:20px 24px;text-align:center;">
          <p style="color:#999;font-size:12px;margin:0 0 8px;">
            <a href="#{settings_url}" style="color:#999;text-decoration:underline;">Manage preferences</a>
            &nbsp;&middot;&nbsp;
            <a href="#{unsubscribe_url}" style="color:#999;text-decoration:underline;">Unsubscribe</a>
          </p>
          <p style="color:#bbb;font-size:11px;margin:0;">
            Blockster &middot; Web3's Daily Content Hub
          </p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp wrap_text_layout(content, unsubscribe_url, settings_url) do
    """
    #{content}

    ---
    Manage preferences: #{settings_url}
    Unsubscribe: #{unsubscribe_url}

    Blockster — Web3's Daily Content Hub
    """
  end

  # ============ Shared Helpers ============

  defp cta_button(label, url) do
    ~s(<div style="text-align:center;margin:24px 0;">
      <a href="#{url}" style="display:inline-block;background:#{@brand_color};color:#000;font-weight:700;font-size:15px;padding:12px 32px;border-radius:50px;text-decoration:none;">#{escape(label)}</a>
    </div>)
  end

  @doc false
  def escape(nil), do: ""
  def escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
  def escape(text), do: escape(to_string(text))
end
