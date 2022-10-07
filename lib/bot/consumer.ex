defmodule Glyph.Bot.Consumer do
  @moduledoc """
  A module that implements all logic that consumes discord events,
  at least for the moment
  """
  use Nostrum.Consumer

  alias Nostrum.Api
  alias Nostrum.Voice
  alias Nostrum.Cache.GuildCache
  alias Glyph.Dice
  alias Glyph.Data.User
  # alias Glyph.Bot.Commands

  @spec start_link :: :ignore | {:error, any} | {:ok, pid}
  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def get_voice_channel_of_msg(msg) do
    msg.guild_id
    |> GuildCache.get!()
    |> Map.get(:voice_states)
    |> Enum.find(%{}, fn v -> v.user_id == msg.author.id end)
    |> Map.get(:channel_id)
  end

  def handle_event({:PRESENCE_UPDATE, {_guild_id, old_presence, new_presence}, _ws_state}) do
    if old_presence == nil || new_presence == nil do
      :noop
    else
      new_status = Map.get(new_presence, :client_status)
      old_status = Map.get(old_presence, :client_status)

      if new_status != old_status do
        case Map.get(Map.get(new_presence, :user), :id) do
          7_704_282_912_448_839_886 ->
            cond do
              Map.get(new_status, :desktop, :offline) == :online ->
                send_admin_message("Joe is online!")

              Map.get(new_status, :mobile, :offline) == :online ->
                send_admin_message("Joe is online on phone!")

              true ->
                :noop
            end

          # 259076782408335360 ->
          #  cond do
          #    Map.get(new_status, :desktop, :offline) == :online -> send_admin_message("Tionis is online!")
          #    Map.get(new_status, :mobile, :offline) == :online -> send_admin_message("Tionis is online on phone!")
          #    true -> :noop
          #  end
          _ ->
            :noop
        end
      else
        :noop
      end
    end
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    # This logic of this function could be replaced by
    # multiple "command" functions using pattern matching
    words = String.split(msg.content, " ")

    author_mention = Map.get(msg, :author) |> Nostrum.Struct.User.mention()
    msg_preamble = author_mention <> "\n"
    user_id = Integer.to_string(msg.author.id)
	
	IO.inspect(words)
    case hd(words) do
      "/roll" ->
        if length(words) == 1 do
          Api.create_message!(msg.channel_id, "Invalid command!")
        else
          Api.create_message!(
            msg.channel_id,
            msg_preamble <> handle_roll(tl(words))
          )
        end

      "/badluck" -> Api.create_message!(
          msg.channel_id,
          msg_preamble <> handle_bad_luck()
        )

      "/bad_luck" -> Api.create_message!(
          msg.channel_id,
          msg_preamble <> handle_bad_luck()
        )

      "/bl" -> Api.create_message!(
        msg.channel_id,
        msg_preamble <> handle_bad_luck()
      )

      "/r" ->
        Api.create_message!(
          msg.channel_id,
          msg_preamble <> handle_roll(tl(words))
        )

      "roll" ->
        Api.create_message!(
          msg.channel_id,
          msg_preamble <> handle_roll(tl(words))
        )

      "r" ->
        Api.create_message!(
          msg.channel_id,
          msg_preamble <> handle_roll(tl(words))
        )


      "/sr" ->
        Api.create_message!(
          msg.channel_id,
          msg_preamble <> handle_shadow_roll(tl(words), user_id)
        )

      "/edge" ->
        Api.create_message!(
          msg.channel_id,
          msg_preamble <> handle_shadow_edge(user_id)
        )

      "/e" ->
        Api.create_message!(
          msg.channel_id,
          msg_preamble <> handle_shadow_edge(user_id)
        )

      "/shadowroll" ->
        Api.create_message!(
          msg.channel_id,
          msg_preamble <> handle_shadow_roll(tl(words), user_id)
        )

      "/ping" ->
        Api.create_message!(msg.channel_id, msg_preamble <> "pong!")

      "/channel_id" ->
        Api.create_message!(msg.channel_id, "#{msg.channel_id}")

      "/help" ->
        Api.create_message!(msg.channel_id, msg_preamble <> get_help())

      "init" ->
        Api.create_message!(
          msg.channel_id,
          msg_preamble <> handle_initiative(tl(words), User.get_id_from_discord_msg(msg))
        )

      "/rollinit" ->
        Api.create_message!(msg.channel_id, msg_preamble <> handle_mass_roll(tl(words)))

      "/remindme" ->
        Api.create_message!(msg.channel_id, msg_preamble <> "Not implemented yet!")

      "gsummon" ->
        summon(msg)
		
	  "gm" ->
		# TODO add help message if words emtpy or in invalid syntax
		id_as_string = String.to_integer(hd(Regex.run(~r/\d+/,"")))
		IO.inspect(id_as_string)
		User.set_gm(User.get_id_from_discord_msg(msg),
					User.get_id_from_discord_id(id_as_string))

      "gleave" ->
        Voice.leave_channel(msg.guild_id)

      "gunsummon" ->
        Voice.leave_channel(msg.guild_id)

      "gplay" ->
        if Voice.ready?(msg.guild_id) do
          :ok = Voice.play(msg.guild_id, Enum.at(words, 1), :ytdl, realtime: true)
        else
          do_not_ready_msg(msg)
        end

      "gpause" ->
        Voice.pause(msg.guild_id)

      "gresume" ->
        Voice.resume(msg.guild_id)

      "gstop" ->
        Voice.stop(msg.guild_id)

      "gairhorn" ->
        if Voice.ready?(msg.guild_id) do
          :ok =
            Voice.play(msg.guild_id, Path.join(:code.priv_dir(:glyph), "airhorn.mp3"), :url,
              realtime: false
            )
        else
          do_not_ready_msg(msg)
        end

      _ ->
        :ignore
    end
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    case Map.get(interaction, :data) |> Map.get(:name) do
      "roll" -> handle_roll_interaction(interaction)
      "rollinit" -> handle_mass_roll_interaction(interaction)
      "shadowroll" -> handle_shadowroll_interaction(interaction)
      "edge" -> handle_edge_interaction(interaction)
      "badluck" -> handle_badluck_interaction(interaction)
      _ -> :ignore
    end
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end

  defp summon(msg) do
    case get_voice_channel_of_msg(msg) do
      nil -> Api.create_message(msg.channel_id, "Must be in a voice channel to summon")
      voice_channel_id -> Voice.join_channel(msg.guild_id, voice_channel_id)
    end
  end

  defp send_admin_message(message) do
    Api.create_message!(637_639_941_521_801_227, message)
  end

  def get_help() do
    # " - /quote - quotator commands" <>
    # " - /remindme $ISO_Date $Text-  sends a reminder with text at ISO Date"
    "Available Commands\n" <>
      "  General Commands\n" <>
      "   - /roll <dice> <modifiers> - roll construct dice or x y-sided die with the xdy notation\n" <>
      "   - /r - shortcut for /roll\n" <>
      "   - /init - main command to roll your init\n" <>
      "   - /rollinit - roll multiple inits\n" <>
      "   - /ping - returns pong\n" <>
      "   - /shadowroll <amount> <mod>- roll <amount> shadowrun dice, if <mod> contains `e` use edge" <>
      "   - /sr - Shortcut for shadowroll" <>
      "   - /edge - use edge retroactivly on the last dice throw, you can also use /e for this" <>
      "   - /e - shortcut for /edge"
      "  Voice Commands\n" <>
      "   - /summon - Summon bot to voice channel\n" <>
      "   - /leave - Tell bot to leave voice channel\n" <>
      "   - /resume - Resume playback\n" <>
      "   - /pause - Pause playback\n" <>
      "   - /stop - Stop playback\n" <>
      "   - /airhorn - Play an airhorn sound\n"
  end

  defp handle_initiative(words, user_id) do
    case hd(words) do
      "roll" -> handle_roll_init_mod(tl(words), user_id)
      "save" -> handle_save_init_mod(tl(words), user_id)
      _ -> :ignore
    end
  end

  defp do_not_ready_msg(msg) do
    Api.create_message(
      msg.channel_id,
      "I need to be in a voice channel for that.\nUse /summon for that"
    )
  end

  defp handle_roll_init_mod(words, user_id) do
	one_based_index = if length(words) > 0 do
		{index, _} = Integer.parse(hd(words))
		index
	else
		1
	end
    {:ok, init_list} = User.get_init_list(user_id)

    if length(init_list) > 0 do
		IO.inspect(one_based_index)
		IO.inspect(init_list)
      IO.inspect(Enum.at(init_list, one_based_index - 1))
    else
      "No init modifier saved!"
    end
  end

  defp handle_save_init_mod(words, user_id) do
    {:ok} = User.set_init_list(user_id, words)
    "Saved your init values:\n" <> List.to_string(words)
  end

  defp handle_mass_roll(words) do
    if Enum.count(words) > 2 do
      raise ArgumentError
    else
      {amount, _} = Integer.parse(hd(words))
      {init_mod, _} = Integer.parse(Enum.at(words, 1))
      get_mass_roll_string(amount, init_mod, 1)
    end
  end

  defp get_mass_roll_string(amount, init_mod, index) do
    if amount == 1 do
      get_mass_roll_init_line(amount, index)
    else
      get_mass_roll_init_line(amount, index) <>
        "\n" <> get_mass_roll_string(amount - 1, init_mod, index + 1)
    end
  end

  defp get_mass_roll_init_line(init_mod, index) do
    Integer.to_string(index) <>
      ": " <> Integer.to_string(Dice.roll_one_y_sided_die(10) + init_mod)
  end

  defp handle_mass_roll_interaction(interaction) do
    message = get_answer_for_massroll_interaction(interaction)

    response = %{
      type: 4,
      data: %{
        content: message
      }
    }

    Api.create_interaction_response(interaction, response)
  end

  defp get_answer_for_massroll_interaction(interaction) do
    options = Map.get(interaction, :data) |> Map.get(:options)

    amount =
      Enum.filter(options, fn x -> Map.get(x, :name) == "amount" end)
      |> hd
      |> Map.get(:value)
      |> Integer.to_string()

    init_mods =
      Enum.filter(options, fn x -> Map.get(x, :name) == "init-mods" end)
      |> hd
      |> Map.get(:value)
      |> Integer.to_string()

    handle_mass_roll([amount, init_mods])
  end

  defp handle_shadowroll_interaction(interaction) do
    message = get_answer_for_shadowroll_interaction(interaction)

    response = %{
      type: 4,
      data: %{
        content: message
      }
    }

    Api.create_interaction_response(interaction, response)
  end

  defp handle_edge_interaction(interaction) do
    message =
      Map.get(interaction, :user)
      |> Map.get(:id)
      |> Integer.to_string()
      |> handle_shadow_edge()

    response = %{
      type: 4,
      data: %{
        content: message
      }
    }

    Api.create_interaction_response(interaction, response)
  end

  defp handle_badluck_interaction(interaction) do
    response = %{
      type: 4,
      data: %{
        content: handle_bad_luck()
      }
    }

    Api.create_interaction_response(interaction, response)
  end

  defp handle_roll_interaction(interaction) do
    message = get_answer_for_roll_interaction(interaction)

    response = %{
      type: 4,
      data: %{
        content: message
      }
    }

    Api.create_interaction_response(interaction, response)
  end

  defp get_answer_for_shadowroll_interaction(interaction) do
    user_id = Map.get(interaction, :user) |> Map.get(:id) |> Integer.to_string()
    options = Map.get(interaction, :data) |> Map.get(:options)

    if Enum.empty?(Enum.filter(options, fn x -> Map.get(x, :name) == "is_edge" end)) do
      amount =
        Enum.filter(options, fn x -> Map.get(x, :name) == "amount" end)
        |> hd
        |> Map.get(:value)

      handle_shadow_roll([Integer.to_string(amount)], user_id)
    else
      amount =
        Enum.filter(options, fn x -> Map.get(x, :name) == "amount" end)
        |> hd
        |> Map.get(:value)

      is_edge =
        Enum.filter(options, fn x -> Map.get(x, :name) == "is_edge" end)
        |> hd
        |> Map.get(:value)

      if is_edge do
        handle_shadow_roll([Integer.to_string(amount), "e"], user_id)
      else
        handle_shadow_roll([Integer.to_string(amount)], user_id)
      end
    end
  end

  defp get_answer_for_roll_interaction(interaction) do
    options = Map.get(interaction, :data) |> Map.get(:options)

    if Enum.empty?(Enum.filter(options, fn x -> Map.get(x, :name) == "dice-modifiers" end)) do
      handle_roll([
        Enum.filter(
          options,
          fn x -> Map.get(x, :name) == "dice-amount" end
        )
        |> hd
        |> Map.get(:value)
      ])
    else
      dice_amount =
        Enum.filter(options, fn x -> Map.get(x, :name) == "dice-amount" end)
        |> hd
        |> Map.get(:value)

      dice_modifiers =
        Enum.filter(options, fn x -> Map.get(x, :name) == "dice-modifiers" end)
        |> hd
        |> Map.get(:value)

      handle_roll([dice_amount, dice_modifiers])
    end
  end

  def handle_bad_luck() do
    case Dice.roll_one_y_sided_die(6) do
      1 -> "You rolled a 1\nThat's to bad!\n**No** luck for you!"
      x -> "You rolled a "<> Integer.to_string(x) <>".\nYou've got luck!"
    end
  end

  @spec handle_roll(nonempty_maybe_improper_list) :: binary
  def handle_roll(words) do
    cond do
      Regex.match?(~r/^\d+d\d+$/, hd(words)) ->
        hd(words)
        |> Glyph.Dice_Parser.parse_dice_notation()
        |> Dice.roll_x_y_sided_dice()
        |> normal_dice_result_to_string()

      Regex.match?(~r/^\d+$/, hd(words)) ->
        handle_construct_roll(words)

      Regex.match?(~r/chance/, hd(words)) ->
        handle_chance_die()

      Regex.match?(~r/^one$/, hd(words)) ->
        Dice.roll_x_y_sided_dice({1, 10})
        |> normal_dice_result_to_string()
    end
  end

  def handle_shadow_roll(words, user_id) do
    {amount, _} = Integer.parse(hd(words))
    mods = Enum.at(words, 1)
    with_edge = mods == "e" || mods == "E"
    result = Dice.roll_shadowrun_dice({amount, with_edge})

    Glyph.Data.Store.set_user_data(
      user_id,
      "last_shadow_roll",
      JSON.encode!(%{result: result, is_edge: with_edge})
    )

    result_to_string_2d(result) <>
      get_shadowrun_success_message(
        Dice.count_shadowrun_successes_2d(result),
        Dice.count_ones_first_rolls(result),
        amount
      )
  end

  def handle_shadow_edge(user_id) do
    data = Glyph.Data.Store.get_user_data(user_id, "last_shadow_roll")

    if data == nil do
      "Error: Last roll could not be processed"
    else
      {is_ok, last_roll} = JSON.decode(data)

      if is_ok != :ok do
        "Error: Last roll could not be processed"
      else
        reroll_shadow_throw(user_id, Map.get(last_roll, "result"), Map.get(last_roll, "is_edge"))
      end
    end
  end

  defp reroll_shadow_throw(user_id, last_roll_list, is_edge) do
    result = Dice.shadowrun_reroll(last_roll_list, is_edge)

    Glyph.Data.Store.set_user_data(
      user_id,
      "last_shadow_roll",
      JSON.encode!(%{result: result, is_edge: is_edge})
    )

    "Your reroll results:\n" <>
      result_to_string_2d(result) <>
      get_shadowrun_success_message(
        Dice.count_shadowrun_successes_2d(result),
        Dice.count_ones_first_rolls(result),
        length(last_roll_list)
      )
  end

  defp handle_chance_die() do
    number = Dice.roll_one_y_sided_die(10)
    text = "You rolled a **" <> Integer.to_string(number) <> "**!"

    case number do
      10 -> text <> "\nWell, that's a **success**!"
      1 -> text <> "\nWell, that's a **critical failure**!"
      _ -> text
    end
  end

  def handle_construct_roll(words) do
    {dice_amount, dice_modifiers} = Glyph.Dice_Parser.parse_roll_options(words) # TODO extract GM from command
    result = Dice.roll_construct_dice({dice_amount, dice_modifiers})
	if Enum.member?(dice_modifiers, :secret) do# TODO  maybe add extra command
		# TODO send message to GM with the full results ()
		"I rolled your " <> dice_amount <> " Dice, let's hope for the best!"
	else
		result_to_string_2d(result) <>
			get_success_message(
				Dice.count_successes_2d(result),
				Dice.count_ones_first_rolls(result),
				dice_amount)
	end
  end

  defp normal_dice_result_to_string(result) do
    case Enum.count(result) do
      1 ->
        Integer.to_string(hd(result))

      _ ->
        normal_dice_result_to_string_inner(result) <> " = " <> Integer.to_string(Enum.sum(result))
    end
  end

  defp normal_dice_result_to_string_inner(result) do
    if Enum.count(result) == 1 do
      Integer.to_string(hd(result))
    else
      Integer.to_string(hd(result)) <> " + " <> normal_dice_result_to_string_inner(tl(result))
    end
  end

  defp get_shadowrun_success_message(successes, ones, dice_amount) do
    crit_fail = ones >= Float.round(dice_amount / 2)

    part_one =
      cond do
        successes == 0 -> "\nYou had **no** Hits!"
        successes == 1 -> "\nYou had **1** Hit!"
        true -> "\nYou had **" <> Integer.to_string(successes) <> "** Hits!"
      end

    part_two =
      cond do
        crit_fail && successes == 0 -> "\nWell that's a **critical** Glitch!"
        crit_fail && successes >= 0 -> "\nThat's a Glitch!"
        true -> ""
      end

    part_one <> part_two
  end

  defp get_success_message(successes, ones, dice_amount) do
    crit_fail = ones >= Float.round(dice_amount / 2)

    part_one =
      cond do
        successes == 0 -> "\nYou had **no** Successes!"
        successes == 1 -> "\nYou had **1** Success!"
        true -> "\nYou had **" <> Integer.to_string(successes) <> "** Successes!"
      end

    part_two =
      cond do
        crit_fail -> "\nWell that's a **critical** failure!"
        successes >= 5 -> "\nWell that's an **exceptional** success!"
        true -> ""
      end

    part_one <> part_two
  end

  defp result_to_string_2d(result) do
    cond do
      Enum.empty?(result) -> ""
      Enum.count(result) == 1 -> "[" <> result_to_string_1d(hd(result)) <> "]"
      true -> "[" <> result_to_string_1d(hd(result)) <> "] " <> result_to_string_2d(tl(result))
    end
  end

  defp result_to_string_1d(result) do
    if Enum.count(result) == 1 do
      Integer.to_string(hd(result))
    else
      Integer.to_string(hd(result)) <> "➔" <> result_to_string_1d(tl(result))
    end
  end
end
