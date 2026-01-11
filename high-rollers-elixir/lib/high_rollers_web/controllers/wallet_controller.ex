defmodule HighRollersWeb.WalletController do
  @moduledoc """
  API controller for wallet session management.

  Stores wallet connection state in Phoenix session so that the WalletHook
  can read it on mount, eliminating the flash/flicker when navigating between tabs.

  All endpoints return JSON and expect the browser pipeline for session access.
  """
  use HighRollersWeb, :controller

  @doc """
  Store wallet connection in Phoenix session.
  Called from JavaScript after successful wallet connection.
  """
  def connect(conn, %{"address" => address, "type" => type} = params) do
    balance = Map.get(params, "balance")
    chain = Map.get(params, "chain", "arbitrum")

    conn
    |> put_session(:wallet_address, String.downcase(address))
    |> put_session(:wallet_type, type)
    |> put_session(:wallet_balance, balance)
    |> put_session(:wallet_chain, chain)
    |> json(%{ok: true})
  end

  @doc """
  Clear wallet from Phoenix session.
  Called from JavaScript on disconnect.
  """
  def disconnect(conn, _params) do
    conn
    |> delete_session(:wallet_address)
    |> delete_session(:wallet_type)
    |> delete_session(:wallet_balance)
    |> delete_session(:wallet_chain)
    |> json(%{ok: true})
  end

  @doc """
  Update just the balance in session.
  Called from JavaScript after balance changes.
  """
  def update_balance(conn, %{"balance" => balance} = params) do
    chain = Map.get(params, "chain")

    conn = put_session(conn, :wallet_balance, balance)
    conn = if chain, do: put_session(conn, :wallet_chain, chain), else: conn

    json(conn, %{ok: true})
  end
end
