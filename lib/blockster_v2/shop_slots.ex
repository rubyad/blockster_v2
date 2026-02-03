defmodule BlocksterV2.ShopSlots do
  @moduledoc """
  Manages shop product slot assignments in Mnesia.
  Each slot is independent - assigning a product to one slot
  does not affect any other slot.
  """

  @doc """
  Get the product_id assigned to a specific slot.
  Returns nil if slot is empty or not yet assigned.
  """
  def get_slot(slot_number) when is_integer(slot_number) do
    case :mnesia.dirty_read({:shop_product_slots, slot_number}) do
      [{:shop_product_slots, ^slot_number, product_id}] -> product_id
      [] -> nil
    end
  end

  @doc """
  Get all slot assignments as a map of %{slot_number => product_id}.
  Only returns slots that have been assigned (not empty ones).
  """
  def get_all_slots do
    :mnesia.dirty_match_object({:shop_product_slots, :_, :_})
    |> Enum.reduce(%{}, fn {:shop_product_slots, slot_number, product_id}, acc ->
      Map.put(acc, slot_number, product_id)
    end)
  end

  @doc """
  Assign a product to a specific slot.
  Overwrites any existing assignment for that slot.
  Does NOT affect any other slots.
  """
  def set_slot(slot_number, product_id) when is_integer(slot_number) do
    :mnesia.dirty_write({:shop_product_slots, slot_number, product_id})
    :ok
  end

  @doc """
  Clear a slot (set to empty/nil).
  """
  def clear_slot(slot_number) when is_integer(slot_number) do
    :mnesia.dirty_write({:shop_product_slots, slot_number, nil})
    :ok
  end

  @doc """
  Build display list for a given number of slots.
  Returns list of {slot_number, product_id_or_nil} tuples.
  """
  def build_display_list(total_slots) do
    slot_map = get_all_slots()

    Enum.map(0..(total_slots - 1), fn slot_number ->
      {slot_number, Map.get(slot_map, slot_number)}
    end)
  end
end
