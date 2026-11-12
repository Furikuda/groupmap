# frozen_string_literal: true

module GroupMap
  # In-memory, per-key (client IP) sliding-window rate limiter.
  # State lives in process memory: it resets on restart and is not shared
  # between processes, which is fine for a single Puma process.
  class Throttle
    HOUR = 3600.0

    def initialize(min_interval:, per_hour:)
      @min_interval = min_interval.to_f
      @per_hour = per_hour.to_i
      @hits = Hash.new { |h, k| h[k] = [] } # key -> monotonic timestamps, oldest first
      @mutex = Mutex.new
      @calls = 0
    end

    # Records a hit and returns nil when allowed, otherwise the number of
    # seconds (Integer, >= 1) the caller has to wait. Rejected hits are not recorded.
    def hit(key, now: Process.clock_gettime(Process::CLOCK_MONOTONIC))
      @mutex.synchronize do
        prune(now)
        times = @hits[key]
        times.shift while times.any? && times.first <= now - HOUR

        wait = wait_time(times, now)
        return wait.ceil.clamp(1..) if wait.positive?

        times << now
        nil
      end
    end

    private

    def wait_time(times, now)
      waits = []
      waits << (times.last + @min_interval - now) if times.any?
      waits << (times[-@per_hour] + HOUR - now) if times.size >= @per_hour
      waits.max || 0
    end

    # Drop idle keys now and then so memory stays bounded.
    def prune(now)
      @calls += 1
      return unless (@calls % 1000).zero?

      @hits.delete_if { |_, times| times.empty? || times.last <= now - HOUR }
    end
  end
end
