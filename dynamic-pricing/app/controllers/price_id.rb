# PriceId is a struct that represents a (period, hotel, room) combination, corresponding to
# a request to the pricing AI API.
# (This is not the best name, but it will do for now).
PriceId = Struct.new(:period, :hotel, :room) do
  def to_cache_key
    make_cache_key(period, hotel, room)
  end
end