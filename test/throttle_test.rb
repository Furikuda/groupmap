# frozen_string_literal: true

require_relative 'test_helper'

class ThrottleTest < Minitest::Test
  def throttle(min_interval: 3, per_hour: 3)
    GroupMap::Throttle.new(min_interval: min_interval, per_hour: per_hour)
  end

  def test_first_hit_is_allowed
    assert_nil throttle.hit('ip', now: 0.0)
  end

  def test_enforces_min_interval_and_reports_wait
    t = throttle
    t.hit('ip', now: 100.0)

    assert_equal 2, t.hit('ip', now: 101.0)
    assert_nil t.hit('ip', now: 103.0)
  end

  def test_wait_is_rounded_up_to_at_least_one_second
    t = throttle
    t.hit('ip', now: 0.0)

    assert_equal 1, t.hit('ip', now: 2.9)
  end

  def test_rejected_hits_are_not_recorded
    t = throttle
    t.hit('ip', now: 0.0)
    5.times { t.hit('ip', now: 1.0) }

    assert_nil t.hit('ip', now: 3.0), 'rejected attempts must not extend the wait'
  end

  def test_hourly_cap_uses_a_sliding_window
    t = throttle
    [0, 3, 6].each { |s| assert_nil t.hit('ip', now: s.to_f) }

    assert_equal 3591, t.hit('ip', now: 9.0)
    assert_nil t.hit('ip', now: 3601.0), 'oldest hit has left the window'
    assert_equal 2, t.hit('ip', now: 3602.0)
  end

  def test_keys_are_independent
    t = throttle
    t.hit('a', now: 0.0)

    assert_nil t.hit('b', now: 0.5)
    refute_nil t.hit('a', now: 0.5)
  end

  def test_idle_keys_are_pruned
    t = throttle(min_interval: 0, per_hour: 10_000)
    999.times { |i| t.hit("ip#{i}", now: 0.0) }
    t.hit('late', now: 4000.0) # 1000th call triggers pruning

    keys = t.instance_variable_get(:@hits).keys

    assert_equal ['late'], keys
  end

  def test_thread_safety_under_contention
    t = throttle(min_interval: 0, per_hour: 50)
    allowed = Queue.new
    Array.new(8) { Thread.new { 20.times { allowed << 1 if t.hit('ip', now: 1.0).nil? } } }.each(&:join)

    assert_equal 50, allowed.size
  end
end
