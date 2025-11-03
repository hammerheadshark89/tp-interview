require "test_helper"
require "minitest/mock"
require_relative '../../app/controllers/cache'
require_relative '../../app/controllers/price_id'

class PricingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_cache = PricingController.class_variable_get(:@@cache)
  end

  teardown do
    PricingController.class_variable_set(:@@cache, @original_cache)
  end
  
  test "should get pricing with cache hit" do
    mock_cache = Minitest::Mock.new
    mock_ref = Reference.new(PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"), 12000, Time.now)
    # cache hit
    mock_cache.expect(:get_ref_or_refresh_candidates, [mock_ref, []], [PriceId.new("Summer", "FloatingPointResort", "SingletonRoom")])
    PricingController.class_variable_set(:@@cache, mock_cache)

    get pricing_url, params: {
      period: "Summer",
      hotel: "FloatingPointResort",
      room: "SingletonRoom"
    }

    assert_response :success
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_equal "12000", json_response["rate"]
    mock_cache.verify
  end

  test "should get pricing with cache miss" do
    mock_ai_api_response_body = {
      "rates" => [
        {
          "period" => "Summer",
          "hotel" => "FloatingPointResort",
          "room" => "BooleanTwin",
          "rate" => "16000"
        },
        {
          "period" => "Summer",
          "hotel" => "FloatingPointResort",
          "room" => "SingletonRoom",
          "rate" => "12000"
        },
        {
          "period" => "Summer",
          "hotel" => "FloatingPointResort",
          "room" => "RestfulKing",
          "rate" => "18000"
        }
      ]
    }
    mock_ai_api_response = Struct.new(:success?, :body, :status).new(true, mock_ai_api_response_body, 200)
    
    mock_cache = Minitest::Mock.new
    # cache miss
    mock_cache.expect(:get_ref_or_refresh_candidates,
                      [nil, [PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"),
                             PriceId.new("Summer", "FloatingPointResort", "BooleanTwin"),
                             PriceId.new("Summer", "FloatingPointResort", "RestfulKing")]],
                      [PriceId.new("Summer", "FloatingPointResort", "SingletonRoom")])
    mock_cache.expect(:set, nil, [make_references_from_ai_response(PriceId.new("Summer", "FloatingPointResort", "SingletonRoom"), Time.parse("2025-01-01 12:00:00 UTC"), mock_ai_api_response_body)])
    PricingController.class_variable_set(:@@cache, mock_cache)
    
    AiApi.stub(:call, mock_ai_api_response) do
      travel_to Time.parse("2025-01-01 12:00:00 UTC") do
        get pricing_url, params: {
          period: "Summer",
          hotel: "FloatingPointResort",
          room: "SingletonRoom"
        }
        assert_response :success
        assert_equal "application/json", @response.media_type
        json_response = JSON.parse(@response.body)
        assert_equal "12000", json_response["rate"]
        mock_cache.verify
      end
    end
  end

  test "should handle AI API HTTP error" do
    mock_ai_api_response = Struct.new(:success?, :body, :status).new(false, { "error" => "Internal server error" }, 500)
    
    AiApi.stub(:call, mock_ai_api_response) do
        get pricing_url, params: {
          period: "Summer",
          hotel: "FloatingPointResort",
          room: "SingletonRoom"
        }
        assert_response :internal_server_error
        assert_equal "application/json", @response.media_type
        json_response = JSON.parse(@response.body)
        assert_includes json_response["error"], "Failed to get pricing: 500 {\"error\"=>\"Internal server error\"}"
    end
  end

  test "should handle AI API timeout" do
    AiApi.stub :call, -> (body) { raise Faraday::TimeoutError.new('timeout') } do
      get pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }
      
      assert_response :internal_server_error
      assert_equal "application/json", @response.media_type
      json_response = JSON.parse(@response.body)
      assert_includes json_response["error"], "timeout"
    end
  end

  test "should handle AI API invalid response" do
    mock_ai_api_response_body = {
      "rates" => [
        # The target price id is not present in the response
        {
          "period" => "Summer",
          "hotel" => "FloatingPointResort",
          "room" => "BooleanTwin",
          "rate" => "16000"
        }
      ]
    }
    mock_ai_api_response = Struct.new(:success?, :body, :status).new(true, mock_ai_api_response_body, 200)
    
    mock_cache = Minitest::Mock.new
    # cache miss
    mock_cache.expect(:get_ref_or_refresh_candidates, [nil, [PriceId.new("Summer", "FloatingPointResort", "SingletonRoom")]], [PriceId.new("Summer", "FloatingPointResort", "SingletonRoom")])
    PricingController.class_variable_set(:@@cache, mock_cache)
    
    AiApi.stub(:call, mock_ai_api_response) do
      get pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }
      assert_response :internal_server_error
      assert_equal "application/json", @response.media_type
      json_response = JSON.parse(@response.body)
      assert_includes json_response["error"], "Failed to get pricing: requested ID is missing from response body"
      mock_cache.verify
    end
  end

  test "should return error without any parameters" do
    get pricing_url

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Missing required parameters"
  end

  test "should handle empty parameters" do
    get pricing_url, params: {
      period: "",
      hotel: "",
      room: ""
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Missing required parameters"
  end

  test "should reject invalid period" do
    get pricing_url, params: {
      period: "summer-2024",
      hotel: "FloatingPointResort",
      room: "SingletonRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid period"
  end

  test "should reject invalid hotel" do
    get pricing_url, params: {
      period: "Summer",
      hotel: "InvalidHotel",
      room: "SingletonRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid hotel"
  end

  test "should reject invalid room" do
    get pricing_url, params: {
      period: "Summer",
      hotel: "FloatingPointResort",
      room: "InvalidRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid room"
  end
end
