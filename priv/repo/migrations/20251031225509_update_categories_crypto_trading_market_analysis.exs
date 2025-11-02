defmodule BlocksterV2.Repo.Migrations.UpdateCategoriesCryptoTradingMarketAnalysis do
  use Ecto.Migration

  def up do
    # Update "Trading" to "Crypto Trading"
    execute "UPDATE posts SET category = 'Crypto Trading' WHERE category = 'Trading';"

    # Update "Business" to "Market Analysis"
    execute "UPDATE posts SET category = 'Market Analysis' WHERE category = 'Business';"
  end

  def down do
    # Revert "Crypto Trading" back to "Trading"
    execute "UPDATE posts SET category = 'Trading' WHERE category = 'Crypto Trading';"

    # Revert "Market Analysis" back to "Business"
    execute "UPDATE posts SET category = 'Business' WHERE category = 'Market Analysis';"
  end
end
