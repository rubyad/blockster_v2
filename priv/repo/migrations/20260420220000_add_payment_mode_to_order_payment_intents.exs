defmodule BlocksterV2.Repo.Migrations.AddPaymentModeToOrderPaymentIntents do
  use Ecto.Migration

  # Phase 7 of the social login plan. Future-proofs the table for two flows:
  #
  #   * "manual" (current default) — settler generates an ephemeral pubkey,
  #     buyer transfers SOL to it from their wallet, watcher sweeps to
  #     treasury. Works for Wallet Standard users who have SOL on-hand.
  #
  #   * "wallet_sign" — settler builds a direct transfer tx (fee_payer =
  #     settler, user as transfer authority), Web3Auth user signs locally.
  #     No ephemeral middle-man, no watcher polling needed, zero SOL
  #     required from the user.
  #
  # v1 still uses "manual" for everyone. "wallet_sign" wiring lands behind
  # the SOCIAL_LOGIN_ENABLED flag and is the foundation for Web3Auth SOL
  # shop checkout in v1.1+ (v1 gates SOL items to wallet users — plan §7.4).
  def change do
    alter table(:order_payment_intents) do
      add :payment_mode, :string, null: false, default: "manual"
    end

    create index(:order_payment_intents, [:payment_mode])
  end
end
