# SPDX-License-Identifier: AGPL-3.0-only
defmodule ValueFlows.Agent.People do
  # alias ValueFlows.{Simulate}
  require Logger

  def people(signed_in_user) do
    people = if Bonfire.Common.Utils.module_enabled?(Bonfire.Me.Users) do
         Bonfire.Me.Users.list()
    else
      if Bonfire.Common.Utils.module_enabled?(CommonsPub.Users) do
        {:ok, users} = CommonsPub.Users.many([:default, user: signed_in_user])
        users
      else
        []
      end
    end

    Enum.map(
      people,
      &(&1
        |> ValueFlows.Agent.Agents.character_to_agent())
    )

  end


  def person(id, signed_in_user) when is_binary(id) do
    person = if Bonfire.Common.Utils.module_enabled?(Bonfire.Me.Users) do
         with {:ok, user} <- Bonfire.Me.Users.by_id(id) do
          user
         else _ ->
          nil
        end
    else
      if Bonfire.Common.Utils.module_enabled?(CommonsPub.Users) do
        with {:ok, user} <-
              CommonsPub.Users.one([:default, :geolocation, id: id, user: signed_in_user]) do
          user
        else _ ->
          nil
        end
      end
    end

    if person do
      ValueFlows.Agent.Agents.character_to_agent(person)
    else
      nil
    end

  end

  def person(_, _), do: nil

end
