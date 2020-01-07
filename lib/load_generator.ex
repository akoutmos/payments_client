defmodule PaymentsClient.LoadGenerator do
  alias PaymentsClient.{MockAPI, RateLimiter}

  def create_requests(num_requests) do
    1..num_requests
    |> Enum.each(fn _ ->
      {request_handler, response_handler} = generate_random_request()

      RateLimiter.make_request(request_handler, response_handler)
    end)
  end

  defp generate_random_request do
    case Enum.random(1..3) do
      1 ->
        {
          {MockAPI, :create_payment, [123, %{cc_number: 1_234_567_890, exp_date: "01/28"}]},
          {MockAPI, :handle_create_payment}
        }

      2 ->
        {
          {MockAPI, :delete_payment, [123, 456]},
          {MockAPI, :handle_delete_payment}
        }

      3 ->
        {
          {MockAPI, :charge_payment, [123, 456, 10.00]},
          {MockAPI, :handle_charge_payment}
        }
    end
  end
end
