defmodule Pow.Ecto.Schema do
  @moduledoc """
  Handles the Ecto schema for user.

  The macro will create a `@pow_fields` module attribute, and append fields to
  it using the attributes from `Pow.Ecto.Schema.Fields.attrs/1`. Likewise, a
  `@pow_assocs` module attribute is also generated for associations. The
  `pow_user_fields/0` macro will use these attributes to create fields and
  associations in the ecto schema.

  The macro will add two overridable methods to your module; `changeset/2`
  and `verify_password/2`. See the customization section below for more.

  The following helper methods are added for changeset customization:

    - `pow_changeset/2`,
    - `pow_verify_password/2`
    - `pow_user_id_field_changeset/2`
    - `pow_password_changeset/2`,
    - `pow_current_password_changeset/2`,

  Finally `pow_user_id_field/0` method is added to the module that is used to
  fetch the user id field name.

  A `@pow_config` module attribute is created containing the options that were
  passed to the macro with the `use Pow.Ecto.Schema, ...` call.

  ## Usage

  Configure `lib/my_project/users/user.ex` the following way:

      defmodule MyApp.Users.User do
        use Ecto.Schema
        use Pow.Ecto.Schema,
          user_id_field: :email,
          password_hash_methods: {&Pow.Ecto.Schema.Password.pbkdf2_hash/1,
                                  &Pow.Ecto.Schema.Password.pbkdf2_verify/2},
          password_min_length: 10,
          password_max_length: 4096

        schema "users" do
          field :custom_field, :string

          pow_user_fields()

          timestamps()
        end

        def changeset(user_or_changeset, attrs) do
          pow_changeset(user_or_changeset, attrs)
        end
      end

  Remember to add `user: MyApp.Users.User` to your configuration.

  ## Configuration options

  * `:user_id_field` - the field to use for user id. This value defaults to
    `:email`, and the changeset will automatically validate it as an e-mail.

  ## Customize Pow fields

  Pow fields can be overridden if the field name and type matches:

      defmodule MyApp.Users.User do
        use Ecto.Schema
        use Pow.Ecto.Schema

        schema "users" do
          field :encrypted_password, :string
          field :password_hash, :string, source: :encrypted_password

          pow_user_fields()

          timestamps()
        end
      end

  The same holds true for associations:

      defmodule MyApp.Users.User do
        use Ecto.Schema
        use Pow.Ecto.Schema

        @pow_assocs {:belongs_to, :invited_by, __MODULE__}
        @pow_assocs {:has_many, :invited, __MODULE__}

        schema "users" do
          belongs_to :invited_by, __MODULE__, foreign_key: :user_id

          pow_user_fields()

          timestamps()
        end
      end

  ## Customize Pow changeset

  You can extract individual changeset methods to modify the changeset flow
  entirely. As an example, this is how you can remove the validation check for
  confirm password in the changeset method:

      defmodule MyApp.Users.User do
        use Ecto.Schema
        use Pow.Ecto.Schema

        import Pow.Ecto.Schema.Changeset, only: [new_password_changeset: 3]

        # ...

        def changeset(user_or_changeset, attrs) do
          user_or_changeset
          |> pow_user_id_field_changeset(attrs)
          |> pow_current_password_changeset(attrs)
          |> new_password_changeset(attrs, @pow_config)
        end
      end

  Note that the changeset methods in `Pow.Ecto.Schema.Changeset` require the
  Pow ecto module configuration that is passed to the
  `use Pow.Ecto.Schema, ...` call. This can be fetched by using the
  `@pow_config` module attribute.
  """
  alias Ecto.Changeset
  alias Pow.Config

  @callback changeset(Ecto.Schema.t() | Changeset.t(), map()) :: Changeset.t()
  @callback verify_password(Ecto.Schema.t(), binary()) :: boolean()

  @doc false
  defmacro __using__(config) do
    quote do
      @behaviour unquote(__MODULE__)
      @pow_config unquote(config)

      @spec changeset(Ecto.Schema.t() | Changeset.t(), map()) :: Changeset.t()
      def changeset(user_or_changeset, attrs), do: pow_changeset(user_or_changeset, attrs)

      @spec verify_password(Ecto.Schema.t(), binary()) :: boolean()
      def verify_password(user, password), do: pow_verify_password(user, password)

      defoverridable unquote(__MODULE__)

      unquote(__MODULE__).__pow_methods__()
      unquote(__MODULE__).__register_fields__()
      unquote(__MODULE__).__register_assocs__()
      unquote(__MODULE__).__register_user_id_field__()
    end
  end

  @changeset_methods [:user_id_field_changeset, :password_changeset, :current_password_changeset]

  @doc false
  defmacro __pow_methods__ do
    quoted_changeset_methods =
      for method <- @changeset_methods do
        pow_method_name = String.to_atom("pow_#{method}")

        quote do
          @spec unquote(pow_method_name)(Ecto.Schema.t() | Changeset.t(), map()) :: Changeset.t()
          def unquote(pow_method_name)(user_or_changeset, attrs) do
            unquote(__MODULE__).Changeset.unquote(method)(user_or_changeset, attrs, @pow_config)
          end
        end
      end

    quote do
      import unquote(__MODULE__), only: [pow_user_fields: 0]

      @spec pow_changeset(Ecto.Schema.t() | Changeset.t(), map()) :: Changeset.t()
      def pow_changeset(user_or_changeset, attrs) do
        user_or_changeset
        |> pow_user_id_field_changeset(attrs)
        |> pow_current_password_changeset(attrs)
        |> pow_password_changeset(attrs)
      end

      unquote(quoted_changeset_methods)

      @spec pow_verify_password(Ecto.Schema.t(), binary()) :: boolean()
      def pow_verify_password(user, password) do
        unquote(__MODULE__).Changeset.verify_password(user, password, @pow_config)
      end
    end
  end

  @doc """
  A macro to add fields from the `@pow_fields` module attribute generated in
  `__using__/1`.

  The `@pow_fields` are populated by `Pow.Ecto.Schema.Fields.attrs/1`, and will
  have at minimum the following fields:

    * `:email` (if not changed with `:user_id_field` option)
    * `:password_hash`
    * `:current_password` (virtual)
    * `:password` (virtual)
    * `:confirm_password` (virtual)
  """
  defmacro pow_user_fields do
    quote do
      unquote(__MODULE__).__append_assocs__(@pow_assocs, @ecto_assocs)
      unquote(__MODULE__).__append_fields__(@pow_fields, @ecto_fields)
    end
  end

  defmacro __append_assocs__(assocs, ecto_assocs) do
    quote do
      unquote(assocs)
      |> unquote(__MODULE__).__filter_new_assocs__(unquote(ecto_assocs))
      |> Enum.each(fn
        {:belongs_to, name, queryable} ->
          belongs_to(name, queryable)

        {:belongs_to, name, queryable, defaults} ->
          belongs_to(name, queryable, defaults)

        {:has_many, name, queryable} ->
          has_many(name, queryable)

        {:has_many, name, queryable, defaults} ->
          has_many(name, queryable, defaults)
      end)
    end
  end

  @doc false
  def __filter_new_assocs__(assocs, existing_assocs) do
    Enum.reject(assocs, fn assoc ->
      Enum.any?(existing_assocs, &assocs_match?(elem(assoc, 0), elem(assoc, 1), &1))
    end)
  end

  defp assocs_match?(:has_many, name, {name, %Ecto.Association.Has{cardinality: :many}}), do: true
  defp assocs_match?(:belongs_to, name, {name, %Ecto.Association.BelongsTo{}}), do: true
  defp assocs_match?(_type, _name, _existing_assoc), do: false

  defmacro __append_fields__(fields, ecto_fields) do
    quote do
      unquote(fields)
      |> unquote(__MODULE__).__filter_new_fields__(unquote(ecto_fields))
      |> Enum.each(fn
        {name, type} ->
          field(name, type)

        {name, type, defaults} ->
          field(name, type, defaults)
      end)
    end
  end

  @doc false
  def __filter_new_fields__(fields, existing_fields) do
    Enum.filter(fields, &not Enum.member?(existing_fields, {elem(&1, 0), elem(&1, 1)}))
  end

  # TODO: Remove by 1.1.0
  @deprecated "No longer public method"
  def filter_new_fields(fields, existing_fields), do: __filter_new_fields__(fields, existing_fields)

  @doc false
  defmacro __register_fields__ do
    quote do
      Module.register_attribute(__MODULE__, :pow_fields, accumulate: true)

      for attr <- unquote(__MODULE__).Fields.attrs(@pow_config) do
        Module.put_attribute(__MODULE__, :pow_fields, attr)
      end
    end
  end

  @doc false
  defmacro __register_assocs__ do
    quote do
      Module.register_attribute(__MODULE__, :pow_assocs, accumulate: true)
    end
  end

  @doc false
  defmacro __register_user_id_field__ do
    quote do
      @user_id_field unquote(__MODULE__).user_id_field(@pow_config)
      def pow_user_id_field, do: @user_id_field
    end
  end

  @doc """
  Get user id field key from changeset or configuration.

  Defaults to `:email`.
  """
  @default_user_id_field :email
  @spec user_id_field(Changeset.t() | Config.t()) :: atom()
  def user_id_field(%Changeset{data: %user_mod{}}), do: user_mod.pow_user_id_field()
  def user_id_field(config) when is_list(config), do: Config.get(config, :user_id_field, @default_user_id_field)
  def user_id_field(_any), do: @default_user_id_field

  @doc """
  Normalizes the user id field.

  Keeps the user id field value case insensitive and removes leading and
  trailing whitespace.
  """
  @spec normalize_user_id_field_value(binary()) :: binary()
  def normalize_user_id_field_value(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  @doc false
  def __timestamp_for__(struct, column) do
    type = struct.__schema__(:type, column)

    __timestamp__(type)
  end

  @doc false
  def __timestamp__(:naive_datetime) do
    %{NaiveDateTime.utc_now() | microsecond: {0, 0}}
  end
  def __timestamp__(:naive_datetime_usec) do
    NaiveDateTime.utc_now()
  end
  def __timestamp__(:utc_datetime) do
    DateTime.from_unix!(System.system_time(:second), :second)
  end
  def __timestamp__(:utc_datetime_usec) do
    DateTime.from_unix!(System.system_time(:microsecond), :microsecond)
  end
  def __timestamp__(type) do
    type.from_unix!(System.system_time(:microsecond), :microsecond)
  end
end
