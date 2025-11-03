module AiApi
  def self.call(body)
    puts "Calling AI API with body: #{body}"
    conn = Faraday.new(url: Rails.configuration.x.rate_api_base_url) do |faraday|
      faraday.headers['token'] = Rails.configuration.x.rate_api_token
      faraday.headers['Content-Type'] = 'application/json'
      faraday.request :json
      faraday.response :json
      faraday.options.timeout = Rails.configuration.x.rate_api_deadline.to_i
    end

    conn.post('/pricing') do |req|
      req.body = body
    end
  end
end