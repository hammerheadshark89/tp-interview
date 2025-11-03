require 'faraday'
require_relative 'ai_api'
require_relative 'cache'
require_relative 'price_id'

class PricingController < ApplicationController
  VALID_PERIODS = %w[Summer Autumn Winter Spring].freeze
  VALID_HOTELS = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  VALID_ROOMS = %w[SingletonRoom BooleanTwin RestfulKing].freeze

  @@cache = Cache.new

  before_action :validate_params

  def index
    # Overview:
    # - Validate parameters
    # - Look up the price in the cache
    #   - On cache hit, return the price
    #   - On cache miss, we will have a list of candidates for refreshing (which includes the target price id)
    # - Call the AI API with the candidates
    # - Add the references to the cache
    # - Return the price of the target price id

    target_price_id = PriceId.new(params[:period], params[:hotel], params[:room])

    result = @@cache.get_ref_or_refresh_candidates(target_price_id)
    if result[0]
      puts "Cache hit for #{target_price_id.period} #{target_price_id.hotel} #{target_price_id.room}"
      render json: result[0].to_proxy_api_response_json()
      return
    end

    puts "Cache miss for #{target_price_id.period} #{target_price_id.hotel} #{target_price_id.room}"
    candidates = result[1]
    request_body = {
      attributes: candidates.map { |c| { period: c.period, hotel: c.hotel, room: c.room } }
    }.to_json
    
    fetch_time = Time.now

    begin
      response = AiApi.call(request_body)
    rescue => e
      return render json: { error: "Failed to get pricing: #{e.message}" }, status: :internal_server_error
    end
    
    if response.success?
      refs = make_references_from_ai_response(target_price_id, fetch_time, response.body)
      if refs.nil?
        return render json: { error: "Failed to get pricing: requested ID is missing from response body" }, status: :internal_server_error
      end
      @@cache.set(refs)
      # n.b. target price id is the first element of the list
      render json: refs[0].to_proxy_api_response_json()
    else
      # We don't know what the format of the response body is, just return it.
      render json: { error: "Failed to get pricing: #{response.status} #{response.body}" }, status: :internal_server_error
    end
  end

  private

  def validate_params
    # Validate required parameters
    unless params[:period].present? && params[:hotel].present? && params[:room].present?
      return render json: { error: "Missing required parameters: period, hotel, room" }, status: :bad_request
    end

    # Validate parameter values
    unless VALID_PERIODS.include?(params[:period])
      return render json: { error: "Invalid period. Must be one of: #{VALID_PERIODS.join(', ')}" }, status: :bad_request
    end

    unless VALID_HOTELS.include?(params[:hotel])
      return render json: { error: "Invalid hotel. Must be one of: #{VALID_HOTELS.join(', ')}" }, status: :bad_request
    end

    unless VALID_ROOMS.include?(params[:room])
      return render json: { error: "Invalid room. Must be one of: #{VALID_ROOMS.join(', ')}" }, status: :bad_request
    end
  end
end
