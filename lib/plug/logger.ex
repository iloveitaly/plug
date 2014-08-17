defmodule Plug.Logger do
  @moduledoc """
  A plug for logging basic request information. 
  
  To use it, just plug it into the desired module. Currently it
  does not expect any option during initialization.

  ## Request ID

  This plug generates a `:request_id` metadata that can be used
  to identify requests in production. In order to log the request_id,
  you need to configure your logger backends to include it as part
  of the metadata:

      config :logger, :console, metadata: [:request_id]

  It is recommended to include this metadata in your production
  configuration file.

  The request id can be received as part of the request in the header
  field `x-request-id` and it will be included in the response with the
  same name.

  If you plan on sending your own request ids they must follow the
  following format:

    1. Be greater than 20 characters
    2. Be less than 200 characters
    3. Consist of ASCII letters, digits, or the characters +, /, =, and -

  If we receive an invalid request id we will generate a new one.
  """

  require Logger
  alias Plug.Conn
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _config) do
    request_id = external_request_id(conn) || generate_request_id()
    Logger.metadata(request_id: request_id)

    path = path_to_iodata(conn.path_info)
    Logger.info [conn.method, ?\s, path]

    before_time = :os.timestamp()
    Conn.register_before_send(conn, fn (conn) -> 
      after_time = :os.timestamp()
      diff = :timer.now_diff(after_time, before_time)

      resp_time = formatted_diff(diff)
      type = connection_type(conn)
      Logger.info [type, ?\s, Integer.to_string(conn.status), ?\s, "in", ?\s, resp_time]

      Conn.put_resp_header(conn, "x-request-id", request_id)
    end)
  end

  defp generate_request_id, do: :crypto.rand_bytes(15) |> Base.encode64

  defp formatted_diff(diff) do
    if diff > 1000 do
      [Integer.to_string(div(diff, 100)), "ms"]
    else
      [Integer.to_string(diff), "µs"]
    end
  end

  defp connection_type(%{state: :chunked}), do: "Chunked"
  defp connection_type(_), do: "Sent"

  defp path_to_iodata(path), do: Enum.reduce(path, [], fn(i, acc) -> [acc, ?/, i] end)

  defp valid_request_id?(s) do
    byte_size(s) in 20..200 and valid_base64?(s)
  end

  defp valid_base64?(<<h, t::binary>>)
      when h in ?a..?z
      when h in ?A..?Z
      when h in ?0..?9
      when h in '+=/-',
      do: valid_base64?(t)

  defp valid_base64?(<<>>),
    do: true

  defp valid_base64?(_),
    do: false

  defp external_request_id(conn) do
    case Conn.get_req_header(conn, "x-request-id") do
      []      -> nil
      [val|_] -> valid_request_id?(val) and val
    end
  end
end
