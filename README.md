# Warnings

I am not a Ruby programmer and I have never used Ruby before this assignment. I scanned through the documentation and used Chatgpt to get background knowledge (and also see "How I used AI" below). Apologies if my usage of Ruby or Rails is idiosyncratic.

I have also used `puts` to print debugging information. For a production service, I would use a JSON logging library that integrates nicely with AWS Cloudwatch etc.

# How to run it

1. `docker run -p 8080:8080 tripladev/ratapi` to start AI server
2. In a different terminal: `docker build -t interview-app .` to build the proxy server
3. `docker run -p 3000:3000 -v $(pwd):/rails interview-app` to run the proxy server

# Overview of solution

**Terminology**: A triple of period, hotel, room is a price ID. The AI server returns prices for price IDs. Price IDs are used as keys for the cache.

The pricing proxy maintains a cache of price quotes. This serves two purposes:
* Avoid lookups to the AI server by serving out of the cache when possible (uses `Rails.cache`)
* Identifies additional price IDs that may be useful to fetch from the AI server. This is motivated by the fact that the API for the AI server allows fetching more than one price ID -- see below for discussion of this. This is code I wrote.

## Rate validity

Room rates are only valid for 5 minutes. The proxy server takes the time it *sent the request to the AI server* as the start of the 5-minute validity window. This is pessimistic (e.g. if the network is slow, the time for the request to reach the AI server is not small), but easy to calculate. The AI server could return the "expires at" time itself to give a more accurate start to the validity window (assuming clocks are accurate enough! -- a reasonable assumption).

## API usage limits

I don't enforce the 1000 requests/day limit on the token -- I assume, but haven't verified, that the AI server returns an error in that case. It would be straightforward to add a tracker, and return an error, if necessary (although it would have to persist across proxy server restarts to be reliable).

Fundamentally, there is no guarantee that the proxy server can serve 10,000 requests while respecting the usage limit. Assuming (reasonably) that we can't predict the future, it is trivial to construct a pattern of incoming requests that will defeat any caching scheme: there are 288 (86400 / 300) 5-minute periods in a day, so if we have 4 unique price IDs, we can construct a pattern of 287 requests for each ID that results in no cache hits.

We can prefetch whenever we have a cache miss (see below), but with a sufficiently large number of unique price IDs, we can similarly defeat a prefetching scheme -- unless we are able to prefetch all possible price IDs!

We need to achieve a cache hit rate of 90% to be able to serve 10,000 requests per day with the available token limit. Prefetching improves the hit-rate, but doesn't guarantee that we can achieve it.

# Prefetching rates for price IDs

## AI server API

The proxy server and AI server APIs are mismatched: the proxy server allows a client to fetch a rate for only 1 price ID, but the AI server allows a client to fetch rates for an array of price IDs. I've tested sending up to 1000 price IDs in one request.

* It's odd that there is such a high upper limit! Generally AIs are priced by the amount of work they do, so the  cost (and token consumption) of a request for 1000 price IDs should be >> cost of 1 price ID. The rate-api documentation doesn't mention the cost of requests for multiple price IDs.
* On the other hand, this API style is a signal that prefetching is supposed to be an option -- i.e. if the proxy gets a cache miss for price ID `x`, don't just fetch the rate for `x`, also *prefetch* some other price IDs that are likely to be useful in future. This should improve the cache hit rate.
* We could cheat and abuse the API. In the current setup, which is a toy example, there are only 36 unique price IDs, so we could trivially keep the cache warm at the cost of only 288 AI server requests per day! I have compromised and used a config parameter `config.x.rate_api_max_requests` (which I set to 10, but could be higher/lower) for how many price IDs are allowed to be sent in one AI server request.

## What to prefetch?

We don't know the future pattern of requests, but I have used the common heuristic that you can expect an object that was last referenced N seconds in the past to be next referenced N seconds in the future -- assuming references to a given object are a Poisson process (this is probably not true in this application, but this assumption is better than nothing).

I've augmented the `Cache` class (which is a wrapper around `Rails.cache` so that, on a cache miss, it gives a list of `config.x.rate_api_max_requests` price IDs to fetch (including the one that missed the cache). The selection criterion is based on the above heuristic:
* Don't prefetch (refetch, in this case) anything younger than 2.5 minutes in the cache
* Prefetch price IDs older than 2.5 minutes, in descending order of age.
Given enough time and a trace of live traffic to test with, I would evaluate this experimentally.

The `Cache` class keeps track of candidate price IDs with an array ordered by reference time, and a map of the most recent reference for each price ID. The reference time array may have duplicates, but these can be detected using the "most recent reference" map. The size of the array will not be excessive (assuming in the vicinity of 10,000 references per day). I could remove duplicates more aggressively, but that would require either:
* Deleting from the middle of the array (`O(n)`) or
* A different data structure (e.g. Binary tree, `O(log(n))`) that has cheaper deletions. This would complicate the code for walking the candidate list (tree traversal), so I have not done it for this assignment.

# Evaluation

I've tested with unit tests and an integration test in `integration/integration.py` (written in Python for my convenience). I haven't checked the results of the integration test thoroughly, but the proxy server can handle the request stream.

The `development.rb` environment sets `config.x.pricing_cache_duration` to 2 minutes, not 5 minutes, so that it doesn't take so long to run a test with hundreds of requests and interesting caching behaviour.

Given more time, I would augment the proxy server to return summary statistics (cache hit rate etc) and then load test with a realistic trace of requests. This would give information about how the prefetching algorithm is performing and how to improve it.

# Use of AI

* I used Chatgpt to familiarize myself with Ruby, by asking questions to understand the Ruby syntax, "philosophy" and any conceptual issues I was having trouble with.

* I used Cursor for editing, with Claude AI to explore the code base and get suggestions for what APIs to use, or the idiomatic ways to get things done, and also for debugging suggestions. I asked it to look at my code, but I didn't let it edit it -- I wanted to try it out for myself.

* I used Claude AI to help me write the integration test (i.e. it wrote code and I modified it).
