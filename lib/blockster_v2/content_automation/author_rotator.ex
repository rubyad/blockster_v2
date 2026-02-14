defmodule BlocksterV2.ContentAutomation.AuthorRotator do
  @moduledoc """
  Manages 8 author personas for automated content. Each persona has a distinct
  voice variation and covers specific content categories.

  Persona user accounts are created via `priv/repo/seeds/content_authors.exs`.
  The `user_id` field is populated at runtime by looking up the email in the DB.
  """

  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.User
  import Ecto.Query

  @personas [
    %{
      username: "jake_freeman",
      email: "jake@blockster.com",
      bio: "Bitcoin maximalist turned pragmatic crypto advocate. Former TradFi analyst.",
      style: "Data-driven, uses market analogies. Focuses on macro/trading/investment.",
      categories: [:trading, :macro_trends, :investment, :bitcoin]
    },
    %{
      username: "maya_chen",
      email: "maya@blockster.com",
      bio: "DeFi degen with a compliance background. Sees both sides, picks freedom.",
      style: "Technical but accessible. Explains DeFi mechanics. Sarcastic about regulators.",
      categories: [:defi, :regulation, :stablecoins, :rwa]
    },
    %{
      username: "alex_ward",
      email: "alex@blockster.com",
      bio: "Privacy advocate and self-custody evangelist. Cypherpunk at heart.",
      style: "Passionate about privacy. Uses historical parallels. Warns about surveillance.",
      categories: [:privacy, :cbdc, :security_hacks, :adoption]
    },
    %{
      username: "sophia_reyes",
      email: "sophia@blockster.com",
      bio: "Web3 gaming and NFT specialist. Believes in the metaverse (unironically).",
      style: "Enthusiastic about innovation. Pop culture references. Younger voice.",
      categories: [:gaming, :nft, :token_launches, :ai_crypto]
    },
    %{
      username: "marcus_stone",
      email: "marcus@blockster.com",
      bio: "Reformed Wall Street trader. Now full-time crypto. Never going back.",
      style: "Sharp, confident takes. Loves contrarian positions. Uses trader slang.",
      categories: [:trading, :altcoins, :investment, :gambling]
    },
    %{
      username: "nina_takashi",
      email: "nina@blockster.com",
      bio: "AI researcher exploring the intersection of machine learning and blockchain.",
      style: "Explains complex tech simply. Excited about possibilities. Skeptical of hype.",
      categories: [:ai_crypto, :ethereum, :adoption, :rwa]
    },
    %{
      username: "ryan_kolbe",
      email: "ryan@blockster.com",
      bio: "Former cybersecurity engineer. Now covers crypto security and mining.",
      style: "Technical detail when it matters. Breaks down exploits clearly. Dry humor.",
      categories: [:security_hacks, :mining, :privacy, :bitcoin]
    },
    %{
      username: "elena_vasquez",
      email: "elena@blockster.com",
      bio: "DeFi yield farmer and stablecoin analyst. Believes sound money wins.",
      style: "Numbers-focused. Compares protocols fairly. Calls out unsustainable yields.",
      categories: [:stablecoins, :defi, :cbdc, :macro_trends]
    }
  ]

  @doc "Returns the static list of persona definitions."
  def personas, do: @personas

  @doc """
  Select an author persona for a given category string.
  Returns `{:ok, %{persona | user_id: id}}` or `{:error, :no_author_found}`.

  Looks up the persona's User record by email to get the `user_id`.
  Falls back to a random persona if no match for the category.
  """
  def select_for_category(category) when is_binary(category) do
    cat_atom = safe_to_atom(category)
    matching = Enum.filter(@personas, fn p -> cat_atom in p.categories end)
    candidates = if Enum.empty?(matching), do: @personas, else: matching
    persona = Enum.random(candidates)

    case get_user_id(persona.email) do
      nil -> {:error, :no_author_found}
      user_id -> {:ok, Map.put(persona, :user_id, user_id)}
    end
  end

  @doc """
  Get persona definition by username. Used for prompt construction.
  """
  def get_persona(username) do
    Enum.find(@personas, &(&1.username == username))
  end

  @doc """
  Get all author user IDs (for admin queries).
  """
  def author_emails do
    Enum.map(@personas, & &1.email)
  end

  # Look up the User record for a persona email. Cached in process dictionary
  # to avoid repeated DB queries within the same GenServer cycle.
  defp get_user_id(email) do
    cache_key = {:author_user_id, email}

    case Process.get(cache_key) do
      nil ->
        user_id =
          from(u in User, where: u.email == ^email, select: u.id)
          |> Repo.one()

        if user_id, do: Process.put(cache_key, user_id)
        user_id

      cached ->
        cached
    end
  end

  defp safe_to_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> :unknown
  end
end
