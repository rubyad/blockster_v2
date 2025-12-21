defmodule BlocksterV2.SiteSettings do
  @moduledoc """
  Context for managing site-wide settings stored in the database.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.SiteSettings.Setting

  @doc """
  Gets a setting value by key. Returns nil if not found.
  """
  def get(key) when is_binary(key) do
    case Repo.get_by(Setting, key: key) do
      nil -> nil
      setting -> setting.value
    end
  end

  @doc """
  Gets a setting value by key with a default if not found.
  """
  def get(key, default) when is_binary(key) do
    get(key) || default
  end

  @doc """
  Sets a setting value. Creates if doesn't exist, updates if it does.
  """
  def set(key, value) when is_binary(key) do
    case Repo.get_by(Setting, key: key) do
      nil ->
        %Setting{}
        |> Setting.changeset(%{key: key, value: value})
        |> Repo.insert()

      setting ->
        setting
        |> Setting.changeset(%{value: value})
        |> Repo.update()
    end
  end

  @doc """
  Deletes a setting by key.
  """
  def delete(key) when is_binary(key) do
    case Repo.get_by(Setting, key: key) do
      nil -> {:ok, nil}
      setting -> Repo.delete(setting)
    end
  end
end
