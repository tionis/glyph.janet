defmodule Glyph.Dice_Parser do
  @spec parse_roll_options(nonempty_maybe_improper_list) :: {integer, list}
  def parse_roll_options(words) do
    {dice_amount, ""} = Integer.parse(hd(words))

    if Enum.count(words) < 2 do
      {dice_amount, []}
    else
      dice_modifier_string = hd(tl(words))

      dice_modifiers =
        []
        |> check_nine_again(dice_modifier_string)
        |> check_eight_again(dice_modifier_string)
        |> check_seven_again(dice_modifier_string)
        |> check_rote_quality(dice_modifier_string)
        |> check_no_reroll(dice_modifier_string)
		|> check_secret_roll(dice_modifier_string)

      {dice_amount, dice_modifiers}
    end
  end

  defp check_secret_roll(dice_modifiers, dice_modifier_string) do
	if dice_modifier_string =~ "s" do
		[:secret | dice_modifiers]
	end
  end

  defp check_nine_again(dice_modifiers, dice_modifier_string) do
    if dice_modifier_string =~ "9" do
      [:nine_again | dice_modifiers]
    else
      dice_modifiers
    end
  end

  defp check_eight_again(dice_modifiers, dice_modifier_string) do
    if dice_modifier_string =~ "8" do
      [:eight_again | List.delete(dice_modifiers, :nine_again)]
    else
      dice_modifiers
    end
  end

  defp check_seven_again(dice_modifiers, dice_modifier_string) do
    if dice_modifier_string =~ "7" do
      [:seven_again | List.delete(List.delete(dice_modifiers, :eight_again), :nine_again)]
    else
      dice_modifiers
    end
  end

  defp check_rote_quality(dice_modifiers, dice_modifier_string) do
    if dice_modifier_string =~ "r" do
      [:rote_quality | dice_modifiers]
    else
      dice_modifiers
    end
  end

  defp check_no_reroll(dice_modifiers, dice_modifier_string) do
    if dice_modifier_string =~ "n" do
      [:no_reroll]
    else
      dice_modifiers
    end
  end

  def parse_dice_notation(text) do
    result = String.split(text, "d")
    {amount, _} = result |> hd() |> Integer.parse()
    {sides, _} = result |> tl() |> hd() |> Integer.parse()
    {amount, sides}
  end
end
