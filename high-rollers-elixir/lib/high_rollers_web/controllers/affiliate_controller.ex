defmodule HighRollersWeb.AffiliateController do
  @moduledoc """
  API endpoints for affiliate linking (called by JavaScript when wallet connects).
  """
  use HighRollersWeb, :controller

  @doc """
  POST /api/link-affiliate

  Links a buyer to an affiliate permanently. First referrer wins.
  Also triggers on-chain linkAffiliate() via AdminTxQueue.

  Request body:
    {"buyer": "0x...", "affiliate": "0x..."}

  Response:
    {"success": true, "affiliate": "0x...", "affiliate2": "0x..." | null, "is_new": bool, "on_chain_queued": bool}
  """
  def link(conn, %{"buyer" => buyer, "affiliate" => affiliate}) do
    with {:ok, _} <- validate_address(buyer),
         {:ok, _} <- validate_address(affiliate) do

      case HighRollers.Users.link_affiliate(buyer, affiliate) do
        {:ok, result} ->
          # Queue on-chain linking if this is a new link
          on_chain_queued = if result.is_new do
            HighRollers.AdminTxQueue.enqueue_link_affiliate(buyer, result.affiliate)
            true
          else
            false
          end

          json(conn, %{
            success: true,
            affiliate: result.affiliate,
            affiliate2: result.affiliate2,
            is_new: result.is_new,
            on_chain_queued: on_chain_queued
          })

        {:error, :self_referral} ->
          conn
          |> put_status(400)
          |> json(%{error: "Cannot refer yourself"})
      end
    else
      {:error, :invalid_address} ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid address format"})
    end
  end

  def link(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Missing buyer or affiliate address"})
  end

  @doc """
  GET /api/buyer-affiliate/:buyer

  Get the affiliate linked to a buyer address.
  Returns default affiliate if none linked.

  Response:
    {"buyer": "0x...", "affiliate": "0x...", "has_custom_affiliate": bool}
  """
  def get_buyer_affiliate(conn, %{"buyer" => buyer}) do
    with {:ok, _} <- validate_address(buyer) do
      case HighRollers.Users.get(buyer) do
        %{affiliate: affiliate} = _user when not is_nil(affiliate) ->
          json(conn, %{
            buyer: String.downcase(buyer),
            affiliate: affiliate,
            has_custom_affiliate: true
          })

        _ ->
          json(conn, %{
            buyer: String.downcase(buyer),
            affiliate: default_affiliate(),
            has_custom_affiliate: false
          })
      end
    else
      {:error, :invalid_address} ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid address"})
    end
  end

  # ===== Helpers =====

  defp validate_address(address) when is_binary(address) do
    if Regex.match?(~r/^0x[a-fA-F0-9]{40}$/, address) do
      {:ok, address}
    else
      {:error, :invalid_address}
    end
  end
  defp validate_address(_), do: {:error, :invalid_address}

  defp default_affiliate do
    # Default affiliate address (project treasury)
    Application.get_env(:high_rollers, :default_affiliate, "0x0000000000000000000000000000000000000000")
  end
end
