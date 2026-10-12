return function(t, ctx)
	local RateLimiter = ctx.require(ctx.shared.Util.RateLimiter)

	t.test("allows a burst, then refuses", function()
		local limiter = RateLimiter.new({ Rate = 0.001, Burst = 3 })
		local player = {}
		t.expect(limiter:Allow(player) and limiter:Allow(player) and limiter:Allow(player), "burst of 3")
		t.expect(not limiter:Allow(player), "4th request refused")
	end)

	t.test("buckets are per player and can be removed", function()
		local limiter = RateLimiter.new({ Rate = 0.001, Burst = 1 })
		local a, b = {}, {}
		t.expect(limiter:Allow(a) and limiter:Allow(b), "independent buckets")
		t.expect(not limiter:Allow(a), "a is empty")
		limiter:Remove(a)
		t.expect(limiter:Allow(a), "a starts fresh after Remove")
	end)

	t.test("refills over time", function()
		local limiter = RateLimiter.new({ Rate = 1000, Burst = 1 })
		local player = {}
		t.expect(limiter:Allow(player), "first")
		local start = os.clock()
		while os.clock() - start < 0.005 do
			-- busy-wait 5 ms; 1000 tokens/s refills well over one token
		end
		t.expect(limiter:Allow(player), "refilled")
	end)
end
