defmodule Behaviour do
  @moduledoc """
  A convenience module for defining behaviours.
  Behaviours can be referenced by other modules
  in order to ensure they implement the proper
  callbacks.

  For example, you can specify the `URI.Parser`
  behaviour as follow:

      defmodule URI.Parser do
        use Behaviour

        @doc "Parses the given URL"
        defcallback parse(uri_info :: URI.Info.t), do: URI.Info.t

        @doc "Defines a default port"
        defcallback default_port(), do: integer
      end

  And then a specific module may use it as:

      defmodule URI.HTTP do
        @behaviour URI.Parser
        def default_port(), do: 80
        def parse(info), do: info
      end

  In case the behaviour changes or URI.HTTP does
  not implement one of the callbacks, a warning
  will be raised.

  ## Implementation

  Behaviours since Erlang R15 must be defined via
  `@callback` attributes. `defcallback` is a simple
  mechanism that defines the `@callback` attribute
  according to the type specification and also allows
  docs and defines a custom function signature.

  The callbacks and their documentation can be retrieved
  via the `__behaviour__` callback function.
  """

  @doc """
  Defines a callback according to the given type specification.
  """
  defmacro defcallback(fun, do: return) do
    { name, args } = :elixir_clauses.extract_args(fun)
    arity = length(args)

    Enum.each args, (function do
      { :::, _, [left, right] } ->
        ensure_not_default(left)
        ensure_not_default(right)
        left
      other ->
        ensure_not_default(other)
        other
    end)

    quote do
      @callback unquote(name)(unquote_splicing(args)), do: unquote(return)
      Behaviour.store_docs __MODULE__, unquote(__CALLER__.line), unquote(name), unquote(arity)
    end
  end

  defp ensure_not_default({ ://, _, [_, _] }) do
    raise ArgumentError, message: "default arguments // not supported in defcallback"
  end

  defp ensure_not_default(_), do: :ok

  @doc false
  def store_docs(module, line, name, arity) do
    doc = Module.get_attribute module, :doc
    Module.delete_attribute module, :doc
    Module.put_attribute module, :__behaviour_docs, { { name, arity }, line, doc }
  end

  @doc false
  defmacro defcallback(fun) do
    IO.write "[WARNING] Behaviour.defcallback/1 is deprecated, please use defcallback/2 instead\n#{Exception.formatted_stacktrace}"

    { name, args } = :elixir_clauses.extract_args(fun)
    length = length(args)

    { args, defaults } = Enum.map_reduce(args, 0, function do
      { ://, _, [expr, _] }, acc ->
        { expr, acc + 1 }
      expr, acc ->
        { expr, acc }
    end)

    attributes = Enum.map (length - defaults)..length, fn(i) ->
      quote do
        @__behaviour_callbacks { unquote(name), unquote(i) }
      end
    end

    quote do
      __block__ unquote(attributes)
      def unquote(name)(unquote_splicing(args))
    end
  end

  @doc false
  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :__behaviour_callbacks, accumulate: true)
      Module.register_attribute(__MODULE__, :__behaviour_docs, accumulate: true)
      @before_compile unquote(__MODULE__)
      import unquote(__MODULE__)
    end
  end

  @doc false
  defmacro __before_compile__(_) do
    quote do
      if @__behaviour_callbacks != [] do
        @doc false
        def behaviour_info(:callbacks) do
          @__behaviour_callbacks
        end
      end

      @doc false
      def __behaviour__(:callbacks) do
        __MODULE__.behaviour_info(:callbacks)
      end

      def __behaviour__(:docs) do
        @__behaviour_docs
      end
    end
  end
end