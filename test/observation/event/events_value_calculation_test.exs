defmodule ValueFlows.EventsValueCalculationTest do
  use Bonfire.ValueFlows.DataCase, async: true

  import Bonfire.Quantify.Simulate, only: [fake_unit!: 1]
  import ValueFlows.Simulate
  import ValueFlows.Test.Faking

  alias ValueFlows.EconomicEvent.EconomicEvents
  alias ValueFlows.Knowledge.Action.Actions

  describe "create a reciprocal event" do
    test "that has a matching action" do
      user = fake_agent!()
      assert {:ok, action} = Actions.action("produce")
      calc = fake_value_calculation!(user, %{action: action.id, formula: "(+ 1 effortQuantity)"})
      event = fake_economic_event!(user, %{action: action.id})

      assert {:ok, reciprocal} = EconomicEvents.one(calculated_using_id: calc.id)
      assert reciprocal = EconomicEvents.preload_all(reciprocal)
      assert reciprocal.action_id == calc.value_action_id
      assert reciprocal.resource_quantity.has_numerical_value ==
        1.0 + reciprocal.effort_quantity.has_numerical_value
    end

    test "effort quantity if action is work or use" do
      user = fake_agent!()
      assert {:ok, action} = ["use", "work"]
      |> Faker.Util.pick()
      |> Actions.action()
      calc = fake_value_calculation!(user, %{action: action.id, formula: "(+ 1 resourceQuantity)"})
      event = fake_economic_event!(user, %{action: action.id})

      assert {:ok, reciprocal} = EconomicEvents.one(calculated_using_id: calc.id)
      assert reciprocal = EconomicEvents.preload_all(reciprocal)
      assert reciprocal.effort_quantity.has_numerical_value ==
        1.0 + reciprocal.resource_quantity.has_numerical_value
    end
  end
end