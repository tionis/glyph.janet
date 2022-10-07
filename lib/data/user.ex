defmodule Glyph.Data.User do
  def get_init_list(user_id) do
    init_list = :ets.lookup(:glyph_init_mod, user_id)
	{:ok, elem(hd(init_list), 1)}
  end

  def set_init_list(user_id, init_list) do
    :ets.insert(:glyph_init_mod, {user_id, init_list})
    {:ok}
  end

  def get_id_from_discord_msg(msg) do
    "dc:" <> Integer.to_string(Map.get(msg, :author) |> Map.get(:id))
  end

  def get_id_from_discord_id(id) do
    "dc:" <> Integer.to_string(id)
  end

  def get_gm(user_id) do
	gm = :ets.lookup(:glyph_user_gm, user_id)
	{:ok, elem(hd(gm), 1)}
  end

  def set_gm(user_id, user_gm) do
    :ets.insert(:glyph_user_gm, {user_id, user_gm})
    {:ok}
  end
end
