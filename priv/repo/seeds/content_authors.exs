# Seeds 8 author personas for the content automation pipeline.
#
# Run with: mix run priv/repo/seeds/content_authors.exs
#
# Safe to run multiple times — skips existing accounts (unique email constraint).
# These users have fake wallet addresses and cannot log in or receive tokens.
# They exist solely as author_id references for automated posts.

alias BlocksterV2.Repo
alias BlocksterV2.Accounts.User

for persona <- BlocksterV2.ContentAutomation.AuthorRotator.personas() do
  # Generate deterministic fake wallet address from email
  wallet_hash = :crypto.hash(:sha256, persona.email) |> Base.encode16(case: :lower)
  fake_wallet = "0x" <> String.slice(wallet_hash, 0, 40)

  attrs = %{
    email: persona.email,
    wallet_address: fake_wallet,
    username: persona.username,
    auth_method: "email",
    is_admin: false,
    is_author: true
  }

  changeset = User.changeset(%User{}, attrs)

  case Repo.insert(changeset) do
    {:ok, user} ->
      IO.puts("Created author: #{persona.username} (user_id: #{user.id}, email: #{persona.email})")

    {:error, %{errors: errors}} ->
      if Keyword.has_key?(errors, :email) or Keyword.has_key?(errors, :wallet_address) do
        # Already exists — look up and report
        existing = Repo.get_by(User, email: persona.email)
        IO.puts("Already exists: #{persona.username} (user_id: #{existing && existing.id})")
      else
        IO.puts("Error creating #{persona.username}: #{inspect(errors)}")
      end
  end
end

IO.puts("\nDone! Author personas are ready.")
