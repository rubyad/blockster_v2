defmodule BlocksterV2.Repo.Migrations.AddTokenToHubs do
  use Ecto.Migration

  def change do
    alter table(:hubs) do
      add :token, :string
    end

    # Populate token values for existing hubs
    execute """
    UPDATE hubs SET token = CASE name
      WHEN 'MoonPay' THEN 'moonBUX'
      WHEN 'Flare' THEN 'flareBUX'
      WHEN 'Neo' THEN 'neoBUX'
      WHEN 'New Friendship Tech' THEN 'nftBUX'
      WHEN 'Nolcha' THEN 'nolchaBUX'
      WHEN 'Rogue Trader' THEN 'rogueBUX'
      WHEN 'Solana' THEN 'solBUX'
      WHEN 'Space & Time' THEN 'spaceBUX'
      WHEN 'Tron' THEN 'tronBUX'
      WHEN 'Transak' THEN 'tranBUX'
      ELSE NULL
    END
    """, ""
  end
end
