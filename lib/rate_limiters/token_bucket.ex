defmodule PaymentsClient.RateLimiters.TokenBucket do
  use GenServer

  require Logger

  alias PaymentsClient.RateLimiter

  @behaviour RateLimiter

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %{
      requests_per_timeframe: opts.timeframe_max_requests,
      available_tokens: opts.timeframe_max_requests,
      token_refresh_rate:
        RateLimiter.calculate_refresh_rate(opts.timeframe_max_requests, opts.timeframe, opts.timeframe_units),
      request_queue: :queue.new(),
      request_queue_size: 0,
      send_after_ref: nil
    }

    {:ok, state, {:continue, :initial_timer}}
  end

  # ---------------- Client facing function ----------------

  @impl RateLimiter
  def make_request(request_handler, response_handler) do
    GenServer.cast(__MODULE__, {:enqueue_request, request_handler, response_handler})
  end

  # ---------------- Server Callbacks ----------------

  @impl true
  def handle_continue(:initial_timer, state) do
    {:noreply, %{state | send_after_ref: schedule_timer(state.token_refresh_rate)}}
  end

  @impl true
  # No tokens available...enqueue the request
  def handle_cast({:enqueue_request, request_handler, response_handler}, %{available_tokens: 0} = state) do
    updated_queue = :queue.in({request_handler, response_handler}, state.request_queue)
    new_queue_size = state.request_queue_size + 1

    {:noreply, %{state | request_queue: updated_queue, request_queue_size: new_queue_size}}
  end

  # Tokens available...use one of the tokens and perform the operation immediately
  def handle_cast({:enqueue_request, request_handler, response_handler}, state) do
    async_task_request(request_handler, response_handler)

    {:noreply, %{state | available_tokens: state.available_tokens - 1}}
  end

  @impl true
  def handle_info(:token_refresh, %{request_queue_size: 0} = state) do
    # No work to do as the queue size is zero...schedule the next timer and increase the token count
    token_count =
      if state.available_tokens < state.requests_per_timeframe do
        state.available_tokens + 1
      else
        state.available_tokens
      end

    {:noreply,
     %{
       state
       | send_after_ref: schedule_timer(state.token_refresh_rate),
         available_tokens: token_count
     }}
  end

  def handle_info(:token_refresh, state) do
    {{:value, {request_handler, response_handler}}, new_request_queue} = :queue.out(state.request_queue)

    async_task_request(request_handler, response_handler)

    {:noreply,
     %{
       state
       | request_queue: new_request_queue,
         send_after_ref: schedule_timer(state.token_refresh_rate),
         request_queue_size: state.request_queue_size - 1
     }}
  end

  def handle_info({ref, _result}, state) do
    Process.demonitor(ref, [:flush])

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp async_task_request(request_handler, response_handler) do
    start_message = "Request started #{NaiveDateTime.utc_now()}"

    Task.Supervisor.async_nolink(RateLimiter.TaskSupervisor, fn ->
      {req_module, req_function, req_args} = request_handler
      {resp_module, resp_function} = response_handler

      response = apply(req_module, req_function, req_args)
      apply(resp_module, resp_function, [response])

      Logger.info("#{start_message}\nRequest completed #{NaiveDateTime.utc_now()}")
    end)
  end

  defp schedule_timer(token_refresh_rate) do
    Process.send_after(self(), :token_refresh, token_refresh_rate)
  end
end
