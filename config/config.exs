import Config

config :payments_client, RateLimiter,
  rate_limiter: PaymentsClient.RateLimiters.LeakyBucket,
  timeframe_max_requests: 60,
  timeframe_units: :seconds,
  timeframe: 60
