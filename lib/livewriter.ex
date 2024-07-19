defmodule Livewriter do
  alias Livebook.Notebook
  alias Livebook.Notebook.{Cell, Section}
  alias Livebook.LiveMarkdown
  require Logger
  require ExUnit.DocTest

  @section_directives [:markdown, :elixir, :erlang, :smartcell]

  def print!(%Notebook{} = notebook, opts \\ []) do
    case LiveMarkdown.notebook_to_livemd(notebook, opts) do
      {out, []} ->
        IO.puts(out)

      {_out, errors} ->
        raise ArgumentError, inspect(errors)
    end
  end

  defmacro livebook(opts \\ [], do: block) do
    blocks =
      case block do
        {:__block__, _meta, blocks} ->
          blocks

        _ ->
          [block]
      end

    opts = Keyword.validate!(opts, leading_comments: [], name: "Untitled notebook")

    {sections, setup} =
      Enum.reduce(blocks, {[], nil}, fn
        {:section, _, _} = node, {acc, stup} ->
          {[node | acc], stup}

        {:setup, _, _} = node, {acc, _stup} ->
          {acc, node}

        {directive, _, _}, acc when directive in @section_directives ->
          Logger.warning(
            "Directive #{inspect(directive)} appears outside a `:section` block and will be ignored."
          )

          acc

        {directive, _, _}, acc ->
          Logger.warning("Unknown directive #{inspect(directive)} found and will be ignored.")
          acc
      end)

    quote do
      %{
        Notebook.new()
        | leading_comments: unquote(opts[:leading_comments]),
          name: unquote(opts[:name]),
          sections: Enum.reverse(unquote(sections))
      }
      |> then(&if(unquote(setup), do: Map.put(&1, :setup_section, unquote(setup)), else: &1))
    end
  end

  defmacro setup(do: block) do
    quote do
      %{Section.new() | id: "setup-section", name: "Setup", cells: [elixir(do: unquote(block))]}
    end
  end

  defmacro section(opts \\ [], do: block) do
    opts = Keyword.validate!(opts, [:id, :fork, name: "Untitled Section"])

    blocks =
      case block do
        {:__block__, _meta, blocks} ->
          blocks

        _ ->
          [block]
      end

    cells =
      Enum.reduce(blocks, [], fn
        {directive, _, _} = node, acc when directive in @section_directives ->
          [node | acc]

        {:setup, _, _}, acc ->
          Logger.warning(
            "`:setup` block found inside `:section` block and will be ignored. `:setup` block must appear outside of a section."
          )

          acc

        {directive, _, _}, acc ->
          Logger.warning("Unknown directive #{inspect(directive)} found and will be ignored.")
          acc
      end)

    quote do
      %{
        Section.new()
        | name: unquote(opts[:name]),
          parent_id: unquote(opts[:fork]),
          cells: Enum.reverse(unquote(cells))
      }
      |> then(&if(unquote(opts[:id]), do: Map.put(&1, :id, unquote(opts[:id])), else: &1))
    end
  end

  defmacro code(opts \\ [], do: block) do
    {language, opts} = Keyword.pop(opts, :language, :elixir)
    opts = Keyword.validate!(opts, [:outputs])
    source = block |> Macro.to_string()

    outputs =
      case opts[:outputs] do
        nil ->
          []

        [] ->
          []

        output when is_binary(output) ->
          Macro.escape([{0, %{type: :terminal_text, text: output, chunk: false}}])

        output when is_list(output) ->
          unless Enum.all?(output, &is_binary/1) do
            raise ArgumentError, "elixir cell only accepts string outputs"
          end

          output
          |> Enum.with_index()
          |> Enum.map(fn out, index ->
            {index, %{type: :terminal_text, text: out, chunk: false}}
          end)
      end

    quote do
      %{
        Cell.Code.new()
        | source: unquote(source),
          outputs: unquote(outputs),
          language: unquote(language)
      }
    end
  end

  defmacro elixir(opts \\ [], do: block) do
    opts = opts ++ [language: :elixir]

    quote do
      code unquote(opts) do
        unquote(block)
      end
    end
  end

  defmacro erlang(opts \\ [], do: block) do
    opts = opts ++ [language: :erlang]

    quote do
      code unquote(opts) do
        unquote(block)
      end
    end
  end

  defmacro markdown(do: block) do
    quote do
      %{Cell.Markdown.new() | source: unquote(block)}
    end
  end

  defp prepare_doctests(modules) do
    regex = ~r/(?<module>(?:\w+\.)*\w+)\.(?<function>\w+)\/(?<arity>\d+)/

    doctests =
      for mod <- modules, reduce: [] do
        mods ->
          mods ++
            (ExUnit.DocTest.__doctests__(mod, [])
             |> Enum.flat_map(fn
               {name, test, _tags} ->
                 case Regex.named_captures(regex, name) do
                   %{"module" => _module, "function" => function_name, "arity" => arity} ->
                     {_ast, acc} =
                       test
                       |> Macro.prewalk([], fn
                         {_, [],
                          [
                            {:value, [], ExUnit.DocTest},
                            expected,
                            doctest_source,
                            last_expr,
                            expected_expr,
                            module,
                            file,
                            line
                          ]} = node,
                         acc ->
                           {node,
                            [
                              %{
                                name: function_name |> String.to_existing_atom(),
                                arity: arity |> String.to_integer(),
                                expected: expected,
                                doctest_source: doctest_source,
                                last_expr: last_expr,
                                expected_expr: expected_expr,
                                module: module,
                                file: file,
                                line: line
                              }
                              | acc
                            ]}

                         node, acc ->
                           {node, acc}
                       end)

                     acc
                 end

               nil ->
                 []
             end))
      end

    config = %ExDoc.Config{}

    config = %{
      config
      | annotations_for_docs: fn metadata ->
          metadata
          |> Map.drop([:arity, :module, :name, :kind])
          |> Enum.into([])
        end
    }

    {retrieved, _filtered} = ExDoc.Retriever.docs_from_modules(modules, config)

    for %ExDoc.ModuleNode{docs: docs, module: module} = modulenode <- retrieved do
      updated_docs =
        for %ExDoc.FunctionNode{arity: arity, name: function_name} = funcnode <- docs do
          doctests =
            Enum.filter(
              doctests,
              &match?(%{module: ^module, name: ^function_name, arity: ^arity}, &1)
            )

          Map.put(funcnode, :doctests, doctests)
        end

      Map.put(modulenode, :docs, updated_docs)
    end
  end

  defmacro from_docs(modules) do
    modules = Macro.expand_literals(modules, __CALLER__)

    pre_livebook =
      cond do
        is_list(modules) and Enum.all?(modules, &is_atom/1) ->
          prepare_doctests(modules)

        is_atom(modules) ->
          prepare_doctests([modules])

        true ->
          raise ArgumentError,
                "from_doctests only accepts a module name or a list of module names"
      end

    livebooks =
      for module <- pre_livebook do
        funcs =
          for func <- module.docs do
            doctests =
              for doctest <- func.doctests do
                quote do
                  elixir outputs: unquote(doctest.expected_expr) do
                    unquote(Code.string_to_quoted!(doctest.last_expr))
                  end
                end
              end

            quote do
              section name: unquote(func.id) do
                markdown do
                  unquote(func.source_doc["en"])
                end

                unquote_splicing(doctests)
              end
            end
          end

        quote do
          livebook do
            section name: unquote(module.title) do
              markdown do
                unquote(module.source_doc["en"])
              end
            end

            unquote_splicing(funcs)
          end
        end
      end

    quote do
      (unquote_splicing(livebooks))
    end
  end
end
