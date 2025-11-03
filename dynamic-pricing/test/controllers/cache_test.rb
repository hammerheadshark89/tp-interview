require "test_helper"

class CacheTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "should store and retrieve references" do
    cache = Cache.new
    
    ref = Reference.new(PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"), "12000", Time.now)
    cache.set([ref])
    
    result = cache.get_ref_or_refresh_candidates(
      PriceId.new("Summer", "FloatingPointResort", "SingletonRoom")
    )
    
    assert_not_nil result[0]
    assert_equal "12000", result[0].rate
  end
  
  test "should return nil for cache miss" do
    cache = Cache.new
    
    result = cache.get_ref_or_refresh_candidates(
      PriceId.new("Winter", "GitawayHotel", "BooleanTwin")
    )
    
    assert_nil result[0]
    assert_not_empty result[1]  # Should have one refresh candidate
    assert_equal [PriceId.new("Winter", "GitawayHotel", "BooleanTwin")], result[1]
  end
  
  test "should expire old references" do
    cache = Cache.new
    
    travel_to 10.minutes.ago do
      old_ref = Reference.new(PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"), "12000", Time.now)
      cache.set([old_ref])
    end
    
    result = cache.get_ref_or_refresh_candidates(
      PriceId.new("Summer", "FloatingPointResort", "SingletonRoom")
    )
    
    # Should be expired and return nil
    assert_nil result[0]
  end
end

class MakeReferencesFromAiResponseTest < ActiveSupport::TestCase
  test "target price id is first in response" do
    response = {
      "rates" => [
        { "period" => "Summer", "hotel" => "FloatingPointResort", "room" => "SingletonRoom", "rate" => "12000" },
        { "period" => "Summer", "hotel" => "FloatingPointResort", "room" => "BooleanTwin", "rate" => "14000" }
      ]
    }
    target_price_id = PriceId.new("Summer", "FloatingPointResort", "SingletonRoom")
    fetch_time = Time.now
    expected_references = [Reference.new(target_price_id, "12000", fetch_time),
                           Reference.new(PriceId.new("Summer", "FloatingPointResort", "BooleanTwin"), "14000", fetch_time)]
    
    references = make_references_from_ai_response(target_price_id, fetch_time, response)
    assert_equal expected_references, references
  end 
  
  test "target price id is second in response" do
    response = {
      "rates" => [
        { "period" => "Summer", "hotel" => "FloatingPointResort", "room" => "BooleanTwin", "rate" => "14000" },
        { "period" => "Summer", "hotel" => "FloatingPointResort", "room" => "SingletonRoom", "rate" => "12000" }
      ]
    }
    target_price_id = PriceId.new("Summer", "FloatingPointResort", "SingletonRoom")
    fetch_time = Time.now
    expected_references = [Reference.new(target_price_id, "12000", fetch_time),
                           Reference.new(PriceId.new("Summer", "FloatingPointResort", "BooleanTwin"), "14000", fetch_time)]

    references = make_references_from_ai_response(target_price_id, fetch_time, response)
    assert_equal expected_references, references
  end

  test "target price id is not present in response" do
    response = {
      "rates" => [
        { "period" => "Summer", "hotel" => "FloatingPointResort", "room" => "BooleanTwin", "rate" => "14000" },
      ]
    }
    target_price_id = PriceId.new("Summer", "FloatingPointResort", "SingletonRoom")
    fetch_time = Time.now
    references = make_references_from_ai_response(target_price_id, fetch_time, response)
    assert_nil references
  end
end

class UnsafeReferenceListTest < ActiveSupport::TestCase
  setup do
    @list = UnsafeReferenceList.new(10.minutes, 5.minute)
    @now = Time.now
    travel_to @now do
      @list.add(Reference.new(PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"), "12000", @now - 9.minutes))
      @list.add(Reference.new(PriceId.new("Summer", "FloatingPointResort", "BooleanTwin"), "14000", @now - 7.minutes))
      @list.add(Reference.new(PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"), "12000", @now - 6.minutes))
      @list.add(Reference.new(PriceId.new("Summer", "FloatingPointResort", "RestfulKing"), "16000", @now - 4.minutes))
      @list.add(Reference.new(PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"), "12000", @now - 2.minutes))
    end
  end

  test "add a reference and remove one old reference" do
    travel_to @now + 2.minutes do
      # Summer FloatingPointResort SingletonRoom 12000 11 minutes ago
      # Summer FloatingPointResort BooleanTwin 14000 9 minutes ago
      # Summer FloatingPointResort SingletonRoom 12000 8 minutes ago
      # Summer FloatingPointResort RestfulKing 16000 6 minutes ago
      # Summer FloatingPointResort SingletonRoom 12000 4 minutes ago
      @list.add(Reference.new(PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"), "12000", Time.now))
      assert_equal [PriceId.new("Summer", "FloatingPointResort", "RestfulKing"),
                    PriceId.new("Summer", "FloatingPointResort", "BooleanTwin")].to_set,
                    @list.get_refresh_candidates(3).to_set
    end
  end

  test "add a reference and remove two old references" do
    travel_to @now + 3.minutes + 30.seconds do
      # Summer FloatingPointResort SingletonRoom 12000 12.5 minutes ago
      # Summer FloatingPointResort BooleanTwin 14000 10.5 minutes ago
      # Summer FloatingPointResort SingletonRoom 12000 9.5 minutes ago
      # Summer FloatingPointResort RestfulKing 16000 7.5 minutes ago
      # Summer FloatingPointResort SingletonRoom 12000 5.5 minutes ago
      @list.add(Reference.new(PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"), "12000", Time.now))
      assert_equal [PriceId.new("Summer", "FloatingPointResort", "RestfulKing")].to_set,
                    @list.get_refresh_candidates(3).to_set
    end
  end

  test "empty list" do
    list = UnsafeReferenceList.new(10.minutes, 5.minute)
    assert_equal [], list.get_refresh_candidates(3)
    list.add(Reference.new(PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"), "12000", Time.now - 1.minutes))
    assert_equal Set.new, list.get_refresh_candidates(3).to_set
  end
end