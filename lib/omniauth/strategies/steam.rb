require 'omniauth-openid'
require 'multi_json'

module OmniAuth
  module Strategies
    class Steam < OmniAuth::Strategies::OpenID
      args :api_key

      option :api_key, nil
      option :name, "steam"
      option :identifier, "http://steamcommunity.com/openid"

      uid { steam_id }

      info do
        begin
        {
          "nickname" => player["personaname"],
          "name"     => player["realname"],
          "location" => [player["loccityid"], player["locstatecode"], player["loccountrycode"]].compact.join(", "),
          "image"    => player["avatarmedium"],
          "urls"     => {
            "Profile" => player["profileurl"],
            "FriendList" => friend_list_url
          }
        }
        rescue MultiJson::ParseError => exception
          fail!(:steamError, exception)
          {}
        end
      end

      extra do
        begin
          { "raw_info" => player }
        rescue MultiJson::ParseError => exception
          fail!(:steamError, exception)
          {}
        end
      end

      def callback_phase
        return fail!(:invalid_credentials) unless valid_params? && valid_openid?

        super
      end

      private

      def valid_openid?
        request.params['openid.ns'] == 'http://specs.openid.net/auth/2.0' &&
          request.params['openid.identity'].start_with?('https://steamcommunity.com/openid/id/') &&
          request.params['openid.claimed_id'].start_with?('https://steamcommunity.com/openid/id/')
      end

      def valid_params?
        request.params.keys.all? do |key|
          allowed_params.include?(key)
        end
      end

      def allowed_params
        [
          '_method',
          'openid.ns',
          'openid.mode',
          'openid.op_endpoint',
          'openid.claimed_id',
          'openid.identity',
          'openid.return_to',
          'openid.response_nonce',
          'openid.assoc_handle',
          'openid.signed',
          'openid.sig'
        ]
      end

      def raw_info
        @raw_info ||= options.api_key ? MultiJson.decode(Net::HTTP.get(player_profile_uri)) : {}
      end

      def player
        @player ||= raw_info["response"]["players"].first
      end

      def steam_id
        @steam_id ||= begin
                        claimed_id = openid_response.display_identifier.split('/').last
                        expected_uri = %r{\Ahttps?://steamcommunity\.com/openid/id/#{claimed_id}\Z}
                        unless expected_uri.match(openid_response.endpoint.claimed_id)
                          raise 'Steam Claimed ID mismatch!'
                        end
                        claimed_id
                      end
      end

      def player_profile_uri
        URI.parse("https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=#{options.api_key}&steamids=#{steam_id}")
      end

      def friend_list_url
        URI.parse("https://api.steampowered.com/ISteamUser/GetFriendList/v0001/?key=#{options.api_key}&steamid=#{steam_id}&relationship=friend")
      end
    end
  end
end
