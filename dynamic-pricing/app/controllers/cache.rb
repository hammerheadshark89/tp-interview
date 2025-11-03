require 'set'

# make_cache_key constructs a cache key that uniquely identifies a request to the pricing API
# Changing this format will invalidate all existing cache entries.
def make_cache_key(period, hotel, room)
  "#{period}-#{hotel}-#{room}"
end

# Reference is a price that was returned by the pricing API, and its associated creation timestamp
# n.b. The timestamp is 
Reference = Struct.new(:price_id, :rate, :timestamp) do
  def to_proxy_api_response_json
    {
      rate: rate.to_s
    }.to_json
  end
end

# make_references_from_ai_response converts an AI API response into a list of references.
# |target_price_id| must be present in the response -- if it is missing, return an empty list
# (this indicates there is something wrong with the the AI API response, and we should trust it).
# If |target_price_id| is present, it will be the first element of the list.
def make_references_from_ai_response(target_price_id, fetch_time, response)
  target = nil
  others = []
  for rate in response['rates'] do
    ref = Reference.new(PriceId.new(rate['period'], rate['hotel'], rate['room']), rate['rate'], fetch_time)
    if target_price_id == ref.price_id
      target = ref
    else
      others.append(ref)
    end
  end
  if target
    return [target] + others
  end
  # Target price id not found in response, don't trust it
  nil
end

# This is a list of recent references, sorted by timestamp, oldest first. It is not thread-safe.
# The purpose of this list is to be able to identify candidates for refreshing, i.e. items in the
# cache that are either going to expire soon, or have recently expired.
class UnsafeReferenceList
  def initialize(max_age, refresh_candidate_age)
    @max_age = max_age
    @refresh_candidate_age = refresh_candidate_age
    @list = []
    @most_recent_timestamp = {}
  end
  
  # add adds a reference to the list, and removes any references that are older than @max_age.
  def add(ref)
    # Remove any references that are older than @max_age.
    while @list.length > 0 and @list[0].timestamp < @max_age.ago
      id = @list[0].price_id
      if @most_recent_timestamp[id] == @list[0].timestamp
        @most_recent_timestamp.delete(id)
        # If we are removing a duplicate reference, there is no need to modify most_recent_timestamp,
        # because the reference we are removing will be older.
      end
      @list.shift
    end
    @list.append(ref)
    @most_recent_timestamp[ref.price_id] = ref.timestamp
  end

  # get_refresh_candidates returns a list of up to |count| price_ids that are candidates for refreshing.
  # This does not modify the list.
  def get_refresh_candidates(count)
    puts "Getting refresh candidates for #{count} at #{Time.now}"
    ts = @refresh_candidate_age.ago
    upper = @list.bsearch_index { |r| r.timestamp > ts }
    if upper.nil? or upper == 0
      return []
    end
    # We want the index of the last reference that is *not younger* than @refresh_candidate_age.
    upper -= 1
    candidates = []
    upper.downto(0) do |i|
      ref = @list[i]
      # Only include a candidate that is the most recent one for its price_id.
      # This (1) avoids duplicate price_ids (only one can be the latest) and
      # (2) avoids fetching a price_id that has been fetched more recently than
      # @refresh_candidate_age.
      if @most_recent_timestamp[ref.price_id] == ref.timestamp
        puts "Adding candidate #{ref.price_id} at #{ref.timestamp}"
        candidates.append(ref.price_id)
      end
      if candidates.length >= count
        break
      end
    end
    return candidates
  end
end

# Cache is a thread-safe cache of references. It wraps Rails.cache and also provides candidates
# for refreshing in the event of a cache miss.
class Cache
  def initialize
    @lock = Mutex.new
    @by_timestamp = UnsafeReferenceList.new(Rails.configuration.x.pricing_reference_list_max_age, Rails.configuration.x.pricing_refresh_candidate_age)
  end

  # get_ref_or_refresh_candidates returns a tuple of (target_reference, refresh_candidates)
  # |target_reference| is the reference for the price_id if it is in the cache, otherwise nil.
  # |refresh_candidates| is a list of price_ids that are candidates for refreshing. It will be
  # empty if |target_reference| is not nil.
  def get_ref_or_refresh_candidates(price_id)
    @lock.synchronize do
      ref = Rails.cache.read(price_id.to_cache_key)
      if ref
        return [ref, []]
      end
      candidates = @by_timestamp.get_refresh_candidates(Rails.configuration.x.rate_api_max_requests - 1)
      return [nil, [price_id] + candidates]
    end
  end

  # set adds a list of references to the cache.
  def set(refs)
    @lock.synchronize do
      refs.each do |ref|
        @by_timestamp.add(ref)
        ttl = Rails.configuration.x.pricing_cache_duration - (Time.now - ref.timestamp)
        Rails.cache.write(ref.price_id.to_cache_key(), ref, expires_in: ttl)
      end
    end
  end
end
