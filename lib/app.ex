defmodule Relex.App do
  defstruct name: nil, version: nil, path: nil, app: nil, type: :permanent, code_path: []

  defmodule NotFound do
    defexception app: nil, message: ""
    def exception(e) do
      "Application #{inspect e.app} not found"
    end
  end

  def new(atom) when is_atom(atom), do: new(name: atom)
  def new({name, options}) when is_atom(name) do
    new(Keyword.merge([name: name], options))
  end
  def new(opts), do: struct(%__MODULE__{}, opts)

  def app(rec) do
    case rec do
      %__MODULE__{name: name, version: version, app: nil} ->
        key = {:app, {name, version}}
        case :ets.lookup(__MODULE__, key) do
          [{_, app}] -> app
          _ ->
            {:ok, [app]} = :file.consult(Path.join([path(rec),"ebin","#{name}.app"]))
            :ets.insert(__MODULE__, {key, app})
            app
        end
      %__MODULE__{app: app} ->
        app
    end
  end

  def path(rec) do
    case rec do
      %__MODULE__{version: version, name: name, code_path: code_path, path: nil} ->
        case :ets.lookup(__MODULE__, {:path, {name, version}}) do
          [{_, path}] ->
            path
          _ ->
            paths = code_path
            paths = Enum.filter(paths, fn(p) -> File.exists?(Path.join([p, "#{name}.app"])) end)
            paths = for path <- paths, do: Path.join(path, "..")
            result =
            case paths do
             [] -> raise NotFound, app: rec
             [path] ->
               if version_matches?(version, %__MODULE__{rec | path: path}) do
                 path
               else
                 raise NotFound, app: rec
               end
             _ ->
               apps =
               for path <- paths do
                 %__MODULE__{rec | path: path}
               end
               apps = Enum.filter(apps, fn(app) -> version_matches?(version, app) end)
               apps = Enum.sort(apps, fn(app1, app2) -> version(app2) <= version(app1) end)
               path(hd(apps))
            end
            :ets.insert(__MODULE__, {{:path, {name, version}}, result})
            result
        end
      %__MODULE__{path: path} ->
        path
    end
  end

  def version(rec) do
    keys(rec)[:vsn]
  end

  defp version_matches?(nil, _app), do: true
  defp version_matches?(version, app) do
    case version do
      %Regex{} -> Regex.match?(version, version(app))
      version when is_function(version) -> version.(app)
      _ -> to_string(version(app)) == to_string(version)
    end
  end

  def dependencies(rec) do
    for app <- (keys(rec)[:applications] || []) do
      %__MODULE__{new(app) | code_path: rec.code_path}
    end ++ included_applications(rec)
  end

  def included_applications(rec) do
    for app <- (keys(rec)[:included_applications] || []) do
      %__MODULE__{new(app) | code_path: rec.code_path}
    end
  end

  defp keys(rec) do
    {:application, _, opts} = app(rec)
    opts
  end

end

defimpl Inspect, for: Relex.App do
  def inspect(%Relex.App{name: name, version: version}, _opts) do
    version = case version do
      %Regex{} -> inspect(version)
      version when is_function(version) -> "<version checked by #{inspect(version)}>"
      _ -> nil
    end
    version = if nil?(version), do: "", else: "-#{version}"
    "#{name}#{version}"
  end
end