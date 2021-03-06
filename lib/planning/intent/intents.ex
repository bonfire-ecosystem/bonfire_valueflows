# SPDX-License-Identifier: AGPL-3.0-only
defmodule ValueFlows.Planning.Intent.Intents do
  import Bonfire.Common.Utils, only: [maybe_put: 3, attr_get_id: 2, maybe: 2, map_key_replace: 3, e: 3]

  import Bonfire.Common.Config, only: [repo: 0]

  # alias Bonfire.GraphQL
  alias Bonfire.GraphQL.{Fields, Page}
  alias ValueFlows.Util

  alias ValueFlows.Knowledge.Action.Actions
  alias ValueFlows.Planning.Intent
  alias ValueFlows.Planning.Intent.Queries

  def cursor(), do: &[&1.id]
  def test_cursor(), do: &[&1["id"]]

  @doc """
  Retrieves a single one by arbitrary filters.
  Used by:
  * GraphQL Item queries
  * ActivityPub integration
  * Various parts of the codebase that need to query for this (inc. tests)
  """
  def one(filters), do: repo().single(Queries.query(Intent, filters))

  def by_id(id, current_user \\ nil) do
    one([
      :default,
      user: current_user,
      id: id
      # preload: :tags
    ])
  end

  @doc """
  Retrieves a list of them by arbitrary filters.
  Used by:
  * Various parts of the codebase that need to query for this (inc. tests)
  """
  def many(filters \\ []), do: {:ok, repo().many(Queries.query(Intent, filters))}

  def fields(group_fn, filters \\ [])
      when is_function(group_fn, 1) do
    {:ok, fields} = many(filters)
    {:ok, Fields.new(fields, group_fn)}
  end

  @doc """
  Retrieves an Page of intents according to various filters

  Used by:
  * GraphQL resolver single-parent resolution
  """
  def page(cursor_fn, page_opts, base_filters \\ [], data_filters \\ [], count_filters \\ [])

  def page(cursor_fn, %{} = page_opts, base_filters, data_filters, count_filters) do
    base_q = Queries.query(Intent, base_filters)
    data_q = Queries.filter(base_q, data_filters)
    count_q = Queries.filter(base_q, count_filters)

    with {:ok, [data, counts]} <- repo().transact_many(all: data_q, count: count_q) do
      {:ok, Page.new(data, counts, cursor_fn, page_opts)}
    end
  end

  @doc """
  Retrieves an Pages of intents according to various filters

  Used by:
  * GraphQL resolver bulk resolution
  """
  def pages(
        cursor_fn,
        group_fn,
        page_opts,
        base_filters \\ [],
        data_filters \\ [],
        count_filters \\ []
      )

  def pages(cursor_fn, group_fn, page_opts, base_filters, data_filters, count_filters) do
    Bonfire.GraphQL.Pagination.pages(
      Queries,
      Intent,
      cursor_fn,
      group_fn,
      page_opts,
      base_filters,
      data_filters,
      count_filters
    )
  end

  def preload_all(%Intent{} = intent) do
    # shouldn't fail
    {:ok, intent} = one(id: intent.id, preload: :all)
    preload_action(intent)
  end

  def preload_action(%Intent{} = intent) do
    Map.put(intent, :action, Actions.action!(intent.action_id))
  end

  ## mutations

  @spec create(any(), attrs :: map) :: {:ok, Intent.t()} | {:error, Changeset.t()}
  def create(%{} = creator, attrs) when is_map(attrs) do

    attrs = prepare_attrs(attrs, creator)

    repo().transact_with(fn ->
      with {:ok, intent} <- repo().insert(Intent.create_changeset(creator, attrs)),
           intent <- preload_all(%{intent | creator: creator}),
           {:ok, intent} <- ValueFlows.Util.try_tag_thing(nil, intent, attrs),
           {:ok, activity} <- ValueFlows.Util.publish(creator, :intend, intent) do

        indexing_object_format(intent) |> ValueFlows.Util.index_for_search()

        {:ok, intent}
      end
    end)
  end

  def update(current_user, id, changes) when is_binary(id) do
    with {:ok, intent} <- by_id(id, current_user) do
      update(intent, changes)
    end
  end

  def update(current_user, %Intent{} = intent, changes) do
    with :ok <- ValueFlows.Util.ensure_edit_permission(current_user, intent) do
      update(intent, changes)
    end
  end

  # TODO: turn into private function
  def update(%Intent{} = intent, attrs) do
    attrs = prepare_attrs(attrs, e(intent, :creator, nil))

    repo().transact_with(fn ->
      with {:ok, intent} <- repo().update(Intent.update_changeset(intent, attrs)),
           intent <- preload_all(intent),
           {:ok, intent} <- ValueFlows.Util.try_tag_thing(nil, intent, attrs),
           {:ok, _} <- ValueFlows.Util.publish(intent, :update) do
        {:ok, intent}
      end
    end)
  end

  def soft_delete(%{} = current_user, id) when is_binary(id) do
      with {:ok, intent} <- by_id(id, current_user) do
        soft_delete(current_user, intent)
      end
  end

  def soft_delete(%{} = current_user, %Intent{} = intent) do
      with :ok <- ValueFlows.Util.ensure_edit_permission(current_user, intent) do
        soft_delete(intent)
      end
  end

  # TODO: turn into private function
  def soft_delete(%Intent{} = intent) do
    repo().transact_with(fn ->
      with {:ok, intent} <- Bonfire.Repo.Delete.soft_delete(intent),
           {:ok, _} <- ValueFlows.Util.publish(intent, :deleted) do
        {:ok, intent}
      end
    end)
  end

  def indexing_object_format(obj) do

    image = ValueFlows.Util.image_url(obj)

    %{
      "index_type" => "ValueFlows.Planning.Intent",
      "id" => obj.id,
      # "url" => obj.canonical_url,
      # "icon" => icon,
      "image" => image,
      "name" => obj.name,
      "summary" => Map.get(obj, :note),
      "published_at" => obj.published_at,
      "creator" => ValueFlows.Util.indexing_format_creator(obj)
      # "index_instance" => URI.parse(obj.canonical_url).host, # home instance of object
    }
  end

  def prepare_attrs(attrs, creator \\ nil) do
    attrs
    |> maybe_put(:action_id, attr_get_id(attrs, :action) |> ValueFlows.Knowledge.Action.Actions.id())
    |> maybe_put(:context_id,
      attrs |> Map.get(:in_scope_of) |> maybe(&List.first/1)
    )
    |> maybe_put(:at_location_id, attr_get_id(attrs, :at_location))
    |> maybe_put(:provider_id, attr_get_id(attrs, :provider))
    |> maybe_put(:receiver_id, attr_get_id(attrs, :receiver))
    |> maybe_put(:input_of_id, attr_get_id(attrs, :input_of))
    |> maybe_put(:output_of_id, attr_get_id(attrs, :output_of))
    |> maybe_put(:resource_conforms_to_id, attr_get_id(attrs, :resource_conforms_to))
    |> maybe_put(:resource_inventoried_as_id, attr_get_id(attrs, :resource_inventoried_as))
    |> Util.parse_measurement_attrs(creator)
  end


end
