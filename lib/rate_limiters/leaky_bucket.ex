defmodule PaymentsClient.RateLimiters.LeakyBucket do
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
      request_queue: :queue.new(),
      request_queue_size: 0,
      request_queue_poll_rate:
        RateLimiter.calculate_refresh_rate(opts.timeframe_max_requests, opts.timeframe, opts.timeframe_units),
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
    {:noreply, %{state | send_after_ref: schedule_timer(state.request_queue_poll_rate)}}
  end

  @impl true
  def handle_cast({:enqueue_request, request_handler, response_handler}, state) do
    updated_queue = :queue.in({request_handler, response_handler}, state.request_queue)
    new_queue_size = state.request_queue_size + 1

    {:noreply, %{state | request_queue: updated_queue, request_queue_size: new_queue_size}}
  end

  @impl true
  def handle_info(:pop_from_request_queue, %{request_queue_size: 0} = state) do
    # No work to do as the queue size is zero...schedule the next timer
    {:noreply, %{state | send_after_ref: schedule_timer(state.request_queue_poll_rate)}}
  end

  def handle_info(:pop_from_request_queue, state) do
    {{:value, {request_handler, response_handler}}, new_request_queue} = :queue.out(state.request_queue)
    start_message = "Request started #{NaiveDateTime.utc_now()}"

    Task.Supervisor.async_nolink(RateLimiter.TaskSupervisor, fn ->
      {req_module, req_function, req_args} = request_handler
      {resp_module, resp_function} = response_handler

      response = apply(req_module, req_function, req_args)
      apply(resp_module, resp_function, [response])

      Logger.info("#{start_message}\nRequest completed #{NaiveDateTime.utc_now()}")
    end)

    {:noreply,
     %{
       state
       | request_queue: new_request_queue,
         send_after_ref: schedule_timer(state.request_queue_poll_rate),
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

  defp schedule_timer(queue_poll_rate) do
    Process.send_after(self(), :pop_from_request_queue, queue_poll_rate)
  end
end
