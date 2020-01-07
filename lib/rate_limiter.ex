defmodule PaymentsClient.RateLimiter do
  @callback make_request(request_handler :: tuple(), response_handler :: tuple()) :: :ok

  def make_request(request_handler, response_handler) do
    get_rate_limiter().make_request(request_handler, response_handler)
  end

  def get_rate_limiter, do: get_rate_limiter_config(:rate_limiter)
  def get_requests_per_timeframe, do: get_rate_limiter_config(:timeframe_max_requests)
  def get_timeframe_unit, do: get_rate_limiter_config(:timeframe_units)
  def get_timeframe, do: get_rate_limiter_config(:timeframe)

  def calculate_refresh_rate(num_requests, time, timeframe_units) do
    floor(convert_time_to_milliseconds(timeframe_units, time) / num_requests)
  end

  def convert_time_to_milliseconds(:hours, time), do: :timer.hours(time)
  def convert_time_to_milliseconds(:minutes, time), do: :timer.minutes(time)
  def convert_time_to_milliseconds(:seconds, time), do: :timer.seconds(time)
  def convert_time_to_milliseconds(:milliseconds, milliseconds), do: milliseconds

  defp get_rate_limiter_config(config) do
    :payments_client
    |> Application.get_env(RateLimiter)
    |> Keyword.get(config)
  end
end
